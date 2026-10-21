extends SceneTree
var failures: Array=[]
var checks:=0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func terrace(id: String, parent: String="ground", height: float=60.0, outline: Array=[]) -> Dictionary:
	var ring: Array=outline if not outline.is_empty() else [[200,200],[700,200],[700,650],[200,650]]
	return {"surface_id":id,"kind":"terrace","parent_surface_id":parent,"height":height,"outline":ring,"edge_styles":ring.map(func(_p):return "cliff"),"edge_widths":ring.map(func(_p):return 0.0),"top_color":"c4bd85","edge_color":"ac9569","locked":false}
func _initialize() -> void:
	if not ResourceLoader.exists("res://addons/strategic_map_editor/workshop_s1/terrain_geometry.gd"):
		check(false,"W4 editable terrain geometry must exist");quit(1);return
	var T=load("res://addons/strategic_map_editor/workshop_s1/terrain_geometry.gd")
	var P=load("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
	var Session=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=Session.new()
	check(s.dispatch({"op":"add_terrain","surface":terrace("t1")}).ok,"single editable terrace transaction")
	var t2:=terrace("t2","t1",30,[[300,260],[550,260],[550,430],[300,430]])
	check(s.dispatch({"op":"add_terrain","surface":t2}).ok,"second nested level")
	check(s.dispatch({"op":"add_terrain","surface":terrace("t3","t2",20,[[350,290],[480,290],[480,380],[350,380]])}).ok,"third nested level")
	check(is_equal_approx(P.height(s.snapshot(),"t3"),110.0),"heights inherit parent offsets")
	var hash: String=s.Model.input_hash(s.snapshot())
	check(not s.dispatch({"op":"add_terrain","surface":terrace("t4","t3",10,[[370,310],[450,310],[450,350],[370,350]])}).ok and s.Model.input_hash(s.snapshot())==hash,"fourth level refused atomically")
	check(not s.dispatch({"op":"update_terrain","surface_id":"t1","patch":{"parent_surface_id":"t3"}}).ok,"surface dependency cycle refused")
	check(not s.dispatch({"op":"add_terrain","surface":terrace("overlap")}).ok,"sibling overlap refused")
	var ramp: Dictionary={"surface_id":"r1","kind":"ramp","height":0.0,"from_surface_id":"ground","to_surface_id":"t1","start":[450,780],"end":[450,580],"width":48.0,"style":"dirt","locked":false}
	check(s.dispatch({"op":"add_terrain","surface":ramp}).ok,"legal ground-to-top ramp")
	var ground:=Vector2(450,690);var screen: Vector2=P.project_point(s.snapshot(),ground,"r1")
	check(is_equal_approx(P.height(s.snapshot(),"r1",0,ground),27.0) and P.ground_point(s.snapshot(),screen,"r1").distance_to(ground)<0.01,"ramp variable height and shared inverse")
	check(not T.contains(s.snapshot(),"ground",PackedVector2Array([Vector2(300,300),Vector2(310,300),Vector2(310,310),Vector2(300,310)])),"ground cannot support objects beneath raised terrain")
	check(not T.contains(s.snapshot(),"t1",PackedVector2Array([Vector2(500,300),Vector2(560,300),Vector2(560,400),Vector2(500,400)])),"whole footprint cannot straddle nested top")
	var source: Dictionary=s.snapshot();var bad: Dictionary=ramp.duplicate(true);bad.surface_id="bad";bad.end=[900,580]
	check(not s.dispatch({"op":"add_terrain","surface":bad}).ok,"unsupported ramp endpoint refused")
	check(s.Model.input_hash(source)==s.Model.input_hash(s.snapshot()),"failed ramp preserves complete project")
	check(s.undo() and s.redo(),"terrain/ramp use existing undo history")
	print("WORKSHOP_TERRAIN ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
