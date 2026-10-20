extends "test_plots_ui.gd"
func click_at(point: Vector2) -> void:
	await super.click_at(root.get_final_transform()*point)
func terrain_apply() -> void:
	while editor.session.job_in_progress():await process_frame
	await process_frame
	check(editor.session.has_preview(),"terrain preview: "+editor.status.text)
	await click_button("应用地形预览（一次撤销）");await settle()
func ground_click(point: Vector2,id: String="ground") -> void:
	var P=load("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
	await world_click(P.project_point(editor.session.snapshot(),point,id))
func run() -> void:
	var script=load("res://addons/strategic_map_editor/workbench.gd")
	if script==null or not script.can_instantiate():check(false,"workbench compile");quit(1);return
	wb=script.new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle(30);await click_button("Canvas 制作 · workshop_s1");await settle(30)
	if not is_instance_valid(wb.workshop_s1_panel):await capture("w4_entry_diagnostic")
	if wb.confirm.visible:await click_at(wb.confirm.confirm_button.get_global_rect().get_center());await settle(30)
	if not is_instance_valid(wb.workshop_s1_panel):check(false,"editor opens");quit(1);return
	editor=wb.workshop_s1_panel
	await asset_tab(editor,4);await capture("w4_terrain_panel");await click_button("画台地多边形")
	for xy in [[230,200],[750,200],[800,400],[750,640],[250,640],[200,400]]:await ground_click(Vector2(xy[0],xy[1]))
	await key(KEY_ENTER);await terrain_apply()
	check(editor.session.snapshot().surfaces.size()==2,"normal canvas terrain authoring")
	if editor.session.snapshot().surfaces.size()<2:wb.queue_free();await settle();quit(1);return
	var top: String=editor.session.snapshot().surfaces[1].surface_id
	await click_button("撤销");check(editor.session.snapshot().surfaces.size()==1,"one terrain undo");await click_button("重做")
	await select_list(editor.terrain_panel.surfaces,0)
	await text_in(editor.terrain_panel.height.get_line_edit(),"90")
	await select_list(editor.terrain_panel.vertices,3);await choose_option(editor.terrain_panel.edge,1);await text_in(editor.terrain_panel.spread.get_line_edit(),"60")
	await click_button("预览地形属性／顶点／所选边");await terrain_apply()
	check(editor.session.snapshot().surfaces[1].height==90 and editor.session.snapshot().surfaces[1].edge_styles[3]=="slope","normal height and per-edge slope edit")
	await choose_option(editor.terrain_panel.from_surface,0);await choose_option(editor.terrain_panel.to_surface,1)
	await click_button("画坡道（分别点击两端）");await ground_click(Vector2(580,850));await ground_click(Vector2(580,530),top);await terrain_apply()
	check(editor.session.snapshot().surfaces.size()==3,"explicit upper lower ramp through UI")
	await capture("w4_ui_terrain_ramp")
	await asset_tab(editor,1);await click_button("载入 10 件自有灰盒小样")
	await select_list(editor.asset_list,4);await click_button("放置所选资产");await ground_click(Vector2(450,430),top)
	check(editor.session.snapshot().manual_entities.size()==1 and editor.session.snapshot().manual_entities[0].surface_id==top,"normal click automatic full-footprint support")
	await asset_tab(editor,4);await select_list(editor.terrain_panel.surfaces,0);await text_in(editor.terrain_panel.height.get_line_edit(),"120");await click_button("预览地形属性／顶点／所选边");await terrain_apply()
	await capture("w4_ui_height_follow")
	await asset_tab(editor,3);await choose_option(editor.plot_panel.primary,6);await text_in(editor.plot_panel.density.get_line_edit(),"0.3")
	await click_button("放置笔刷（一笔一次撤销）");var old_history: int=editor.session.undo_stack.size();await ground_click(Vector2(420,300),top)
	var choice_button
	for b in wb.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.text.begins_with(top+" · 高度"):choice_button=b;break
	check(choice_button!=null,"ambiguous brush landing requires explicit face choice")
	if choice_button!=null:
		await capture("w4_ui_support_choice");await click_at(choice_button.get_global_rect().get_center());await ground_click(Vector2(420,300),top)
	await wait_plot_job()
	check(editor.session.snapshot().recipes.size()==1 and editor.session.snapshot().recipes[0].surface_id==top and editor.session.undo_stack.size()==old_history+1,"brush automatically chooses top and commits one stroke once")
	await click_button("撤销");await click_button("重做");await click_button("取消区域预览 / 计算")
	# A clean save, then normal open of the same editable project.
	await asset_tab(editor,0);await click_button("选择 / 拖动")
	await project_file_dialog("save",output.path_join("w4_ui.shwork.json"));check(not editor.session.is_dirty(),"normal save")
	await project_file_dialog("open",output.path_join("w4_ui.shwork.json"));check(not editor.session.read_only and editor.session.snapshot().surfaces.size()==3,"normal editable reopen")
	await asset_tab(editor,4);await click_button("画台地多边形");await ground_click(Vector2(1050,250));await ground_click(Vector2(1350,300))
	await click_button("保存恢复副本");check(editor.canvas.terrain_points.size()==2,"unfinished draft remains after recovery save")
	await key(KEY_ESCAPE);await settle();await click_button("恢复项目");await settle()
	if editor.confirmation.visible:await click_at(editor.confirmation.confirm_button.get_global_rect().get_center());await settle()
	check(editor.canvas.terrain_points.size()==2,"unfinished terrain draft restores")
	await capture("w4_ui_recovery_draft");await key(KEY_ESCAPE)
	print("WORKSHOP_TERRAIN_UI ",JSON.stringify({"failures":failures}));wb.queue_free();await settle();quit(0 if failures.is_empty() else 1)
