extends "test_rendered_ui.gd"

func key(code: Key, ctrl: bool=false, unicode: int=0, window_id: int=0) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.ctrl_pressed=ctrl;event.pressed=pressed;event.unicode=unicode
		event.window_id=window_id
		for popup in root.find_children("*","PopupMenu",true,false):
			if popup.visible: event.window_id=popup.get_window_id()
		Input.parse_input_event(event);await process_frame
func text_in(field: LineEdit, text: String) -> void:
	await reveal_control(field)
	await click_at(field.get_global_rect().get_center())
	await key(KEY_A,true)
	for ch in text: await key(KEY_NONE,false,ch.unicode_at(0))
	await key(KEY_ENTER)
	await settle()
func drag_at(from: Vector2, to: Vector2) -> void:
	var press:=InputEventMouseButton.new();press.position=from;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;Input.parse_input_event(press);await process_frame
	var move:=InputEventMouseMotion.new();move.position=to;move.relative=to-from;move.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(move);await settle()
	var release:=InputEventMouseButton.new();release.position=to;release.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(release);await settle()
func asset_tab(editor, index: int) -> void:
	var tabs: TabContainer=editor.asset_list.get_parent().get_parent().get_parent()
	var bar:=tabs.get_tab_bar()
	await click_at(bar.global_position+bar.get_tab_rect(index).get_center())
func run() -> void:
	var script=load("res://addons/strategic_map_editor/workbench.gd")
	if script==null or not script.can_instantiate(): check(false,"compile");quit(1);return
	wb=script.new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false
	root.add_child(wb);current_scene=wb
	await settle()
	await click_button("Canvas 制作 · workshop_s1")
	if not is_instance_valid(wb.workshop_s1_panel): check(false,"normal workbench entry");quit(1);return
	var editor=wb.workshop_s1_panel
	await asset_tab(editor,1)
	await click_button("载入 10 件自有灰盒小样")
	check(editor.session.snapshot().asset_refs.size()==10,"UI imports ten graybox assets")
	for i in range(10):
		var rect: Rect2=editor.asset_list.get_item_rect(i)
		await click_at(editor.asset_list.global_position+rect.get_center())
		await click_button("放置所选资产")
		var pos:=Vector2(200+(i%5)*290,350+(i/5)*380)
		await click_at(editor.canvas.global_position+editor.canvas.pan+pos*editor.canvas.zoom)
	check(editor.session.snapshot().manual_entities.size()==10,"ten assets placed from normal UI")
	await capture("w1_ten_assets")
	await click_button("编辑所选资产描述")
	await settle()
	var asset_editor
	for child in editor.get_children():
		if child.get_script()==load("res://addons/strategic_map_editor/workshop_s1/ui/asset_editor.gd"): asset_editor=child
	check(asset_editor!=null,"asset metadata editor opens")
	if asset_editor==null: quit(1);return
	await capture("w1_asset_editor")
	var original_anchor: float=asset_editor.preview.descriptor.anchor_px[0]
	var anchor_point: Vector2=asset_editor.preview.global_position+asset_editor.preview._origin+Vector2(asset_editor.preview.descriptor.anchor_px[0],asset_editor.preview.descriptor.anchor_px[1])*asset_editor.preview._scale
	await drag_at(anchor_point,anchor_point+Vector2(20,0))
	check(float(asset_editor.preview.descriptor.anchor_px[0])>original_anchor,"real preview drag changes anchor")
	check(editor.session.snapshot().asset_refs[asset_editor.asset_ref].anchor_px[0]==original_anchor,"preview does not mutate original version")
	await capture("w1_anchor_draft")
	await text_in(asset_editor.label_field,"灰盒坡岸新版本")
	await click_button("确认黄色 paint 包含完整阴影")
	check(asset_editor.confirmed_paint.button_pressed,"visible paint confirmation reachable")
	await click_button("预览差异后保存新版本")
	check(editor.session.snapshot().asset_refs.size()==11,"metadata UI creates independent version")
	check(editor.session.snapshot().asset_refs.values().any(func(a): return a.label=="灰盒坡岸新版本"),"normal text input changes metadata label")
	await click_button("新增简单高面（W1 原型）")
	check(editor.session.snapshot().surfaces.size()==2,"UI creates W1 raised plane")
	await asset_tab(editor,0)
	await text_in(editor.x_field.get_line_edit(),"600")
	await text_in(editor.y_field.get_line_edit(),"500")
	await reveal_control(editor.surface_picker)
	await click_at(editor.surface_picker.get_global_rect().get_center())
	print("SUPPORT_PICKER_BEFORE ",editor.surface_picker.selected," popup=",editor.surface_picker.get_popup().visible," window=",editor.surface_picker.get_popup().get_window_id()," embedded=",editor.surface_picker.get_popup().is_embedded())
	print("FOCUS_BEFORE ",editor.surface_picker.get_popup().get_focused_item())
	await key(KEY_DOWN,false,0,editor.surface_picker.get_popup().get_window_id())
	print("FOCUS_DOWN1 ",editor.surface_picker.get_popup().get_focused_item())
	await key(KEY_DOWN,false,0,editor.surface_picker.get_popup().get_window_id())
	print("FOCUS_DOWN2 ",editor.surface_picker.get_popup().get_focused_item())
	await key(KEY_ENTER,false,0,editor.surface_picker.get_popup().get_window_id())
	print("SUPPORT_PICKER_AFTER ",editor.surface_picker.selected," popup=",editor.surface_picker.get_popup().visible)
	await click_button("应用对象属性")
	check(editor.session.snapshot().manual_entities[-1].surface_id=="prototype_top","normal UI explicitly attaches object to raised surface")
	await capture("w1_surface_prototype")
	await asset_tab(editor,1)
	await text_in(editor.surface_height.get_line_edit(),"120")
	await click_button("应用高面原型高度")
	var plan: Array=editor.canvas.Plan.build(editor.session.snapshot())
	check(plan.any(func(e): return e.entity_id==editor.selected_id and is_equal_approx(e.position.y,380.0)),"height edit moves same projected attachment")
	await capture("w1_surface_height_changed")
	check(editor.session.save_file(output.path_join("w1_assets.shwork.json")).ok,"save portable project and all immutable assets")
	var other=editor.Session.new()
	check(other.load_file(output.path_join("w1_assets.shwork.json")).ok and not other.read_only,"saved project and resources editable after reopen")
	await capture("w1_saved")
	print("WORKSHOP_ASSETS_UI ",JSON.stringify({"failures":failures,"viewport":[root.size.x,root.size.y],"evidence_type":"automated_viewport_input_replay"}))
	root.remove_child(wb);wb.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
