extends SceneTree

var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	var path := "res://addons/strategic_map_editor/workshop_s1/session_transaction.gd"
	if not FileAccess.file_exists(path):
		printerr("RED: workshop session has not been implemented")
		quit(1)
		return
	var script = load(path)
	if script == null or not script.can_instantiate():
		printerr("FAIL: session cannot compile")
		quit(1)
		return
	var s = script.new()
	var original: Dictionary = s.snapshot()
	check(s.dispatch({"op":"add_manual", "entity":{"entity_id":"one","kind":"marker","ground_xy":[200,300],"surface_id":"ground","local_height":0.0,"label":"对象"}}).ok, "normal command commits")
	check(s.undo_stack.size() == 1, "one command one history")
	var copy: Dictionary = s.snapshot()
	copy.manual_entities[0].label = "polluted"
	check(s.snapshot().manual_entities[0].label == "对象", "snapshot deep isolates")
	var committed: Dictionary = s.snapshot()
	check(s.dispatch({"op":"update_manual", "entity_id":"one","patch":{"ground_xy":[-1,20]}}).ok == false, "invalid candidate rejected")
	check(s.snapshot() == committed and s.undo_stack.size() == 1, "failed command preserves state and history")
	check(s.undo() and s.snapshot() == original, "undo entire project")
	check(s.redo() and s.snapshot() == committed, "redo stable identity and derived snapshot")
	s.begin_preview()
	check(s.preview({"op":"update_manual", "entity_id":"one","patch":{"ground_xy":[260,310]}}).ok, "drag preview valid")
	check(s.snapshot() == committed, "preview never mutates authority")
	s.cancel_preview()
	check(s.snapshot() == committed and s.undo_stack.size() == 1, "escape cancels without history")
	s.begin_preview()
	for i in range(12):
		s.preview({"op":"update_manual", "entity_id":"one","patch":{"ground_xy":[260+i,310]}})
	check(s.commit_preview().ok and s.undo_stack.size() == 2, "twelve motion events one transaction")
	check(s.save_file("user://workshop_s1_tests/session.shwork.json").ok, "atomic save")
	check(not s.is_dirty(), "saved signature clean")
	var saved_bytes := FileAccess.get_file_as_bytes("user://workshop_s1_tests/session.shwork.json")
	s.dispatch({"op":"rename","title":"未成功写入的修订"})
	s._replace_file = func(_from, _to): return ERR_CANT_CREATE
	check(not s.save_file("user://workshop_s1_tests/session.shwork.json").ok, "replacement failure is explicit")
	check(FileAccess.get_file_as_bytes("user://workshop_s1_tests/session.shwork.json") == saved_bytes and s.is_dirty(), "failed replacement preserves old file and unsaved revision")
	s._replace_file = Callable()
	s.undo()
	var other = script.new()
	check(other.load_file("user://workshop_s1_tests/session.shwork.json").ok, "reload project")
	check(not other.read_only, "same-version reload remains editable")
	check(JSON.parse_string(JSON.stringify(other.snapshot())) == JSON.parse_string(JSON.stringify(s.snapshot())), "reload all authority and snapshot")
	var before: Dictionary = other.snapshot()
	check(not other.load_text('{"schema_version":999}').ok and other.snapshot() == before, "future format preserves current project")
	check(not other.load_text('{bad').ok and other.snapshot() == before, "corrupt JSON preserves current project")
	check(not other.save_file("user://workshop_s1_tests/missing_parent/../bad.shwork.json").ok, "reject ambiguous path")
	var legacy_script = load("res://addons/strategic_map_editor/document.gd")
	var legacy = legacy_script.new()
	var legacy_original: Dictionary = s.snapshot().legacy_document
	check(s.dispatch({"op":"legacy_add_feature","kind":"label","points":[[20,20]],"label":"注记"}).ok, "legacy bridge uses same transaction")
	check(s.undo() and s.snapshot().legacy_document == legacy_original, "legacy and workshop share undo")
	check(legacy.undo_stack.is_empty(), "no second legacy history owner")
	check(s.save_recovery("user://workshop_s1_tests/recovery.json", {"tool":"marker","points":[[1,2]]}).ok, "whole-project recovery")
	var recovered = script.new()
	check(recovered.load_recovery("user://workshop_s1_tests/recovery.json").ok, "recover authority and draft")
	check(JSON.parse_string(JSON.stringify(recovered.recovered_draft)) == JSON.parse_string(JSON.stringify({"tool":"marker","points":[[1,2]]})), "draft survives recovery")
	var bad: Dictionary = s.snapshot()
	bad.manual_entities.append(bad.manual_entities[0].duplicate(true))
	check(not s.replace_project(bad).ok, "duplicate identity rejected")
	bad = s.snapshot()
	bad.asset_refs["bad"] = {"texture_ref":"../escape.png"}
	check(not s.replace_project(bad).ok, "unsafe dependency rejected")
	print("WORKSHOP_SESSION ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
