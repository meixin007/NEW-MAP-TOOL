extends "../workshop_s1/test_templates_ui.gd"
func run() -> void:
	wb=load("res://addons/strategic_map_editor/workbench.gd").new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle(20);await click_button("Canvas 制作 · workshop_s1");await settle(15);editor=wb.workshop_s1_panel
	for name in ["w67_mountain_pass","w67_riverside_city","w67_hillside_village","fortification_candidate1"]:
		await project_file_dialog("open",ProjectSettings.globalize_path("res://samples/"+name+".shwork.json"))
		check(not editor.session.read_only,"sample editable "+name)
		var signature: String=editor.session.authority_signature()
		var first: Dictionary=editor.session.view().manual_entities[0]
		await select_entity(first.entity_id)
		await text_in(editor.x_field.get_line_edit(),str(float(first.ground_xy[0])+1.0));await click_button("应用对象属性")
		while editor.session.job_in_progress():await process_frame
		await settle(3)
		check(editor.session.authority_signature()!=signature,"normal sample object move "+name)
		await click_button("撤销");check(editor.session.authority_signature()==signature,"normal sample move undo "+name)
		await text_in(editor.title_field,editor.session.view().title+" · 回归");await click_button("应用名称")
		check(editor.session.authority_signature()!=signature,"normal sample title edit "+name)
		await click_button("撤销");check(editor.session.authority_signature()==signature,"normal sample undo "+name)
		await project_file_dialog("save",output.path_join(name+".shwork.json"))
		await project_file_dialog("open",output.path_join(name+".shwork.json"))
		check(not editor.session.read_only and editor.session.authority_signature()==signature,"normal sample save/reopen "+name)
		await click_button("适合窗口");await capture(name)
		await asset_tab(editor,8);await click_button("采用当前完整范围")
		await text_in(editor.export_panel.scale_field.get_line_edit(),"0.6")
		await text_in(editor.export_panel.destination,output.path_join(name+"_export"));await click_button("开始导出冻结快照")
		var start:=Time.get_ticks_msec()
		while editor.export_panel.adapter.busy and Time.get_ticks_msec()-start<60000:await process_frame
		check(editor.export_panel.last_result.get("ok",false),"normal sample export "+name+" "+editor.export_panel.progress_label.text)
		if not editor.export_panel.last_result.get("ok",false):continue
		await click_button("打开导出清单只读预览");await custom_dialog(editor.export_panel.preview_dialog,output.path_join(name+"_export/manifest.json"))
		await settle(60)
		if not is_instance_valid(editor.export_panel.preview_window):await capture(name+"_preview_failure")
		check(is_instance_valid(editor.export_panel.preview_window) and editor.export_panel.preview_window.visible,"normal sample independent preview "+name)
		if is_instance_valid(editor.export_panel.preview_window):editor.export_panel.preview_window.hide()
		await asset_tab(editor,0)
	print("REVIEW_SAMPLES_UI ",JSON.stringify({"failures":failures,"scope":"automated native controls; original source samples unchanged; visual approval pending"}))
	wb.queue_free();await settle(10);quit(0 if failures.is_empty() else 1)
