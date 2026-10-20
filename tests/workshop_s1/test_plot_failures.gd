extends "test_plots.gd"
func _initialize() -> void:
	Plot=load("res://addons/strategic_map_editor/workshop_s1/plot_generator.gd");Geometry=load("res://addons/strategic_map_editor/workshop_s1/plot_geometry.gd");Brush=load("res://addons/strategic_map_editor/workshop_s1/brush_sampler.gd")
	var script=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=script.new()
	check(load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd").install(s,"user://workshop_s1_tests/w3_negative_"+str(OS.get_process_id())).ok,"fixtures")
	var refs: Dictionary=s.snapshot().asset_refs;var tree: String=refs.keys()[6];var ground: String=refs.keys()[8]
	var farm:=plot("farm","farmland",[[100,100],[1450,100],[1450,850],[100,850]],ground);farm.spacing=[200.0,130.0];farm.scale_range=[0.9,1.0];farm.density=1.0;farm.cluster_strength=0.0
	check(s.dispatch({"op":"add_recipe","recipe":farm}).ok,"finite farmland cells")
	check(s.snapshot().materialized_snapshot.entities.size()>10,"nonempty farmland")
	var source: Dictionary=s.snapshot();var selected: Dictionary=source.materialized_snapshot.entities[0]
	var wide: Dictionary=refs[ground].duplicate(true);wide.asset_version="wide_middle";wide.ground_footprint=[[-240,-100],[240,-100],[240,100],[-240,100]]
	check(s.dispatch({"op":"add_asset_version","descriptor":wide,"adopt_entity_ids":[]}).ok,"wide polygon test asset")
	var p: Dictionary=s.snapshot();var e: Dictionary=selected.duplicate(true);e.asset_ref=wide.asset_id+"@wide_middle";e.ground_xy=[700,450]
	var ribbon: Dictionary={"entity_id":"road","kind":"ribbon","surface_id":"ground","polygons":[s.Model.Paths.strip(Vector2(100,450),Vector2(1400,450),16,16)],"ground_xy":[700,450],"local_height":0.0}
	var resolved: Dictionary=Plot.resolve(p,[ribbon],[e])
	check(not resolved.entities.any(func(item):return item.entity_id==e.entity_id) and resolved.diagnostics.any(func(d):return d.code=="road_or_water"),"road through footprint middle rejected even though corners far away")
	var water:=ribbon.duplicate(true);water.entity_id="water";water.role="river"
	check(Plot.resolve(p,[water],[e]).entities.size()==1,"complete farmland footprint excludes water")
	var hole: Array=[[650,420],[750,420],[750,480],[650,480]]
	check(not Geometry.contains_polygon(farm.outer,[hole],load("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd").footprint(p,e)),"hole in middle of large footprint rejects entire cell")
	var clear:=plot("clear","clearance",[[640,350],[760,350],[760,600],[640,600]])
	check(s.dispatch({"op":"add_recipe","recipe":clear}).ok,"clearance covers multiple complete cells")
	check(s.snapshot().materialized_snapshot.entities.all(func(item):return not Geometry.overlaps_region(s.snapshot(),item,clear)),"farmland never fills permanent clearance")
	var before: Dictionary=s.snapshot();var too_large:=farm.duplicate(true);too_large.recipe_id="too_large";too_large.spacing=[16,16];too_large.outer=[[0,0],[1600,0],[1600,900],[0,900]]
	check(not s.dispatch({"op":"add_recipe","recipe":too_large}).ok and s.snapshot()==before,"over-budget job rejects whole candidate without partial edits")
	var unknown:=farm.duplicate(true);unknown.recipe_id="unknown_dependency";unknown.depends_on=["farm"]
	check(not s.dispatch({"op":"add_recipe","recipe":unknown}).ok and s.snapshot()==before,"unsupported explicit recipe dependency is refused rather than ignored")
	var malformed: Dictionary=Brush.recipe("bad_erase","erase",[[100,100],[1400,800]],100,tree,"ground");malformed.erase_manual="false"
	check(not s.dispatch({"op":"apply_brush","recipe":malformed}).ok and s.snapshot()==before,"malformed erase flag cannot become implicit manual deletion")
	var forest:=plot("forest","forest",[[50,50],[1400,50],[1400,850],[50,850]],tree)
	check(s.dispatch({"op":"add_recipe","recipe":forest}).ok,"forest reuses path/farm protection")
	check(s.dispatch({"op":"set_recipe_locked","recipe_id":"forest","locked":true}).ok,"lock region saves fixed child snapshots")
	var locked: Dictionary=s.snapshot();var protected: Array=locked.manual_overrides.fixed.values()
	check(not protected.is_empty() and protected.all(func(item):return item.locked and item.management=="fixed"),"all region children locked together")
	check(not s.dispatch({"op":"update_recipe","recipe_id":"forest","patch":{"seed":123}}).ok and s.snapshot()==locked,"locked recipe changes rejected")
	if not protected.is_empty():
		check(not s.dispatch({"op":"delete_entity","entity_id":protected[0].entity_id}).ok,"locked child cannot be deleted")
		check(not s.dispatch({"op":"update_entity","entity_id":protected[0].entity_id,"patch":{"ground_xy":[1300,850]}}).ok,"locked child cannot be dragged")
	var erase: Dictionary=Brush.recipe("erase_all","erase",[[0,450],[1600,450]],512,tree,"ground")
	check(s.dispatch({"op":"apply_brush","recipe":erase}).ok,"erase whole visible area")
	check(protected.all(func(item):return s.snapshot().materialized_snapshot.entities.any(func(e2):return e2.entity_id==item.entity_id and e2.ground_xy==item.ground_xy)),"broad eraser preserves every locked fixed child")
	check(s.dispatch({"op":"set_recipe_locked","recipe_id":"forest","locked":false}).ok,"explicit region unlock")
	check(s.snapshot().manual_overrides.fixed.is_empty(),"unlock removes only region-owned lock snapshots")
	var support_session=script.new();check(load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd").install(support_session,"user://workshop_s1_tests/w3_support_"+str(OS.get_process_id())).ok,"support fixtures")
	check(support_session.dispatch({"op":"add_surface_prototype","surface":{"surface_id":"top","height":60,"outline":[[400,300],[800,300],[800,600],[400,600]]}}).ok,"explicit W1 support plane")
	forest.surface_id="top";forest.asset_weights=[{"asset_ref":support_session.snapshot().asset_refs.keys()[6],"weight":1.0}];check(support_session.dispatch({"op":"add_recipe","recipe":forest}).ok,"region stores selected support")
	var sp: Dictionary=support_session.snapshot();var entity_geometry=load("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd")
	check(sp.materialized_snapshot.entities.all(func(item):return Geometry.contains_polygon(sp.surfaces[1].outline,[],entity_geometry.footprint(sp,item))),"all generated footprints fully supported, no automatic height guessing")
	print("WORKSHOP_PLOT_FAILURES ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
