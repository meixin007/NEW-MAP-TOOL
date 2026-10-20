extends "test_assets_ui.gd"
var editor
var wall_id: String=""

func select_list(list: ItemList, index: int) -> void:
	await reveal_control(list)
	await click_at(list.get_global_rect().position+Vector2(30,15))
	for attempt in range(100):
		var selected: PackedInt32Array=list.get_selected_items()
		if not selected.is_empty() and selected[0]==index: return
		await key(KEY_DOWN if selected.is_empty() or selected[0]<index else KEY_UP)
	check(false,"list selection did not reach "+str(index))
func choose_option(picker: OptionButton, index: int) -> void:
	await reveal_control(picker)
	await click_at(picker.get_global_rect().get_center())
	var popup:=picker.get_popup()
	for attempt in range(picker.item_count+2):
		if popup.get_focused_item()==index: break
		await key(KEY_DOWN,false,0,popup.get_window_id())
	await key(KEY_ENTER,false,0,popup.get_window_id())
	check(picker.selected==index,"dropdown chooses requested item")
func world_click(point: Vector2) -> void:
	await click_at(editor.canvas.global_position+editor.canvas.pan+point*editor.canvas.zoom)
func new_path(caption: String, coordinates: Array) -> void:
	await asset_tab(editor,2)
	await click_button(caption)
	for point in coordinates: await world_click(Vector2(point[0],point[1]))
	await key(KEY_ENTER)
	await settle()
func project_file_dialog(action: String, path: String) -> void:
	await click_button({"save":"另存为","open":"打开项目","legacy":"导入旧 v4 河流（逻辑只读）"}[action])
	await settle()
	if editor.confirmation.visible:
		await click_at(editor.confirmation.confirm_button.get_global_rect().get_center());await settle()
	var dialog: FileDialog=editor.file_dialog
	check(dialog.visible,"project file dialog opens")
	await capture("w2_file_dialog_"+action)
	var field: LineEdit=dialog.get_line_edit()
	var offset:=Vector2(dialog.position) if dialog.is_embedded() else Vector2.ZERO
	await click_at(field.get_global_rect().get_center()+offset)
	await key(KEY_A,true)
	for ch in path: await key(KEY_NONE,false,ch.unicode_at(0))
	await key(KEY_ENTER)
	await settle()
	if dialog.visible: await click_at(dialog.get_ok_button().get_global_rect().get_center()+offset)
	await settle()
func select_entity(id: String) -> void:
	await asset_tab(editor,0)
	for i in range(editor.object_list.item_count):
		if editor.object_list.get_item_metadata(i)==id: await select_list(editor.object_list,i);return
	check(false,"entity absent from visible object list")
