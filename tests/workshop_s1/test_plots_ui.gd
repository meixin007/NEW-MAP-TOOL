extends "test_paths_ui.gd"
var original_forest_id: String=""
func wait_plot_job() -> void:
	var started:=Time.get_ticks_msec()
	while editor.session.job_in_progress() and Time.get_ticks_msec()-started<20000:await process_frame
	await settle(3)
	check(not editor.session.job_in_progress(),"plot job finishes within bounded test time")
func apply_plot() -> void:
	await wait_plot_job()
	check(editor.session.has_preview(),"candidate ready for explicit apply: "+editor.status.text)
	if not editor.session.has_preview():return
	await click_button("应用区域预览（一次撤销）");await settle()
func region(caption: String, coordinates: Array, polygon: bool=false) -> void:
	await asset_tab(editor,3);await click_button(caption)
	for point in coordinates:await world_click(Vector2(point[0],point[1]))
	if polygon:await key(KEY_ENTER)
	await apply_plot()
func pack_dialog(path: String) -> void:
	await asset_tab(editor,1);await click_button("导入 W3 参考画风素材包")
	var dialog: FileDialog=editor.file_dialog
	check(dialog.visible,"normal asset-pack file dialog")
	var offset:=Vector2(dialog.position) if dialog.is_embedded() else Vector2.ZERO
	await click_at(dialog.get_line_edit().get_global_rect().get_center()+offset);await key(KEY_A,true)
	for ch in path:await key(KEY_NONE,false,ch.unicode_at(0))
	await key(KEY_ENTER);await settle()
	if dialog.visible:await click_at(dialog.get_ok_button().get_global_rect().get_center()+offset)
	await settle()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:check(false,"style pack path required");quit(1);return
	var script=load("res://addons/strategic_map_editor/workbench.gd")
	if script==null or not script.can_instantiate():quit(1);return
	wb=script.new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle();await click_button("Canvas 制作 · workshop_s1")
	if not is_instance_valid(wb.workshop_s1_panel):quit(1);return
	editor=wb.workshop_s1_panel
	await pack_dialog(args[1])
	check(editor.session.snapshot().asset_refs.size()==3,"normal UI imports three reference-style assets")
	if editor.session.snapshot().asset_refs.size()!=3:print(editor.status.text);quit(1);return
	await click_button("应用参考纸色（当前项目）")
	await region("画矩形区域（两角）",[[60,80],[1500,820]])
	check(editor.session.snapshot().recipes.size()==1,"rectangle forest through actual canvas")
	if editor.session.snapshot().recipes.is_empty():quit(1);return
	original_forest_id=editor.session.snapshot().recipes[0].recipe_id
	await capture("w3_forest_rectangle")
	await click_button("画洞（所选区域内）")
	for point in [[460,300],[680,300],[680,500],[460,500]]:await world_click(Vector2(point[0],point[1]))
	await key(KEY_ENTER);await apply_plot()
	check(editor.session.snapshot().recipes[0].holes.size()==1,"normal polygon hole added")
	await choose_option(editor.plot_panel.kind,4)
	await region("画矩形区域（两角）",[[760,80],[940,840]])
	check(editor.session.snapshot().recipes.any(func(r):return r.get("plot_type")=="clearance"),"permanent clearance region from UI")
	await choose_option(editor.plot_panel.kind,2);await choose_option(editor.plot_panel.primary,2)
	await region("画矩形区域（两角）",[[100,520],[1480,850]])
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.get("plot_type")=="farmland"),"legal finite farmland generated from reference asset")
	await new_path("画道路",[[80,450],[800,450],[1500,450]])
	await new_path("画河流（复用旧 ribbon）",[[80,190],[800,230],[1500,190]])
	await capture("w3_forest_farm_road_water")
	await asset_tab(editor,3);await choose_option(editor.plot_panel.kind,0);await choose_option(editor.plot_panel.primary,0)
	await choose_option(editor.plot_panel.secondary,2)
	await region("画圆 / 椭圆区域",[[1050,80],[1430,350]])
	await region("画六边形区域",[[100,80],[400,310]])
	await region("画多边形区域",[[100,300],[400,300],[400,420],[280,420],[280,500],[100,500]],true)
	check(editor.session.snapshot().recipes.filter(func(r):return r.kind=="plot").size()==6,"rectangle/ellipse/hex/concave regions coexist")
	await capture("w3_shapes_and_holes")
	var children: Array=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("plot_type")=="forest")
	check(children.size()>5,"forest child list populated")
	if children.size()<3:quit(1);return
	var fixed: Dictionary=children[0];var deleted: Dictionary=children[1];var detached: Dictionary=children[2]
	await select_entity(fixed.entity_id);await click_button("固定生成子对象")
	await select_entity(deleted.entity_id);await click_button("删除选中对象")
	await select_entity(detached.entity_id);await click_button("脱离生成器（保留身份）")
	await text_in(editor.x_field.get_line_edit(),"1490");await text_in(editor.y_field.get_line_edit(),"880");await click_button("应用对象属性")
	check(editor.session.snapshot().manual_entities.any(func(e):return e.entity_id==detached.entity_id and is_equal_approx(e.ground_xy[0],1490.0) and is_equal_approx(e.ground_xy[1],880.0)),"detached tree moved through normal fields")
	await asset_tab(editor,3);await choose_option(editor.plot_panel.kind,0);await choose_option(editor.plot_panel.primary,0)
	await click_button("放置笔刷（一笔一次撤销）")
	var before_paint: int=editor.session.undo_stack.size()
	await drag_at(editor.canvas.global_position+editor.canvas.pan+Vector2(100,860)*editor.canvas.zoom,editor.canvas.global_position+editor.canvas.pan+Vector2(1400,860)*editor.canvas.zoom)
	await wait_plot_job();await settle()
	check(editor.session.undo_stack.size()==before_paint+1,"one placement stroke adopts one complete history entry")
	var placed_id: String=editor.session.snapshot().recipes[-1].recipe_id
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.get("recipe_id")==placed_id),"placement stroke produces actual editable objects")
	await capture("w3_painted_stroke")
	await click_button("擦除笔刷（保留固定 / 手工）")
	var before_erase: Dictionary=editor.session.snapshot()
	var start:=Vector2(maxf(10,float(fixed.ground_xy[0])-200),fixed.ground_xy[1]);var end:=Vector2(minf(1590,float(fixed.ground_xy[0])+200),fixed.ground_xy[1])
	await drag_at(editor.canvas.global_position+editor.canvas.pan+start*editor.canvas.zoom,editor.canvas.global_position+editor.canvas.pan+end*editor.canvas.zoom)
	await wait_plot_job();await settle()
	check(editor.session.snapshot().materialized_snapshot.entities.size()<before_erase.materialized_snapshot.entities.size(),"eraser removes unlocked automatic objects")
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==fixed.entity_id and e.management=="fixed"),"real eraser stroke preserves fixed tree")
	check(editor.session.snapshot().manual_entities.any(func(e):return e.entity_id==detached.entity_id),"real eraser preserves detached manual tree")
	await click_button("撤销");check(editor.session.Model.input_hash(editor.session.snapshot())==editor.session.Model.input_hash(before_erase),"one UI undo restores full eraser recipe and results")
	await click_button("重做")
	await capture("w3_erased_with_protection")
	await asset_tab(editor,3)
	var selected_index: int=-1
	for i in range(editor.plot_panel.recipes.item_count):
		if editor.plot_panel.recipes.get_item_metadata(i)==original_forest_id:selected_index=i
	await select_list(editor.plot_panel.recipes,selected_index)
	await text_in(editor.plot_panel.seed.get_line_edit(),"123")
	await click_button("预览所选区域参数");await apply_plot()
	check(not editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==deleted.entity_id),"UI regeneration preserves tree deletion")
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==fixed.entity_id and e.ground_xy==fixed.ground_xy),"UI regeneration preserves fixed tree location")
	await capture("w3_regenerated")
	await click_button("画多边形区域")
	var before_bad: String=editor.Model.input_hash(editor.session.snapshot())
	for point in [[100,300],[300,500],[100,500],[300,300]]:await world_click(Vector2(point[0],point[1]))
	await key(KEY_ENTER)
	check(editor.Model.input_hash(editor.session.snapshot())==before_bad and not editor.session.job_in_progress(),"self-intersection rejected in normal canvas without partial edit")
	await capture("w3_self_intersection_rejected");await key(KEY_ESCAPE)
	await project_file_dialog("save",output.path_join("w3_editable.shwork.json"))
	check(not editor.session.is_dirty() and editor.session.current_path.ends_with("w3_editable.shwork.json"),"normal UI saves complete W3 project")
	await project_file_dialog("open",output.path_join("w3_editable.shwork.json"))
	check(not editor.session.read_only and editor.session.snapshot().recipes.any(func(r):return r.kind=="brush"),"normal UI reopens regions, brush and pinned assets")
	await capture("w3_saved")
	print("WORKSHOP_PLOTS_UI ",JSON.stringify({"failures":failures,"viewport":[root.size.x,root.size.y],"evidence_type":"automated_viewport_input_replay"}))
	root.remove_child(wb);wb.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
