extends SceneTree
var failures: Array[String]=[]
var checks:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message);printerr("FAIL: ",message)
func recipe(id: String, type: String, coordinates: Array) -> Dictionary:
	var points: Array=[]
	var segments: Array=[]
	for i in range(coordinates.size()):
		points.append({"point_id":"p"+str(i),"ground_xy":coordinates[i],"width":24.0})
		if i>0: segments.append({"segment_id":"s"+str(i-1),"from":"p"+str(i-1),"to":"p"+str(i)})
	return {"recipe_id":id,"kind":"path","path_type":type,"name":id,"control_points":points,"segments":segments,"seed":42,"surface_id":"ground","style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
func _initialize() -> void:
	if not FileAccess.file_exists("res://addons/strategic_map_editor/workshop_s1/path_generator.gd"): printerr("RED: path generator not implemented");quit(1);return
	var session_script=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
	if session_script==null or not session_script.can_instantiate(): printerr("FAIL: path session compile");quit(1);return
	var s=session_script.new()
	var samples=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd")
	check(samples.install(s,"user://workshop_s1_tests/path_"+str(OS.get_process_id())).ok,"sample asset import")
	var refs: Dictionary=s.snapshot().asset_refs
	var wall_ref: String=refs.keys()[1]
	var gate_ref: String=refs.keys()[0]
	var tower_ref: String=refs.keys()[3]
	var building_ref: String=refs.keys()[5]
	var logic_before: Dictionary=s.snapshot().legacy_document
	var road:=recipe("road","road",[[100,200],[700,200],[1350,200]])
	check(s.dispatch({"op":"add_recipe","recipe":road}).ok,"editable road creation")
	check(s.snapshot().legacy_document==logic_before,"visual road never grants game passage")
	var after: Dictionary=s.snapshot()
	check(after.materialized_snapshot.entities.size()==2,"one stable ribbon entity per road segment")
	var stable_id: String=after.materialized_snapshot.entities[1].entity_id
	check(s.dispatch({"op":"update_path_point","recipe_id":"road","point_id":"p0","patch":{"ground_xy":[100,240],"width":36.0}}).ok,"edit point and width")
	check(s.snapshot().materialized_snapshot.stats.rebuilt_segments==1 and s.snapshot().materialized_snapshot.stats.reused_segments==1,"local edit rebuilds affected segment only")
	check(s.snapshot().materialized_snapshot.entities[1].entity_id==stable_id,"unaffected stable identity")
	var wall:=recipe("wall","wall",[[200,500],[732,500],[1264,500]])
	wall.wall_asset_ref=wall_ref
	wall.roles=[{"role_id":"start","point_id":"p0","asset_ref":tower_ref,"ground_xy":[200,500],"orientation":0.0},{"role_id":"gate","point_id":"p1","asset_ref":gate_ref,"ground_xy":[732,500],"orientation":0.0},{"role_id":"end","point_id":"p2","asset_ref":tower_ref,"ground_xy":[1264,500],"orientation":0.0}]
	check(s.dispatch({"op":"add_recipe","recipe":wall}).ok,"walls with gate and tower roles")
	var entities: Array=s.snapshot().materialized_snapshot.entities
	var generated: Array=entities.filter(func(e): return e.get("recipe_id")=="wall" and e.get("role")=="wall")
	check(generated.size()==6,"six unscaled socket-connected wall segments")
	check(not s.snapshot().materialized_snapshot.diagnostics.any(func(d): return d.get("recipe_id")=="wall"),"exact prepared geometry has no wall gap diagnostic")
	var fixed_id: String=generated[0].entity_id
	check(s.dispatch({"op":"fix_entity","entity_id":fixed_id}).ok,"fix generated child")
	var fixed: Dictionary=s.snapshot().materialized_snapshot.entities.filter(func(e):return e.entity_id==fixed_id)[0]
	var deleted_id: String=generated[1].entity_id
	check(s.dispatch({"op":"delete_entity","entity_id":deleted_id}).ok,"persistent generated deletion")
	var detached_id: String=generated[2].entity_id
	check(s.dispatch({"op":"detach_entity","entity_id":detached_id}).ok,"detach preserves entity id")
	check(s.dispatch({"op":"update_entity","entity_id":detached_id,"patch":{"ground_xy":[520,610]}}).ok,"manual detached object moves")
	for seed in range(50):
		check(s.dispatch({"op":"update_recipe","recipe_id":"wall","patch":{"seed":seed}}).ok,"bounded regeneration "+str(seed))
	entities=s.snapshot().materialized_snapshot.entities
	check(entities.filter(func(e):return e.entity_id==fixed_id)[0].ground_xy==fixed.ground_xy,"fixed transform survives fifty regenerations")
	check(not entities.any(func(e):return e.entity_id==deleted_id),"deleted candidate never revives")
	var detached: Array=entities.filter(func(e):return e.entity_id==detached_id)
	check(detached.size()==1 and detached[0].management=="manual" and detached[0].ground_xy==[520,610],"one detached identity and manual move survive")
	var before: Dictionary=s.snapshot()
	check(not s.dispatch({"op":"split_path_segment","recipe_id":"wall","segment_id":"s0","ground_xy":[400,500],"point_id":"inserted"}).ok,"ambiguous topology with fixed object reports conflict")
	check(s.snapshot()==before,"topology conflict atomic")
	check(s.dispatch({"op":"split_path_segment","recipe_id":"road","segment_id":"s0","ground_xy":[400,220],"point_id":"inserted"}).ok,"unprotected split returns stable segment mapping")
	check(s.snapshot().recipes[0].segments[0].segment_id=="s0","split keeps original first segment identity")
	var roadside: Dictionary=recipe("side","road",[[100,800],[1350,800]])
	roadside.roadside={"asset_ref":building_ref,"side":"right","spacing":200.0,"offset":100.0}
	check(s.dispatch({"op":"add_recipe","recipe":roadside}).ok,"limited roadside layout")
	check(s.snapshot().materialized_snapshot.entities.any(func(e):return e.get("recipe_id")=="side" and e.get("role")=="roadside"),"legal building candidates placed")
	check(s.save_file("user://workshop_s1_tests/paths/project.shwork.json").ok,"save editable path with fixed/deleted/detached intent")
	var other=session_script.new()
	var reopened: Dictionary=other.load_file("user://workshop_s1_tests/paths/project.shwork.json")
	check(reopened.ok and not other.read_only,"reload paths remains editable: "+str(reopened.get("error","")))
	check(other.dispatch({"op":"update_recipe","recipe_id":"wall","patch":{"seed":999}}).ok,"reloaded generator remains editable")
	check(not other.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==deleted_id),"tombstone persists through save/reopen")
	print("WORKSHOP_PATHS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
