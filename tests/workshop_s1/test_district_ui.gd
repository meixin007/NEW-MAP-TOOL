extends "test_terrain_ui.gd"
func asset_tab(_host,index: int) -> void:
	var tabs: TabContainer=editor.asset_list.get_parent().get_parent().get_parent();var bar:=tabs.get_tab_bar();var rect:=bar.get_tab_rect(bar.current_tab).intersection(Rect2(Vector2.ZERO,bar.size))
	await click_at(bar.global_position+rect.get_center())
	for i in range(tabs.get_tab_count()+1):
		if tabs.current_tab==index:return
		await key(KEY_RIGHT if tabs.current_tab<index else KEY_LEFT)
	check(false,"normal keyboard reaches tab "+str(index))
func room_apply() -> void:
	while editor.session.job_in_progress():await process_frame
	await process_frame
	check(editor.session.has_preview(),"room preview ready: "+editor.status.text)
	if editor.session.has_preview():await click_button("应用房间预览（一次撤销）");await settle()
func new_path(caption: String,coordinates: Array) -> void:
	await asset_tab(editor,2);await click_button(caption)
	for point in coordinates:await ground_click(Vector2(point[0],point[1]))
	await key(KEY_ENTER);await settle()
func region(caption: String,coordinates: Array,polygon: bool=false) -> void:
	await asset_tab(editor,3);await click_button(caption)
	for point in coordinates:await ground_click(Vector2(point[0],point[1]))
	if polygon:await key(KEY_ENTER)
	await apply_plot()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3:check(false,"material and approved tree packs required");quit(1);return
	var script=load("res://addons/strategic_map_editor/workbench.gd");wb=script.new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle(30);await click_button("Canvas 制作 · workshop_s1");await settle(30)
	editor=wb.workshop_s1_panel
	if not is_instance_valid(editor):check(false,"W5 entry");quit(1);return
	await pack_dialog(args[1]);await pack_dialog(args[2]);check(editor.session.snapshot().asset_refs.size()==8,"normal import raw roof plus unchanged approved trees")
	await click_button("应用参考纸色（当前项目）")
	await click_button("载入 10 件自有灰盒小样")
	await asset_tab(editor,5);await click_button("应用参考斜俯视（当前项目）");await choose_option(editor.room_panel.material_picker,1)
	await click_button("画房间／院落（两角）");await ground_click(Vector2(160,100));await ground_click(Vector2(400,340));await room_apply()
	check(editor.session.snapshot().manual_entities.size()==1,"normal canvas authors structured courtyard")
	if editor.session.snapshot().manual_entities.is_empty():wb.queue_free();await settle();quit(1);return
	var courtyard_id: String=editor.session.snapshot().manual_entities[0].entity_id
	await capture("w5_ui_courtyard")
	await click_button("显示本组屋顶");await click_button("预览房间／屋顶参数");await room_apply();check(not editor.session.snapshot().manual_entities[0].room_plan.roof_visible,"normal roof toggle preserves floor/hole/walls")
	await capture("w5_ui_roof_hidden");await click_button("撤销");await click_button("重做");await click_button("撤销")
	await select_list(editor.room_panel.walls,2);await text_in(editor.room_panel.opening_width.get_line_edit(),"32");await click_button("预览院墙／门洞");await room_apply()
	check(editor.session.snapshot().manual_entities[0].room_plan.walls[2].openings[0].width==32,"normal editable entrance opening")
	await select_entity(courtyard_id);await text_in(editor.x_field.get_line_edit(),"300");await click_button("应用对象属性")
	check(editor.session.snapshot().manual_entities[0].ground_xy[0]==300,"manual courtyard moved via normal fields")
	await new_path("画道路",[[80,500],[1520,500]])
	await asset_tab(editor,6);await choose_option(editor.district_panel.material_picker,1)
	await click_button("画矩形街区（两角）");await ground_click(Vector2(60,60));await ground_click(Vector2(1540,900));await apply_plot()
	check(editor.session.snapshot().recipes.any(func(r):return r.kind=="district"),"normal UI creates orthogonal district")
	var compounds: Array=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.kind=="compound" and e.management=="generated")
	check(not compounds.is_empty(),"normal district produces editable courtyards")
	await capture("w5_ui_orthogonal_lots")
	await choose_option(editor.district_panel.layout,1);await text_in(editor.district_panel.vacancy.get_line_edit(),"0");await text_in(editor.district_panel.future.get_line_edit(),"0");await text_in(editor.district_panel.density.get_line_edit(),"1");await click_button("预览街区参数");await apply_plot()
	await capture("w5_ui_along_road_lots")
	await asset_tab(editor,3)
	for i in range(editor.plot_panel.primary.item_count):
		if str(editor.plot_panel.primary.get_item_metadata(i)).begins_with("tree_unit"):await choose_option(editor.plot_panel.primary,i);break
	await region("画矩形区域（两角）",[[80,60],[1520,840]])
	var forest_id: String=editor.session.snapshot().recipes[-1].recipe_id
	var trees: Array=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("recipe_id")==forest_id)
	var deleted_tree: String=""
	if not trees.is_empty():deleted_tree=trees[0].entity_id;await select_entity(deleted_tree);await click_button("删除选中对象")
	check(not deleted_tree.is_empty(),"normal generated forest child selected and deleted")
	await new_path("画城墙",[[100,900],[800,900],[1500,900]]);await select_list(editor.path_panel.points,1);await click_button("在所选控制点插门 / 角楼")
	var gates: Array=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("role")=="role")
	var gate_id: String=""
	if not gates.is_empty():gate_id=gates[0].entity_id;await select_entity(gate_id);await click_button("固定生成子对象")
	check(not gate_id.is_empty(),"normal gate inserted and fixed; engineering fixture explicitly labeled")
	compounds=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.kind=="compound" and e.management=="generated")
	if not compounds.is_empty():
		var fixed: Dictionary=compounds[0];await select_entity(fixed.entity_id);await click_button("固定生成子对象")
		await asset_tab(editor,6);await text_in(editor.district_panel.seed.get_line_edit(),"888");await click_button("预览街区参数");await apply_plot()
		check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==fixed.entity_id and e.ground_xy==fixed.ground_xy and e.management=="fixed"),"normal regeneration retains fixed entrance courtyard")
	await asset_tab(editor,3)
	for i in range(editor.plot_panel.recipes.item_count):
		if editor.plot_panel.recipes.get_item_metadata(i)==forest_id:await select_list(editor.plot_panel.recipes,i);break
	await text_in(editor.plot_panel.seed.get_line_edit(),"999");await click_button("预览所选区域参数");await apply_plot()
	check(not editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==deleted_tree),"normal regeneration preserves deleted tree")
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==gate_id and e.management=="fixed"),"normal regeneration preserves fixed gate")
	check(editor.session.snapshot().manual_entities[0].ground_xy[0]==300,"normal regeneration preserves moved courtyard")
	await capture("w5_ui_moved_courtyard_deleted_tree_fixed_gate_regenerated")
	await project_file_dialog("save",output.path_join("w5_ui.shwork.json"));check(not editor.session.is_dirty(),"normal W5 save")
	await project_file_dialog("open",output.path_join("w5_ui.shwork.json"));check(not editor.session.read_only and editor.session.snapshot().manual_entities[0].entity_id==courtyard_id,"normal W5 editable reopen")
	await asset_tab(editor,5);await click_button("画房间／院落（两角）");await ground_click(Vector2(1300,780));await click_button("保存恢复副本");check(editor.canvas.compound_points.size()==1,"unfinished room draft saved")
	await key(KEY_ESCAPE);await click_button("恢复项目");await settle()
	if editor.confirmation.visible:await click_at(editor.confirmation.confirm_button.get_global_rect().get_center());await settle()
	check(editor.canvas.compound_points.size()==1,"unfinished room draft restores");await capture("w5_ui_recovered_draft");await key(KEY_ESCAPE)
	print("WORKSHOP_DISTRICT_UI ",JSON.stringify({"failures":failures}));wb.queue_free();await settle();quit(0 if failures.is_empty() else 1)
