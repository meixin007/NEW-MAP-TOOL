extends SceneTree
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message)
func _initialize() -> void:
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var Snap=load("res://addons/strategic_map_editor/workshop_s1/snap_resolver.gd");var D=load("res://addons/strategic_map_editor/workshop_s1/editor_draft.gd");var C=load("res://addons/strategic_map_editor/workshop_s1/compound_model.gd");var s=S.new();var p: Dictionary=s.snapshot()
	var e: Dictionary=C.entity("yard","ground",Vector2(200,200),C.plan("courtyard"));p.materialized_snapshot.entities=[e]
	p.style_profile.merge({"grid_kind":"hex","grid_size":32,"grid_visible":false,"grid_snap":true,"edge_snap":true},true)
	var a: Dictionary=Snap.drag(p,e,Vector2(451,377),0.5);var b: Dictionary=Snap.drag(p,e,Vector2(451,377),2)
	check(a==b and a.reason=="grid","hex grid independent of visibility and zoom; takes precedence over edge")
	check(Snap.hex_round(Vector2(a.ground_xy[0],a.ground_xy[1]),32).distance_to(Vector2(a.ground_xy[0],a.ground_xy[1]))<0.001,"hex grid rounding stable")
	p.style_profile.grid_snap=false;p.style_profile.edge_snap=false;check(Snap.drag(p,e,Vector2(451,377),1).reason=="none","disabled overlay snapping leaves point unchanged")
	check(not D.validate({"library_fields":{"label_text":17}}).is_empty(),"malformed library recovery refused")
	check(not D.validate({"selection_ids":"bad"}).is_empty(),"malformed recovered multiselect refused")
	var feature: Dictionary={"id":"note","kind":"label","name":"旧标签","points":[[200,200]],"style":{},"locked":false}
	check(s.dispatch({"op":"legacy_add_feature","kind":"label","points":[[200,200]],"label":"旧标签"}).ok,"legacy label sole authoring authority")
	var id: String=s.snapshot().legacy_document.features[0].id
	check(s.dispatch({"op":"update_label","feature_id":id,"label":"新标签","ground_xy":[250,260]}).ok,"label text and anchor edit")
	check(s.snapshot().legacy_document.features[0].name=="新标签" and s.snapshot().legacy_document.features[0].points[0]==[250,260],"label is stored in original document")
	check(s.undo() and s.snapshot().legacy_document.features[0].name=="旧标签","label edit one undo")
	check(s.dispatch({"op":"delete_label","feature_id":id}).ok and s.snapshot().legacy_document.features.is_empty(),"label deletion")
	print("WORKSHOP_EDITOR_CONTRACT ",JSON.stringify({"failures":failures}));quit(0 if failures.is_empty() else 1)
