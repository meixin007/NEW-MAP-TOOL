extends "test_district_ui.gd"
func custom_dialog(dialog: FileDialog,path: String) -> void:
	check(dialog.visible,"normal template/preview file dialog")
	var offset:=Vector2(dialog.position) if dialog.is_embedded() else Vector2.ZERO
	await click_at(dialog.get_line_edit().get_global_rect().get_center()+offset);await key(KEY_A,true)
	for ch in path:await key(KEY_NONE,false,ch.unicode_at(0))
	await key(KEY_ENTER);await settle(20)
	if dialog.visible:await click_at(dialog.get_ok_button().get_global_rect().get_center()+offset);await settle(20)
func ctrl_item(list: ItemList,index: int) -> void:
	await reveal_control(list)
	var point: Vector2=root.get_final_transform()*(list.global_position+list.get_item_rect(index).get_center())
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.ctrl_pressed=true;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	await settle()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:check(false,"material pack required");quit(1);return
	wb=load("res://addons/strategic_map_editor/workbench.gd").new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb;await settle(30);await click_button("Canvas 制作 · workshop_s1");await settle(20);editor=wb.workshop_s1_panel
	await pack_dialog(args[1]);await asset_tab(editor,5);await choose_option(editor.room_panel.material_picker,1)
	for box in [[[160,120],[340,330]],[[500,120],[680,330]]]:
		await click_button("画房间／院落（两角）");await ground_click(Vector2(box[0][0],box[0][1]));await ground_click(Vector2(box[1][0],box[1][1]));await room_apply()
	await asset_tab(editor,0);await select_list(editor.object_list,0);await ctrl_item(editor.object_list,1);check(editor.selected_entity_ids().size()==2,"normal multi-select includes occluded list members")
	await asset_tab(editor,7);await click_button("保存所选为模板");await custom_dialog(editor.library_panel.dialog,output.path_join("courtyard_v1.shtemplate.json"));check(FileAccess.file_exists(output.path_join("courtyard_v1.shtemplate.json")),"normal template and thumbnail save")
	await capture("w6_template_saved")
	await click_button("新建工坊项目");await settle()
	if editor.confirmation.visible:await click_at(editor.confirmation.confirm_button.get_global_rect().get_center());await settle()
	await asset_tab(editor,7);await click_button("打开模板文件");await custom_dialog(editor.library_panel.dialog,output.path_join("courtyard_v1.shtemplate.json"));await click_button("放置当前模板（点画布）");await ground_click(Vector2(600,520))
	check(editor.session.snapshot().manual_entities.size()==2 and editor.session.snapshot().prefab_instances.size()==1,"normal cross-map paste creates independent complete group")
	if editor.session.snapshot().prefab_instances.is_empty():wb.queue_free();await settle();quit(1);return
	await select_list(editor.library_panel.groups,0);await text_in(editor.library_panel.dx.get_line_edit(),"40");await click_button("预览整组变换");check(editor.session.has_preview(),"normal group preview");await click_button("应用整组预览（一次撤销）");await click_button("撤销");await click_button("重做")
	await select_list(editor.library_panel.groups,0);await click_button("解组所选（一次撤销）");check(editor.session.snapshot().prefab_instances.is_empty() and editor.session.snapshot().manual_entities.size()==2,"normal ungroup editable")
	await click_button("显示网格");await choose_option(editor.library_panel.grid_kind,1);await click_button("启用网格吸附");await click_button("应用网格／吸附／图例")
	check(editor.session.snapshot().style_profile.grid_kind=="hex" and editor.session.snapshot().style_profile.grid_visible and editor.session.snapshot().style_profile.grid_snap,"grid visibility independent from snap, persisted options")
	await capture("w6_hex_grid")
	await click_button("显示网格");await click_button("应用网格／吸附／图例")
	await asset_tab(editor,0);await select_list(editor.object_list,0);await asset_tab(editor,7);await click_button("隐藏所选对象");check(editor.session.snapshot().manual_entities[0].hidden,"hidden object stays in list and authority")
	await click_button("显示所选对象")
	await text_in(editor.library_panel.label_text,"山河注记");await click_button("添加标签（点画布）");await ground_click(Vector2(800,300));check(editor.session.snapshot().legacy_document.features.size()==1,"normal editable label placement")
	await select_list(editor.library_panel.label_list,0);await text_in(editor.library_panel.label_text,"渡口");await click_button("预览标签修改");check(editor.session.has_preview(),"normal label preview");await click_button("应用标签预览（一次撤销）");check(editor.session.snapshot().legacy_document.features[0].name=="渡口","normal label text edit commits")
	await text_in(editor.library_panel.label_text,"未提交恢复标签");await click_button("保存恢复副本");check(editor.capture_draft().library_fields.label_dirty and editor.capture_draft().library_fields.label_text=="未提交恢复标签","label draft included in saved recovery");await click_button("取消标签输入／预览")
	await asset_tab(editor,8);await click_button("采用当前完整范围");await text_in(editor.export_panel.destination,output.path_join("normal_export"));await click_button("开始导出冻结快照")
	var begin:=Time.get_ticks_msec()
	while editor.export_panel.adapter.busy and Time.get_ticks_msec()-begin<30000:await process_frame
	check(editor.export_panel.last_result.get("ok",false),"normal export entry completes: "+editor.export_panel.progress_label.text)
	await capture("w7_export_complete")
	await click_button("打开导出清单只读预览");await custom_dialog(editor.export_panel.preview_dialog,output.path_join("normal_export/manifest.json"));check(is_instance_valid(editor.export_panel.preview_window) and editor.export_panel.preview_window.visible,"normal readonly preview window")
	if is_instance_valid(editor.export_panel.preview_window):editor.export_panel.preview_window.hide()
	await project_file_dialog("save",output.path_join("w67_ui.shwork.json"));await project_file_dialog("open",output.path_join("w67_ui.shwork.json"));check(not editor.session.read_only,"normal W6 metadata save/reopen")
	print("WORKSHOP_TEMPLATES_UI ",JSON.stringify({"failures":failures}));wb.queue_free();await settle(20);quit(0 if failures.is_empty() else 1)