func run() -> void:
	var script=load("res://addons/strategic_map_editor/workbench.gd")
	if script==null or not script.can_instantiate(): check(false,"compile");quit(1);return
	wb=script.new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle();await click_button("Canvas 制作 · workshop_s1")
	if not is_instance_valid(wb.workshop_s1_panel): check(false,"integrated entry");quit(1);return
	editor=wb.workshop_s1_panel
	await asset_tab(editor,1);await click_button("载入 10 件自有灰盒小样")
	await new_path("画城墙",[[200,500],[732,500],[1264,500]])
	check(editor.session.snapshot().recipes.size()==1,"wall drawn with normal UI and Enter")
	if editor.session.snapshot().recipes.is_empty(): quit(1);return
	wall_id=editor.session.snapshot().recipes[0].recipe_id
	await select_list(editor.path_panel.points,1)
	await click_button("在所选控制点插门 / 角楼")
	await select_list(editor.path_panel.points,0)
	await choose_option(editor.path_panel.role_asset,1)
	await click_button("在所选控制点插门 / 角楼")
	await select_list(editor.path_panel.points,2)
	await click_button("在所选控制点插门 / 角楼")
	var project: Dictionary=editor.session.snapshot()
	var wall_entities: Array=project.materialized_snapshot.entities.filter(func(e):return e.get("recipe_id")==wall_id and e.get("role")=="wall")
	check(project.recipes[0].roles.size()==3 and wall_entities.size()==6,"UI gate and tower sockets build six full wall pieces")
	check(project.materialized_snapshot.diagnostics.is_empty(),"exact wall scene needs no unsupported stretching")
	await capture("w2_wall_gate")
	if project.recipes[0].roles.size()!=3: print("ROLE_FAILURE ",editor.status.text);quit(1);return
	await new_path("画道路",[[732,100],[732,500],[732,850]])
	var drag_recipe: Dictionary=editor.canvas.paths_recipe()
	var drag_start: Vector2=editor.canvas.global_position+editor.canvas.pan+Vector2(732,100)*editor.canvas.zoom
	var history_size: int=editor.session.undo_stack.size()
	await drag_at(drag_start,drag_start+Vector2(-12,0)*editor.canvas.zoom)
	check(is_equal_approx(editor.canvas.paths_recipe().control_points[0].ground_xy[0],720) and editor.session.undo_stack.size()==history_size+1,"UI path point drag is one transaction")
	await click_button("撤销");check(is_equal_approx(editor.canvas.paths_recipe().control_points[0].ground_xy[0],732),"UI undo restores path geometry")
	await click_button("重做")
	await text_in(editor.path_panel.width.get_line_edit(),"36")
	await click_button("应用控制点 / 宽度")
	check(is_equal_approx(editor.canvas.paths_recipe().control_points[0].width,36),"normal UI changes endpoint width")
	await capture("w2_path_dragged")
	await new_path("画道路",[[100,780],[732,780],[1400,780]])
	await click_button("应用有限道旁布置")
	check(editor.session.snapshot().materialized_snapshot.entities.any(func(e):return e.get("role")=="roadside"),"normal UI generates finite legal roadside buildings")
	await capture("w2_roads_and_buildings")
	project=editor.session.snapshot()
	var gate: Dictionary=project.materialized_snapshot.entities.filter(func(e):return e.kind=="asset" and project.asset_refs[e.asset_ref].category=="gate")[0]
	await select_entity(gate.entity_id);await click_button("固定生成子对象")
	check(editor.session.snapshot().manual_overrides.fixed.size()==1,"UI fixes gate while road remains connected")
	var fixed_wall: Dictionary=wall_entities[0]
	await select_entity(fixed_wall.entity_id);await click_button("固定生成子对象")
	var deleted: Dictionary=wall_entities[1]
	await select_entity(deleted.entity_id);await click_button("删除选中对象")
	var detached: Dictionary=wall_entities[2]
	await select_entity(detached.entity_id);await click_button("脱离生成器（保留身份）")
	await text_in(editor.y_field.get_line_edit(),"620")
	await click_button("应用对象属性")
	check(editor.session.snapshot().manual_entities.any(func(e):return e.entity_id==detached.entity_id and is_equal_approx(e.ground_xy[1],620)),"UI detached object moves manually")
	await choose_option(editor.socket_picker,1)
	await click_button("按接点吸附（点目标蓝点）")
	var end_tower: Dictionary=editor.session.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("recipe_id")==wall_id and e.get("role")=="role" and is_equal_approx(e.ground_xy[0],1264))[0]
	await select_entity(end_tower.entity_id)
	await world_click(Vector2(1232,500))
	check(editor.session.snapshot().manual_entities.any(func(e):return e.entity_id==detached.entity_id and is_equal_approx(e.ground_xy[0],1160) and is_equal_approx(e.ground_xy[1],500)),"manual socket fallback through normal UI")
	await capture("w2_socket_snap")
	await click_button("撤销")
	await asset_tab(editor,2);await select_list(editor.path_panel.recipes,0)
	await text_in(editor.path_panel.seed.get_line_edit(),"123")
	await click_button("应用路径名称 / 种子 / 样式")
	project=editor.session.snapshot()
	check(not project.materialized_snapshot.entities.any(func(e):return e.entity_id==deleted.entity_id),"UI regeneration keeps deletion")
	check(project.materialized_snapshot.entities.any(func(e):return e.entity_id==gate.entity_id and e.management=="fixed" and e.ground_xy==gate.ground_xy),"UI regeneration keeps fixed gate")
	await capture("w2_protection")
	var before: String=editor.Model.input_hash(project)
	await click_button("加控制点（点路径）");await world_click(Vector2(400,500))
	check(editor.Model.input_hash(editor.session.snapshot())==before and editor.status.text.contains("固定"),"normal UI reports ambiguous protected topology")
	await capture("w2_topology_conflict")
	var legacy_script=load("res://addons/strategic_map_editor/document.gd")
	var legacy=legacy_script.new();legacy.add_feature("river",[[80,100],[500,160],[950,120]],"旧 v4 河流")
	var legacy_path: String=output.path_join("legacy_input.map.json")
	check(legacy.save_file(legacy_path).is_empty(),"isolated legacy import fixture")
	var legacy_hash:=FileAccess.get_sha256(legacy_path)
	await asset_tab(editor,2)
	var previous_recipes: int=editor.session.snapshot().recipes.size()
	await project_file_dialog("legacy",legacy_path)
	check(editor.session.snapshot().recipes.size()==previous_recipes+1 and editor.session.snapshot().legacy_document.features.size()==1,"normal UI imports legacy river projection")
	await click_button("撤销")
	check(editor.session.snapshot().recipes.size()==previous_recipes and editor.session.snapshot().legacy_document.features.is_empty(),"one UI undo restores recipe and legacy bridge together")
	await click_button("重做")
	await select_list(editor.path_panel.recipes,editor.path_panel.recipes.item_count-1)
	await select_list(editor.path_panel.points,1)
	await text_in(editor.path_panel.width.get_line_edit(),"44")
	await click_button("应用控制点 / 宽度")
	check(FileAccess.get_sha256(legacy_path)==legacy_hash and editor.Model.Paths.digest(editor.session.snapshot().legacy_document)==editor.Model.Paths.digest(legacy.snapshot()),"visual river width preserves source file and legacy rules")
	await capture("w2_legacy_river")
	await project_file_dialog("save",output.path_join("w2_editable.shwork.json"))
	check(editor.session.current_path.replace("\\","/").ends_with("w2_editable.shwork.json") and not editor.session.is_dirty(),"normal UI saves complete editable project")
	var other=editor.Session.new()
	var reopened: Dictionary=other.load_file(output.path_join("w2_editable.shwork.json"))
	check(reopened.ok and not other.read_only,"reopen complete UI-authored project: "+str(reopened.get("error","")))
	if not reopened.ok or other.read_only:
		var saved_project: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("w2_editable.shwork.json")))
		var memory_input: Dictionary=editor.session.snapshot();memory_input.erase("materialized_snapshot")
		var saved_input: Dictionary=saved_project.duplicate(true);saved_input.erase("materialized_snapshot")
		editor.Session._atomic_write(output.path_join("debug_input.json"),{"memory":editor.Model.Canonical.stringify(memory_input),"saved":editor.Model.Canonical.stringify(saved_input),"recorded_hash":saved_project.materialized_snapshot.input_hash})
		saved_project.materialized_snapshot={}
		var expected: Dictionary=editor.Model.materialize(saved_project)
		editor.Session._atomic_write(output.path_join("debug_expected.json"),expected)
	await project_file_dialog("open",output.path_join("w2_editable.shwork.json"))
	check(editor.session.snapshot().manual_overrides.tombstones.size()==2 and not editor.session.read_only,"normal UI reopens all protection intent")
	await capture("w2_saved")
	await new_path("画城墙",[[200,250],[450,350]])
	check(editor.session.snapshot().materialized_snapshot.diagnostics.any(func(d):return d.code=="missing_orientation"),"normal UI exposes unsupported direction diagnostic")
	await capture("w2_missing_direction")
	print("WORKSHOP_PATHS_UI ",JSON.stringify({"failures":failures,"viewport":[root.size.x,root.size.y],"evidence_type":"automated_viewport_input_replay"}))
	root.remove_child(wb);wb.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
