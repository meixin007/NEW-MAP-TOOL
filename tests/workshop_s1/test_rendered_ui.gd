extends SceneTree
## Automated viewport input replay. This is not a claim of manual/native acceptance.
var failures: Array[String] = []
var wb
var output := ""
func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://workshop_s1_tests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message);printerr("FAIL: ",message)
func button_named(node: Node, caption: String):
	if node is Button and node.text == caption and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var result = button_named(child,caption)
		if result != null: return result
	return null
func settle(frames: int = 12) -> void:
	for i in range(frames): await process_frame
func click_at(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point;motion.global_position=point;motion.relative=point-root.get_mouse_position()
	Input.parse_input_event(motion)
	await settle(2)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()
func click_button(caption: String) -> void:
	var target = button_named(wb,caption)
	if target==null and caption in ["载入 10 件自有灰盒小样","新增简单高面（W1 原型）","应用高面原型高度"]:
		var toggle=button_named(wb,"开发诊断 / 原型")
		if toggle!=null:await reveal_control(toggle);await click_at(toggle.get_global_rect().get_center());target=button_named(wb,caption)
	if target == null: check(false,"button missing: "+caption);return
	await reveal_control(target)
	var visible_rect: Rect2=target.get_global_rect()
	var ancestor: Node=target.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents: visible_rect=visible_rect.intersection(ancestor.get_global_rect())
		ancestor=ancestor.get_parent()
	if not visible_rect.has_area(): check(false,"button has no visible hit area: "+caption);return
	await click_at(visible_rect.get_center())
func reveal_control(target: Control) -> void:
	var parent: Node=target.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			for attempt in range(60):
				var viewport: Rect2=parent.get_global_rect()
				var control_rect:=target.get_global_rect()
				if control_rect.position.y>=viewport.position.y and control_rect.end.y<=viewport.end.y: break
				var event:=InputEventMouseButton.new()
				event.position=viewport.get_center()
				event.button_index=MOUSE_BUTTON_WHEEL_DOWN if control_rect.end.y>viewport.end.y else MOUSE_BUTTON_WHEEL_UP
				event.pressed=true
				Input.parse_input_event(event)
				var release:=event.duplicate() as InputEventMouseButton
				release.pressed=false
				Input.parse_input_event(release)
				await settle(2)
		parent=parent.get_parent()
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png")) == OK,"save rendered screenshot")
func run() -> void:
	var script = load("res://addons/strategic_map_editor/workbench.gd")
	if script == null or not script.can_instantiate(): check(false,"workbench compile");quit(1);return
	wb = script.new()
	wb.restore_last_map_on_start = false
	wb.layout_persistence_enabled = false
	root.add_child(wb)
	current_scene = wb
	await settle()
	await capture("w0_legacy")
	await click_button("▸ 更多工具 · 参考图 / 检查 / 恢复 / 布局")
	await click_button("Canvas 制作 · workshop_s1")
	check(is_instance_valid(wb.workshop_s1_panel),"real UI opens project mode")
	if not is_instance_valid(wb.workshop_s1_panel): quit(1);return
	var editor = wb.workshop_s1_panel
	await click_button("放置手工对象（灰盒）")
	await click_at(editor.canvas.global_position+editor.canvas.pan+Vector2(600,450)*editor.canvas.zoom)
	check(editor.session.snapshot().manual_entities.size() == 1,"viewport event places marker")
	await capture("w0_new_object")
	await click_button("撤销")
	check(editor.session.snapshot().manual_entities.is_empty(),"normal button undo")
	await click_button("重做")
	check(editor.session.snapshot().manual_entities.size() == 1,"normal button redo")
	await click_button("新增 v4 注记（统一事务）")
	check(editor.session.snapshot().legacy_document.features.size() == 1,"bridge through normal button")
	await click_button("撤销")
	check(editor.session.snapshot().legacy_document.features.is_empty() and editor.session.snapshot().manual_entities.size() == 1,"one mixed history")
	await click_button("选择 / 拖动")
	var start: Vector2 = editor.canvas.global_position+editor.canvas.pan+Vector2(600,440)*editor.canvas.zoom
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var move := InputEventMouseMotion.new()
	move.position = start+Vector2(80,40)
	move.relative = Vector2(80,40)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await settle()
	press = InputEventMouseButton.new()
	press.position = move.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = false
	Input.parse_input_event(press)
	await settle()
	check(float(editor.session.snapshot().manual_entities[0].ground_xy[0]) > 650,"viewport drag commits")
	await capture("w0_dragged")
	check(editor.session.save_file(output.path_join("w0_ui.shwork.json")).ok,"save UI project")
	await capture("w0_saved")
	await click_button("返回旧地图")
	check(not is_instance_valid(wb.workshop_s1_panel),"back to original UI")
	await settle()
	await capture("w0_returned")
	print("WORKSHOP_RENDERED_UI ",JSON.stringify({"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"viewport":[root.size.x,root.size.y],"evidence_type":"automated_viewport_input_replay"}))
	root.remove_child(wb)
	wb.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
