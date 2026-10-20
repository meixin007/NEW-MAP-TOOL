extends SceneTree
## Uses only the 24c55c1 API; expected red on that fixed head, green after repair.
const Editor=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_editor.gd")
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var editor=Editor.new();root.add_child(editor);await process_frame;await process_frame
	var s=editor.session;var c=editor.canvas
	var added: Dictionary=s.dispatch({"op":"add_manual","entity":{"entity_id":"receipt","kind":"marker","ground_xy":[200,200],"surface_id":"ground","local_height":0,"label":"receipt"}})
	if not added.ok:printerr(added);editor.queue_free();await process_frame;quit(1);return
	editor.select_entity("receipt");c._drag_entity=s.view().manual_entities[0];c._dragging=true
	c._preview_drag({"op":"update_entity","entity_id":"receipt","patch":{"ground_xy":[220,210]}})
	var first: Dictionary=editor.capture_draft();editor._recovery_revision=s.revision;editor._recovery_draft=first
	check(not editor.has_unsaved_editor_session(),"unchanged receipt covered")
	c._preview_drag({"op":"update_entity","entity_id":"receipt","patch":{"ground_xy":[260,240]}})
	check(first!=editor.capture_draft(),"target changes recovery draft")
	check(editor.has_unsaved_editor_session(),"target change invalidates receipt")
	c.cancel();editor.queue_free();await process_frame
	print("PR1_RECEIPT_COUNTEREXAMPLE ",JSON.stringify({"checks":3,"failures":failures}));quit(0 if failures.is_empty() else 1)
