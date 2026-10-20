extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message);printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var script = load("res://addons/strategic_map_editor/workbench.gd")
	if script == null or not script.can_instantiate():
		printerr("FAIL: original workbench cannot compile")
		quit(1)
		return
	var wb = script.new()
	wb.restore_last_map_on_start = false
	wb.layout_persistence_enabled = false
	root.add_child(wb)
	current_scene = wb
	await process_frame
	await process_frame
	var legacy: Dictionary = wb.doc.snapshot()
	wb._open_workshop_s1()
	await process_frame
	check(is_instance_valid(wb.workshop_s1_panel), "new mode opens from original workbench")
	if not is_instance_valid(wb.workshop_s1_panel): quit(1);return
	var editor = wb.workshop_s1_panel
	check(editor.canvas.size.x > 300, "usable canvas viewport")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = editor.canvas.pan+Vector2(400,400)*editor.canvas.zoom
	event.pressed = true
	editor.canvas.mode = "marker"
	editor.canvas._gui_input(event)
	await process_frame
	check(editor.session.snapshot().manual_entities.size() == 1, "canvas input creates new object")
	check(wb.doc.snapshot() == legacy and wb.doc.undo_stack.is_empty(), "legacy state and history unchanged")
	check(wb.has_unsaved_editor_session(), "plugin exit guard includes new project")
	check(wb.save_editor_session().ok, "host saves entire new project recovery")
	check(not wb.has_unsaved_editor_session(), "recovery satisfies host exit guard without marking project clean")
	check(editor.session.is_dirty(), "recovery is not normal project save")
	check(editor.session.save_file("user://workshop_s1_tests/ui.shwork.json").ok, "UI-owned session saves")
	editor.history(false)
	check(editor.session.snapshot().manual_entities.is_empty(), "UI undo routes to project session")
	editor.history(true)
	check(editor.session.snapshot().manual_entities.size() == 1, "UI redo stable")
	editor.name_field.text = "恢复中的未应用名称"
	editor.name_field.text_changed.emit(editor.name_field.text)
	check(editor.has_unsaved_authoring() and editor._property_dirty,"unapplied input is dirty")
	check(editor.save_recovery().ok,"recovery includes unapplied fields")
	editor._property_dirty = false
	editor.refresh()
	editor.restore_recovery()
	check(editor._property_dirty and editor.name_field.text == "恢复中的未应用名称", "reopen restores pending fields without applying")
	check(editor.session.snapshot().manual_entities[0].label == "手工对象", "recovery does not silently apply fields")
	editor._property_dirty = false
	editor.refresh()
	check(editor.Samples.install(editor.session,"user://workshop_s1_tests/recovery_assets_"+str(OS.get_process_id())).ok,"metadata recovery fixture")
	var metadata=editor.AssetEditor.new();metadata.session=editor.session;metadata.asset_ref=editor.session.snapshot().asset_refs.keys()[0];editor.add_child(metadata);metadata.popup_centered(Vector2i(1000,700))
	metadata.label_field.text="未保存资产描述"
	metadata.preview.descriptor.ground_footprint=[]
	check(editor.has_pending_fields(),"unfinished metadata polygon participates in dirty guard")
	check(editor.save_recovery().ok,"full recovery includes unfinished asset editor")
	editor.remove_child(metadata);metadata.queue_free();await process_frame
	editor.restore_recovery()
	var restored=editor.active_asset_editor()
	check(restored!=null and restored.label_field.text=="未保存资产描述" and restored.preview.descriptor.ground_footprint.is_empty(),"unfinished asset metadata restores without applying")
	if restored!=null: editor.remove_child(restored);restored.queue_free()
	wb._close_workshop_s1()
	await process_frame
	check(wb.canvas.is_visible_in_tree() and wb.doc.snapshot() == legacy, "old mode returns intact")
	root.remove_child(wb)
	wb.queue_free()
	await process_frame
	print("WORKSHOP_INTEGRATED_UI ", JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
