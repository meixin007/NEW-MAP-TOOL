extends "test_paths.gd"

func _initialize() -> void:
	var script=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
	if script==null or not script.can_instantiate(): printerr("FAIL: compile");quit(1);return
	var s=script.new()
	var sample_script=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd")
	check(sample_script.install(s,"user://workshop_s1_tests/negative_"+str(OS.get_process_id())).ok,"negative fixtures")
	var refs: Dictionary=s.snapshot().asset_refs
	var wall_ref: String=refs.keys()[1]
	var building_ref: String=refs.keys()[5]
	var short_path:=recipe("short","wall",[[50,80],[100,80]])
	short_path.wall_asset_ref=wall_ref
	check(s.dispatch({"op":"add_recipe","recipe":short_path}).ok,"short wall records intent")
	check(s.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.code=="short_gap"),"short gap reports prepared asset shortage")
	var acute:=recipe("acute","wall",[[200,100],[350,150]])
	acute.wall_asset_ref=wall_ref
	check(s.dispatch({"op":"add_recipe","recipe":acute}).ok,"unsupported angle records editable path")
	check(s.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.code=="missing_orientation"),"acute turn diagnostic, no PNG rotation")
	var side:=recipe("unsupported_side","road",[[100,850],[1400,850]])
	side.roadside={"asset_ref":building_ref,"side":"left","spacing":200.0,"offset":100.0}
	check(s.dispatch({"op":"add_recipe","recipe":side}).ok,"roadside unsupported side remains editable")
	check(s.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.code=="missing_front_variant"),"missing building front reported")
	var river_obstacle:=recipe("water_exclusion","river",[[100,700],[1400,700]])
	check(s.dispatch({"op":"add_recipe","recipe":river_obstacle}).ok,"visual river exclusion")
	var watery_side:=recipe("watery_side","road",[[100,800],[1400,800]])
	watery_side.roadside={"asset_ref":building_ref,"side":"right","spacing":200.0,"offset":100.0}
	check(s.dispatch({"op":"add_recipe","recipe":watery_side}).ok,"bounded roadside candidates near water")
	check(not s.snapshot().materialized_snapshot.entities.any(func(e):return e.get("recipe_id")=="watery_side" and e.get("role")=="roadside"),"complete building footprint avoids parallel water")
	check(s.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.get("recipe_id")=="watery_side" and d.code=="roadside_rejected"),"water rejection reason retained")
	var wide: Dictionary=refs[building_ref].duplicate(true)
	wide.asset_version="wide"
	wide.ground_footprint=[[-200,-180],[200,-180],[200,180],[-200,180]]
	check(s.dispatch({"op":"add_asset_version","descriptor":wide,"adopt_entity_ids":[]}).ok,"wide footprint fixture")
	var e: Dictionary={"entity_id":"manual_building","kind":"asset","asset_ref":wide.asset_id+"@wide","ground_xy":[600,450],"surface_id":"ground","local_height":0.0,"orientation":0.0,"scale":1.0,"label":"保护建筑","management":"manual"}
	check(s.dispatch({"op":"add_manual","entity":e}).ok,"manual building")
	var before: Dictionary=s.snapshot()
	var road:=recipe("crosses_middle","road",[[100,450],[1200,450]])
	var conflict: Dictionary=s.dispatch({"op":"add_recipe","recipe":road})
	check(not conflict.ok and conflict.error.contains("占地"),"road crossing middle caught although corners far from road")
	check(s.snapshot()==before,"failed generation adopts no partial road")
	var bad:=before.duplicate(true)
	bad.recipes[0].control_points[1].point_id=bad.recipes[0].control_points[0].point_id
	check(not s.replace_project(bad).ok,"duplicate control-point identity rejected")
	bad=before.duplicate(true)
	bad.materialized_snapshot.entities[0].ground_xy=[1,1]
	check(not s.load_text(JSON.stringify(bad)).ok,"same-version forged derived output rejected")
	bad=before.duplicate(true)
	bad.materialized_snapshot.generator_version="earlier_fixture"
	check(s.replace_project(bad).ok and s.read_only,"stale snapshot preserved read-only")
	check(not s.dispatch({"op":"rename","title":"bad"}).ok,"stale snapshot does not auto-regenerate")
	check(s.rebuild_derived().ok and not s.read_only and s.is_dirty(),"explicit rebuild preserves authority and becomes saveable revision")
	check(s.undo() and s.read_only,"rebuild undo restores readable prior snapshot")
	check(s.redo() and not s.read_only,"rebuild redo returns current snapshot")
	check(not s.save_file("user://workshop_s1_tests/old.map.json").ok,"new project cannot overwrite v4 suffix")
	var snap_session=script.new()
	check(sample_script.install(snap_session,"user://workshop_s1_tests/snap_"+str(OS.get_process_id())).ok,"snap fixtures")
	var snap_refs: Dictionary=snap_session.snapshot().asset_refs
	var wall: String=snap_refs.keys()[1]
	for id in ["a","b"]:
		check(snap_session.dispatch({"op":"add_manual","entity":{"entity_id":id,"kind":"asset","asset_ref":wall,"ground_xy":[300 if id=="a" else 600,300],"surface_id":"ground","local_height":0.0,"orientation":0.0,"scale":1.0,"label":id,"management":"manual"}}).ok,"manual snap asset "+id)
	check(snap_session.dispatch({"op":"snap_entity","entity_id":"a","source_socket":"b","target_entity_id":"b","target_socket":"a"}).ok,"compatible sockets snap without rotating PNG")
	check(is_equal_approx(snap_session.snapshot().manual_entities[0].ground_xy[0],456.0),"exact endpoint displacement")
	var snapped: Dictionary=snap_session.snapshot()
	check(not snap_session.dispatch({"op":"snap_entity","entity_id":"a","source_socket":"a","target_entity_id":"b","target_socket":"a"}).ok and snap_session.snapshot()==snapped,"same-facing sockets reject atomically")
	check(snap_session.undo() and not snap_session.snapshot().manual_entities[0].has("socket_binding"),"undo restores position and socket relation together")
	var legacy_script=load("res://addons/strategic_map_editor/document.gd")
	var legacy=legacy_script.new()
	legacy.add_feature("river",[[100,200],[500,300],[900,260]],"旧河流")
	var legacy_before: Dictionary=legacy.snapshot()
	var river_session=script.new()
	check(river_session.dispatch({"op":"import_legacy_rivers","legacy_document":legacy_before}).ok,"old v4 river imports through original validator")
	check(river_session.snapshot().legacy_document==legacy_before,"legacy river authority preserved")
	var river: Dictionary=river_session.snapshot().recipes[0]
	check(river_session.dispatch({"op":"update_path_point","recipe_id":river.recipe_id,"point_id":river.control_points[1].point_id,"patch":{"width":48.0}}).ok,"new river width UI command uses original ribbon sampler")
	check(river_session.snapshot().legacy_document==legacy_before,"visual width does not change old water or passage semantics")
	check(river_session.snapshot().materialized_snapshot.entities[0].source_algorithm=="legacy_art_ribbon.sample","river reuses original implementation")
	var canonical=load("res://addons/strategic_map_editor/workshop_s1/canonical.gd")
	var mixed_keys: Dictionary={"anchor":[1,2]}
	mixed_keys[&"default_orientation"]=0
	check(canonical.digest(mixed_keys)==canonical.digest(JSON.parse_string(JSON.stringify(mixed_keys))),"StringName keys normalize before lexical sort")
	var growth_session=script.new()
	check(sample_script.install(growth_session,"user://workshop_s1_tests/growth_"+str(OS.get_process_id())).ok,"asset growth fixtures")
	var growth_refs: Dictionary=growth_session.snapshot().asset_refs
	var courtyard: String=growth_refs.keys()[5]
	for id in ["grow","protected"]:
		check(growth_session.dispatch({"op":"add_manual","entity":{"entity_id":id,"kind":"asset","asset_ref":courtyard,"ground_xy":[400 if id=="grow" else 700,400],"surface_id":"ground","local_height":0.0,"orientation":0.0,"scale":1.0,"label":id,"management":"manual"}}).ok,"growth manual fixture "+id)
	var grown: Dictionary=growth_refs[courtyard].duplicate(true)
	grown.asset_version="grown";grown.ground_footprint=[[-400,-100],[400,-100],[400,100],[-400,100]]
	var growth_before: Dictionary=growth_session.snapshot()
	check(not growth_session.dispatch({"op":"add_asset_version","descriptor":grown,"adopt_entity_ids":["grow"]}).ok,"larger adopted asset rechecks other protected manual footprint")
	check(growth_session.snapshot()==growth_before,"asset growth conflict preserves old revision and assets")
	check(not growth_session.dispatch({"op":"update_manual","entity_id":"grow","patch":{"entity_id":"stolen_identity"}}).ok and growth_session.snapshot()==growth_before,"W0 compatibility command cannot bypass stable entity identity")
	print("WORKSHOP_PATH_FAILURES ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
