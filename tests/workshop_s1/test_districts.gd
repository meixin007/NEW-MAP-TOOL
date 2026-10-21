extends SceneTree
var failures: Array=[]
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func road(id: String,a: Array,b: Array) -> Dictionary:
	return {"recipe_id":id,"kind":"path","path_type":"road","name":id,"control_points":[{"point_id":"a","ground_xy":a,"width":28},{"point_id":"b","ground_xy":b,"width":28}],"segments":[{"segment_id":"s","from":"a","to":"b"}],"surface_id":"ground","style":"dirt","seed":42,"roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
func _initialize() -> void:
	if not ResourceLoader.exists("res://addons/strategic_map_editor/workshop_s1/district_generator.gd"):
		check(false,"W5 bounded district generator must exist");quit(1);return
	var D=load("res://addons/strategic_map_editor/workshop_s1/district_generator.gd");var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=S.new()
	check(s.dispatch({"op":"add_recipe","recipe":road("main",[80,480],[1520,480])}).ok,"authoritative main road")
	var r: Dictionary=D.recipe("district","orthogonal",[[80,80],[1520,80],[1520,880],[80,880]],"ground",["main"])
	r.vacancy=0;r.future_fraction=0
	check(s.dispatch({"op":"add_recipe","recipe":r}).ok,"orthogonal district")
	var first: Dictionary=s.snapshot();var compounds: Array=first.materialized_snapshot.entities.filter(func(e):return e.kind=="compound")
	check(compounds.size()>3,"nonempty legal courtyard district")
	check(not first.materialized_snapshot.lots.is_empty() and first.materialized_snapshot.lots.all(func(l):return l.has("lot_id") and l.has("entrance")),"stable typed lots and entrances")
	var ids: Array=first.materialized_snapshot.lots.map(func(l):return l.lot_id)
	check(s.dispatch({"op":"update_recipe","recipe_id":"district","patch":{"density":0.4,"vacancy":0.2,"future_fraction":0.2}}).ok,"parameters adjust without topology rewrite")
	check(s.snapshot().materialized_snapshot.lots.map(func(l):return l.lot_id)==ids,"lot ids survive density and role adjustments")
	check(s.snapshot().materialized_snapshot.lots.any(func(l):return l.lot_role=="future") and s.snapshot().materialized_snapshot.lots.any(func(l):return l.lot_role=="permanent_clearance"),"future and permanent clearance have distinct roles")
	check(s.dispatch({"op":"update_recipe","recipe_id":"district","patch":{"layout":"along_road","density":1,"vacancy":0,"future_fraction":0}}).ok,"same boundary along-road mode")
	check(s.snapshot().materialized_snapshot.entities.filter(func(e):return e.kind=="compound").size()>3,"along-road legal courtyards")
	var narrow: Dictionary=D.recipe("narrow","orthogonal",[[100,100],[150,100],[150,800],[100,800]],"ground",["main"])
	check(s.dispatch({"op":"add_recipe","recipe":narrow}).ok and s.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.get("recipe_id")=="narrow"),"narrow boundary terminates with diagnostic")
	print("WORKSHOP_DISTRICTS ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
