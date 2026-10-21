extends SceneTree
var failures: Array=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:
	var path: String="res://addons/strategic_map_editor/workshop_s1/template_library.gd"
	if not ResourceLoader.exists(path):check(false,"W6 template library must exist");quit(1);return
	var L=load(path);var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var C=load("res://addons/strategic_map_editor/workshop_s1/compound_model.gd");var s=S.new()
	check(s.dispatch({"op":"add_manual","entity":C.entity("house","ground",Vector2(320,360),C.plan("courtyard"))}).ok,"source courtyard")
	var t: Dictionary=L.capture(s.snapshot(),["house"],"map_group","庭院小组")
	check(t.ok,"capture relative group")
	if not t.ok:quit(1);return
	var other=S.new();check(other.dispatch({"op":"instantiate_template","template":t.template,"ground_xy":[700,600]}).ok,"cross-map snapshot placement")
	var p: Dictionary=other.snapshot();check(p.manual_entities.size()==1 and p.manual_entities[0].entity_id!="house" and p.prefab_instances.size()==1,"fresh identity and editable group record")
	var id: String=p.manual_entities[0].entity_id;var group: String=p.prefab_instances[0].instance_id
	check(other.dispatch({"op":"ungroup_instance","instance_id":group}).ok and other.snapshot().prefab_instances.is_empty(),"ungroup keeps entities")
	check(other.undo() and other.snapshot().prefab_instances.size()==1,"ungroup one undo")
	check(other.dispatch({"op":"update_entity","entity_id":id,"patch":{"label":"独立修改"}}).ok and s.snapshot().manual_entities[0].label!="独立修改","instance edits do not update source")
	check(other.load_text(JSON.stringify(other.snapshot())).ok and not other.read_only,"template instance survives JSON roundtrip")
	var before: String=other.Model.input_hash(other.snapshot())
	check(not other.dispatch({"op":"transform_entities","entity_ids":[id],"pivot":[700,600],"angle":0,"factor":100,"offset":[0,0]}).ok and other.Model.input_hash(other.snapshot())==before,"invalid group transform atomic refusal")
	var bad: Dictionary=t.template.duplicate(true);bad.preview_ref="../outside.png";check(not L.validate(bad).is_empty(),"template path traversal refused")
	print("WORKSHOP_TEMPLATES ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
