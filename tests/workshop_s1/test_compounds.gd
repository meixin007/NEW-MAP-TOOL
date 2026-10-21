extends SceneTree
var failures: Array=[]
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:
	if not ResourceLoader.exists("res://addons/strategic_map_editor/workshop_s1/compound_model.gd"):
		check(false,"W5 editable room/courtyard model must exist");quit(1);return
	var C=load("res://addons/strategic_map_editor/workshop_s1/compound_model.gd")
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=S.new()
	var plan: Dictionary=C.plan("courtyard",180,160,"residential")
	var e: Dictionary=C.entity("court","ground",Vector2(500,550),plan)
	check(s.dispatch({"op":"add_manual","entity":e}).ok,"editable courtyard transaction")
	check(s.snapshot().manual_entities[0].room_plan.rooms.size()>=3 and not s.snapshot().manual_entities[0].room_plan.holes.is_empty(),"courtyard keeps rooms and central void")
	var root: Dictionary=s.snapshot();var changed: Dictionary=plan.duplicate(true);changed.roof_visible=false
	check(s.dispatch({"op":"update_entity","entity_id":"court","patch":{"room_plan":changed}}).ok,"roof visibility edit")
	check(s.undo() and s.snapshot()==root and s.redo(),"roof toggle one undo with exact state")
	var P=load("res://addons/strategic_map_editor/workshop_s1/render_plan.gd")
	check(P.build(s.snapshot()).any(func(part):return part.entity_id=="court"),"shared render plan includes courtyard")
	var signature: String=s.Model.input_hash(s.snapshot());var bad: Dictionary=changed.duplicate(true);bad.rooms[0].rect=[-500,-500,20,20]
	check(not s.dispatch({"op":"update_entity","entity_id":"court","patch":{"room_plan":bad}}).ok and signature==s.Model.input_hash(s.snapshot()),"room outside complete courtyard footprint refused atomically")
	var room: Dictionary=C.plan("room",100,70,"storage");check(room.rooms.size()==1 and room.holes.is_empty(),"independent room semantics")
	var path: String="user://w5_compounds/courtyard.shwork.json";check(s.save_file(path).ok,"save compound")
	var reopened=S.new();var loaded: Dictionary=reopened.load_file(path);print("REOPEN ",JSON.stringify({"result":loaded,"read_only":reopened.read_only,"hash":reopened.Model.input_hash(reopened.snapshot()),"expected":signature}));check(loaded.ok and not reopened.read_only and reopened.Model.input_hash(reopened.snapshot())==signature,"editable compound reopen")
	print("WORKSHOP_COMPOUNDS ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
