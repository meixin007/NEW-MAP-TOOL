extends SceneTree
var checks:=0
var failures: Array[String]=[]
var Plot
var Geometry
var Brush
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func plot(id: String, type: String, outer: Array, ref: String="") -> Dictionary:
	return {"recipe_id":id,"kind":"plot","name":id,"plot_type":type,"shape":"polygon","outer":outer,"holes":[],"surface_id":"ground","seed":42,"density":0.65,"spacing":[96.0,64.0],"scale_range":[0.8,1.0],"asset_weights":[] if ref.is_empty() else [{"asset_ref":ref,"weight":1.0}],"cluster_strength":0.35,"locked":false}
func _initialize() -> void:
	var module: String="res://addons/strategic_map_editor/workshop_s1/plot_generator.gd"
	if not ResourceLoader.exists(module):check(false,"W3 plot generator must exist");quit(1);return
	Plot=load(module);Geometry=load("res://addons/strategic_map_editor/workshop_s1/plot_geometry.gd");Brush=load("res://addons/strategic_map_editor/workshop_s1/brush_sampler.gd")
	if Plot==null or Geometry==null or Brush==null or not Plot.can_instantiate():check(false,"W3 modules compile");quit(1);return
	var script=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
	var s=script.new()
	var samples=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd")
	check(samples.install(s,"user://workshop_s1_tests/w3_"+str(OS.get_process_id())).ok,"fixtures")
	var refs: Dictionary=s.snapshot().asset_refs
	var tree: String=refs.keys()[6]
	for shape in ["rectangle","ellipse","hexagon"]:
		var points: Array=Geometry.shape(shape,[100,100],[500,400])
		check(Geometry.validate(points,[]).is_empty(),shape+" geometry")
	var concave: Array=[[80,80],[1100,80],[1100,500],[700,500],[700,820],[80,820]]
	var hole: Array=[[260,250],[400,250],[400,400],[260,400]]
	check(Geometry.validate(concave,[hole]).is_empty(),"concave polygon with valid hole")
	check(not Geometry.validate([[0,0],[100,100],[0,100],[100,0]],[]).is_empty(),"self-intersection rejected")
	check(not Geometry.validate(concave,[[[10,10],[200,10],[200,200],[10,200]]]).is_empty(),"outside hole rejected")
	var region:=plot("forest","forest",concave,tree);region.holes=[hole]
	check(s.dispatch({"op":"add_recipe","recipe":region}).ok,"forest region transaction")
	var low: Dictionary=s.snapshot()
	check(low.materialized_snapshot.entities.size()>5,"nonempty deterministic forest")
	check(low.materialized_snapshot.entities.all(func(e):return Geometry.contains_polygon(region.outer,region.holes,load("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd").footprint(low,e))),"complete footprints stay inside concave outer and outside hole")
	check(s.dispatch({"op":"update_recipe","recipe_id":"forest","patch":{"density":0.95}}).ok,"increase density")
	var high: Dictionary=s.snapshot()
	var high_ids: Array=high.materialized_snapshot.entities.map(func(e):return e.entity_id)
	check(low.materialized_snapshot.entities.all(func(e):return e.entity_id in high_ids),"density adds candidates without renumbering or losing existing ones")
	var same: Dictionary=high.duplicate(true);same.materialized_snapshot={}
	check(s.Model.Paths.digest(s.Model.materialize(same).entities)==s.Model.Paths.digest(high.materialized_snapshot.entities),"same version/input rebuild matches")
	var chosen: Dictionary=high.materialized_snapshot.entities[0]
	check(s.dispatch({"op":"fix_entity","entity_id":chosen.entity_id}).ok,"fix region child")
	var removed: Dictionary=high.materialized_snapshot.entities[1]
	check(s.dispatch({"op":"delete_entity","entity_id":removed.entity_id}).ok,"persistent region deletion")
	var detached: Dictionary=high.materialized_snapshot.entities[2]
	check(s.dispatch({"op":"detach_entity","entity_id":detached.entity_id}).ok,"detach region child keeps identity")
	check(s.dispatch({"op":"update_entity","entity_id":detached.entity_id,"patch":{"ground_xy":[1300,600]}}).ok,"move detached child")
	var early_clear:=plot("early_clearance","clearance",[[450,100],[650,100],[650,700],[450,700]])
	check(s.dispatch({"op":"add_recipe","recipe":early_clear}).ok,"permanent clearance before 50 controlled regenerations")
	for seed in range(50):
		var result: Dictionary=s.dispatch({"op":"update_recipe","recipe_id":"forest","patch":{"seed":seed}})
		if not result.ok:check(false,"seed change "+str(seed)+" "+str(result));break
	var after: Dictionary=s.snapshot()
	check(after.materialized_snapshot.entities.any(func(e):return e.entity_id==chosen.entity_id and e.ground_xy==chosen.ground_xy and e.management=="fixed"),"50 seeds preserve fixed position")
	check(not after.materialized_snapshot.entities.any(func(e):return e.entity_id==removed.entity_id),"50 seeds preserve deletion")
	check(after.manual_entities.any(func(e):return e.entity_id==detached.entity_id and e.ground_xy==[1300,600]),"50 seeds preserve detached movement")
	check(after.materialized_snapshot.entities.filter(func(e):return e.get("management")=="generated").all(func(e):return not Geometry.overlaps_region(after,e,early_clear)),"50 seeds preserve permanent no-generation intent")
	var clear:=plot("clearance","clearance",[[450,100],[650,100],[650,700],[450,700]])
	check(s.dispatch({"op":"add_recipe","recipe":clear}).ok,"permanent clearance intent")
	var fixed: Array=s.snapshot().manual_overrides.fixed.values()
	check(s.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("management")=="generated").all(func(e):return not Geometry.overlaps_region(s.snapshot(),e,clear)),"generated forest excludes full clearance polygon")
	var before_erase: Dictionary=s.snapshot()
	var erase: Dictionary=Brush.recipe("erase","erase",[[50,50],[1100,800]],180.0,tree,"ground")
	check(s.dispatch({"op":"apply_brush","recipe":erase}).ok,"erase is one transaction")
	check(s.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==chosen.entity_id and e.management=="fixed"),"eraser preserves fixed children")
	check(s.undo() and s.snapshot()==before_erase,"one undo restores entire eraser stroke")
	check(s.redo(),"eraser redo")
	var stroke_a: Dictionary=Brush.recipe("stroke","place",[[100,100],[1000,100]],90.0,tree,"ground")
	var stroke_b: Dictionary=Brush.recipe("stroke","place",range(91).map(func(i):return [100+i*10,100]),90.0,tree,"ground")
	var project: Dictionary=s.Model.blank();project.asset_refs=refs
	check(s.Model.Paths.digest(Plot.build(stroke_a,project,{}).entities)==s.Model.Paths.digest(Plot.build(stroke_b,project,{}).entities),"low/high sampling same frozen stroke gives same candidate IDs/transforms")
	var path: String="user://workshop_s1_tests/w3_roundtrip_"+str(OS.get_process_id())+".shwork.json"
	check(s.save_file(path).ok,"save W3 recipes/assets")
	var other=script.new()
	check(other.load_file(path).ok and not other.read_only and other.Model.input_hash(other.snapshot())==s.Model.input_hash(s.snapshot()),"W3 project reopens editable with same authority")
	print("WORKSHOP_PLOTS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
