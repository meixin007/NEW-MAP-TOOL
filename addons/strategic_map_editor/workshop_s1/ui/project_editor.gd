@tool
extends Control
const Session = preload("../session_transaction.gd")
const Model = preload("../project_model.gd")
const ProjectCanvas = preload("project_canvas.gd")
const Dialog = preload("../../dialog_shell.gd")
const Importer = preload("../asset_importer.gd")
const Asset = preload("../asset_descriptor.gd")
const AssetEditor = preload("asset_editor.gd")
const Samples = preload("../sample_assets.gd")
const PathPanel = preload("path_panel.gd")
const TerrainPanel=preload("terrain_panel.gd")
const PlotPanel=preload("plot_panel.gd")
const RoomPanel=preload("room_panel.gd")
const DistrictPanel=preload("district_panel.gd")
const LibraryPanel=preload("library_panel.gd")
const ExportPanel=preload("export_panel.gd")
const EntityGeometry = preload("../entity_geometry.gd")
signal leave_requested
var session = Session.new()
var canvas
var object_list: ItemList
var title_field: LineEdit
var name_field: LineEdit
var x_field: SpinBox
var y_field: SpinBox
var status: Label
var path_label: Label
var file_dialog: FileDialog
var confirmation
var asset_list: ItemList
var asset_query: LineEdit
var source_notice: LineEdit
var batch_files: FileDialog
var scale_field: SpinBox
var orientation_field: SpinBox
var surface_picker: OptionButton
var surface_height: SpinBox
var path_panel
var plot_panel
var terrain_panel
var room_panel
var district_panel
var library_panel
var export_panel
var selection_ids: Array=[]
var _refresh_snapshot: Dictionary={}
var _object_rows: Array=[]
var _list_project: Dictionary={}
var _list_cursor: int=-1
var _asset_rows: Dictionary={}
var _asset_query: String="__initial_query__"
var last_refresh_ms:=0.0
var _queued_owner: String=""
var _preview_owner: String="plot"
var auto_surface: CheckBox
var socket_picker: OptionButton
var selected_id := ""
var _action := ""
var _recovery_revision := -1
var _refreshing := false
var _property_dirty := false
var _title_dirty := false
var _recovery_draft: Dictionary = {}
var _defer_refresh:=false
const RECOVERY := "user://workshop_s1/recovery.json"

func button(parent: Node, caption: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _ready() -> void:
	name = "WorkshopS1"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("26322f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var heading := Label.new()
	heading.text = "山河工坊 · workshop_s1 · W6—W7 模板与导出"
	heading.add_theme_font_size_override("font_size",22)
	root.add_child(heading)
	var actions := HFlowContainer.new()
	root.add_child(actions)
	button(actions,"返回旧地图",func(): guard_leave(leave_requested.emit))
	button(actions,"新建工坊项目",func(): guard_leave(func(): session.replace_project(Model.blank());session.current_path="";session._saved_signature="";reset_context();refresh()))
	button(actions,"打开项目",func(): guard_leave(func(): choose_file("open")))
	button(actions,"保存项目",save_current)
	button(actions,"另存为",func(): choose_file("save"))
	button(actions,"撤销",func(): history(false))
	button(actions,"重做",func(): history(true))
	button(actions,"适合窗口",func(): canvas.fit_map())
	button(actions,"保存恢复副本",func(): queue_recovery())
	button(actions,"恢复项目",func(): guard_leave(restore_recovery))
	button(actions,"重新验证恢复的修改",resume_pending_edit)
	button(actions,"应用恢复的画布预览",func(): report(session.commit_preview()))
	button(actions,"取消画布预览",func(): canvas.cancel())
	button(actions,"应用区域预览（一次撤销）",func():
		if _preview_owner=="district":district_panel.apply_preview()
		else:plot_panel.apply_preview())
	button(actions,"取消区域预览 / 计算",func():
		if _preview_owner=="district":district_panel.cancel()
		else:plot_panel.cancel_job())
	button(actions,"重建派生快照（明确确认）",func():
		var dialog:=Dialog.new();dialog.title="重建派生快照";dialog.dialog_text="将按当前生成版本重建派生结果，保留权威配方、固定／删除／脱离意图。旧快照可一次撤销；请检查后保存。";add_child(dialog)
		dialog.confirmed.connect(func(): report(session.rebuild_derived());dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered())
	path_label = Label.new()
	root.add_child(path_label)
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	title_field = LineEdit.new()
	title_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_field)
	button(title_row,"应用名称",func():
		var result: Dictionary = session.dispatch({"op":"rename","title":title_field.text})
		if result.ok: _title_dirty=false;refresh()
		report(result))
	title_field.text_changed.connect(func(_value):
		if not _refreshing: _title_dirty=true)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 410
	body.add_child(tabs)
	var objects_scroll := ScrollContainer.new()
	objects_scroll.name = "对象"
	tabs.add_child(objects_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objects_scroll.add_child(sidebar)
	button(sidebar,"选择 / 拖动",func(): request_canvas_mode("select"))
	button(sidebar,"放置手工对象（灰盒）",func(): request_canvas_mode("marker"))
	button(sidebar,"新增 v4 注记（统一事务）",func(): report(session.dispatch({"op":"legacy_add_feature","kind":"label","points":[[120,120]],"label":"旧文档注记"})))
	object_list = ItemList.new()
	object_list.select_mode=ItemList.SELECT_MULTI
	object_list.custom_minimum_size.y = 200
	object_list.item_selected.connect(func(i): select_entity(str(object_list.get_item_metadata(i))))
	object_list.multi_selected.connect(func(i,chosen):
		if _refreshing:return
		selection_ids=[]
		for index in object_list.get_selected_items():selection_ids.append(str(object_list.get_item_metadata(index)))
		if chosen:select_entity(str(object_list.get_item_metadata(i))))
	sidebar.add_child(object_list)
	name_field = LineEdit.new()
	name_field.placeholder_text = "对象名称"
	sidebar.add_child(name_field)
	x_field = SpinBox.new()
	x_field.max_value = 100000
	x_field.prefix = "X "
	sidebar.add_child(x_field)
	y_field = SpinBox.new()
	y_field.max_value = 100000
	y_field.prefix = "Y "
	sidebar.add_child(y_field)
	scale_field = SpinBox.new();scale_field.min_value=0.1;scale_field.max_value=8;scale_field.step=0.05;scale_field.value=1;scale_field.prefix="比例 ";sidebar.add_child(scale_field)
	orientation_field = SpinBox.new();orientation_field.max_value=359;orientation_field.prefix="方向 ";sidebar.add_child(orientation_field)
	surface_picker = OptionButton.new();sidebar.add_child(surface_picker)
	surface_picker.item_selected.connect(func(_i):
		canvas.active_surface_id=str(surface_picker.get_selected_metadata())
		if not _refreshing and not selected_id.is_empty():_property_dirty=true)
	auto_surface=CheckBox.new();auto_surface.text="点放自动选面（歧义时选择）";auto_surface.button_pressed=true;auto_surface.toggled.connect(func(v):canvas.automatic_surface=v);sidebar.add_child(auto_surface)
	button(sidebar,"应用对象属性",func():
		var result: Dictionary = queue_candidate({"op":"update_entity","entity_id":selected_id,"patch":object_patch()},"object",true)
		if result.ok:_property_dirty=false)
	button(sidebar,"取消未应用属性",func(): _property_dirty=false;_title_dirty=false;refresh())
	button(sidebar,"固定生成子对象",func(): report(session.dispatch({"op":"fix_entity","entity_id":selected_id})))
	button(sidebar,"脱离生成器（保留身份）",func(): report(session.dispatch({"op":"detach_entity","entity_id":selected_id})))
	button(sidebar,"删除选中对象",func(): report(session.dispatch({"op":"delete_entity","entity_id":selected_id})))
	button(sidebar,"锁定所选对象",func():report(session.dispatch({"op":"set_entity_locked","entity_id":selected_id,"locked":true})))
	button(sidebar,"解锁所选对象",func():report(session.dispatch({"op":"set_entity_locked","entity_id":selected_id,"locked":false})))
	socket_picker=OptionButton.new();sidebar.add_child(socket_picker)
	button(sidebar,"按接点吸附（点目标蓝点）",func():
		if socket_picker.selected<0: status.text="来源对象缺少接点。";return
		request_canvas_mode("socket_snap",func(): canvas.snap_source_socket=str(socket_picker.get_selected_metadata());canvas.snap_source_entity_id=selected_id;canvas.snap_target_entity_id="";status.text="点击相容蓝色接点；也可先在对象列表指定目标。容差 16 屏幕像素。"))
	_build_asset_tab(tabs)
	canvas = ProjectCanvas.new()
	canvas.session = session
	canvas.selected.connect(select_entity)
	canvas.reported.connect(func(message): status.text = message)
	body.add_child(canvas)
	var path_scroll:=ScrollContainer.new();path_scroll.name="路径";tabs.add_child(path_scroll)
	path_panel=PathPanel.new();path_panel.host=self;path_scroll.add_child(path_panel)
	canvas.recipe_selected.connect(func(id,point_id): path_panel.select_recipe(id,point_id))
	var plot_scroll:=ScrollContainer.new();plot_scroll.name="区域";tabs.add_child(plot_scroll)
	plot_panel=PlotPanel.new();plot_panel.host=self;plot_scroll.add_child(plot_panel)
	canvas.plot_drawn.connect(plot_panel.drawn);canvas.brush_drawn.connect(plot_panel.stroke)
	canvas.brush_started.connect(plot_panel.refresh_brush_template)
	var terrain_scroll:=ScrollContainer.new();terrain_scroll.name="台地";tabs.add_child(terrain_scroll)
	terrain_panel=TerrainPanel.new();terrain_panel.host=self;terrain_scroll.add_child(terrain_panel)
	canvas.terrain_drawn.connect(terrain_panel.drawn);canvas.terrain_selected.connect(terrain_panel.select_surface);canvas.support_ambiguous.connect(choose_support)
	var room_scroll:=ScrollContainer.new();room_scroll.name="院落";tabs.add_child(room_scroll)
	room_panel=RoomPanel.new();room_panel.host=self;room_scroll.add_child(room_panel)
	canvas.compound_drawn.connect(room_panel.drawn)
	var district_scroll:=ScrollContainer.new();district_scroll.name="街区";tabs.add_child(district_scroll)
	district_panel=DistrictPanel.new();district_panel.host=self;district_scroll.add_child(district_panel)
	canvas.district_drawn.connect(district_panel.drawn)
	canvas.district_lot_selected.connect(func(id,candidate):district_panel.select_recipe(id);district_panel.select_lot(candidate))
	var library_scroll:=ScrollContainer.new();library_scroll.name="模板";tabs.add_child(library_scroll)
	library_panel=LibraryPanel.new();library_panel.host=self;library_scroll.add_child(library_panel);canvas.template_placed.connect(library_panel.placed)
	canvas.label_placed.connect(func(point):report(session.dispatch({"op":"legacy_add_feature","kind":"label","points":[point],"label":library_panel.label_text.text})))
	var export_scroll:=ScrollContainer.new();export_scroll.name="导出";tabs.add_child(export_scroll)
	export_panel=ExportPanel.new();export_panel.host=self;export_scroll.add_child(export_panel)
	status = Label.new()
	status.text = "开发构建；灰盒不代表画风通过。中键平移，滚轮缩放，Esc 取消拖动。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	button(root,"查看全部诊断",show_diagnostics)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.shwork.json ; 山河工坊项目"])
	file_dialog.file_selected.connect(func(path):
		var result: Dictionary
		if _action=="asset_pack":
			result=Importer.new().import_pack(session,path)
		elif _action=="legacy_rivers":
			var json:=JSON.new()
			if json.parse(FileAccess.get_file_as_string(path))!=OK or not json.data is Dictionary: report({"ok":false,"error":"旧 v4 JSON 无法读取。"});return
			result=session.dispatch({"op":"import_legacy_rivers","legacy_document":json.data})
		elif _action=="save":queue_save(path);return
		else: result=session.load_file(path)
		report(result)
		if result.ok and _action in ["open","legacy_rivers"]: reset_context();refresh();canvas.fit_map())
	add_child(file_dialog)
	confirmation = Dialog.new()
	add_child(confirmation)
	name_field.text_changed.connect(func(_value):
		if not _refreshing: _property_dirty=true)
	for field in [x_field,y_field,scale_field,orientation_field]:
		field.value_changed.connect(func(_value):
			if not _refreshing: _property_dirty=true)
	batch_files=FileDialog.new()
	batch_files.access=FileDialog.ACCESS_FILESYSTEM
	batch_files.file_mode=FileDialog.FILE_MODE_OPEN_FILES
	batch_files.filters=PackedStringArray(["*.png ; 透明 PNG"])
	batch_files.files_selected.connect(func(paths): show_batch(Array(paths)))
	add_child(batch_files)
	session.changed.connect(_session_changed)
	session.history_trimmed.connect(func(message): status.text=message)
	refresh()
	_finish_fit.call_deferred()
	set_process(true)

func _process(_delta: float) -> void:
	_pump_object_list()
	var saved: Dictionary=session.poll_io_job()
	if saved.status=="failed":status.text=str(saved.error)
	elif saved.status=="saved":
		if saved.context.kind=="recovery" and saved.context.project_id==session.view().project_id:
			_recovery_revision=saved.context.revision;_recovery_draft=saved.context.draft
		status.text="恢复副本已保存。" if saved.context.kind=="recovery" else "项目已保存。"
		path_label.text=("● 未保存 · " if session.is_dirty() else "已保存 · ")+session.current_path
	if canvas.edit_pending:return # Canvas owns its release transaction polling.
	if _preview_owner in ["terrain","room","direct_edit","recovery"]:
		var result: Dictionary=session.poll_preview_job()
		match result.status:
			"working":status.text="正在验证和准备绘制 · %dms · 可取消"%result.elapsed_ms
			"ready":canvas._last_revision=-1;canvas.queue_redraw();status.text="预览就绪；请明确应用或取消。"
			"committed":status.text="修改已验证并提交；可撤销。";_preview_owner="plot"
			"failed":
				match _queued_owner:
					"object":_property_dirty=true
					"path_point":path_panel.point_dirty=true
					"path_recipe":path_panel.dirty=true
					"terrain":terrain_panel.dirty=true
					"room":room_panel.dirty=true
				status.text=str(result.error);_preview_owner="plot"
			"discarded":status.text=result.message;_preview_owner="plot"
		return
	if _preview_owner=="district" and is_instance_valid(district_panel):district_panel.poll()
	elif is_instance_valid(plot_panel):plot_panel.poll()
func _exit_tree() -> void:
	session.shutdown_jobs()
func _session_changed() -> void:
	if not _defer_refresh:refresh();report({"ok":true})

func queue_candidate(command: Dictionary,owner: String,apply_on_ready: bool=false) -> Dictionary:
	var result: Dictionary=session.start_edit_job(command) if apply_on_ready else session.start_preview_job(command)
	if result.ok:_queued_owner=owner;_preview_owner="direct_edit" if apply_on_ready else owner;status.text="正在验证候选；可按Esc取消。"
	else:report(result)
	return result

func reset_context() -> void:
	selected_id="";selection_ids=[];canvas.cancel();canvas.mode="select";canvas.active_surface_id="ground";canvas.selected_id="";canvas.selected_recipe_id="";canvas.selected_point_id="";canvas.selected_terrain_id="";canvas.selected_plot_id=""
	path_panel.dirty=false;path_panel.point_dirty=false;plot_panel.dirty=false;plot_panel.selected_recipe_id="";terrain_panel.dirty=false;terrain_panel.point_dirty=false;room_panel.dirty=false;room_panel.selected_id="";district_panel.dirty=false;district_panel.selected_recipe_id="";library_panel.dirty=false;library_panel.options_dirty=false;library_panel.label_dirty=false;library_panel.selected_label_id=""
	district_panel._roads_initialized=false;terrain_panel.selected_id="";canvas.path_type="road";canvas.path_width=24;canvas.path_style="dirt"

func _finish_fit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(canvas): canvas.fit_map()

func refresh() -> void:
	if not is_instance_valid(object_list): return
	var began:=Time.get_ticks_usec()
	var p: Dictionary = session.view()
	_refresh_snapshot=p
	_refreshing = true
	path_label.text = ("● 未保存 · " if session.is_dirty() else "已保存 · ") + (session.current_path if not session.current_path.is_empty() else "新项目") + (" · 版本不匹配，只读旧快照" if session.read_only else "")
	if not _title_dirty: title_field.text = p.title
	_list_project=p;_list_cursor=0
	object_list.mouse_filter=Control.MOUSE_FILTER_IGNORE;object_list.focus_mode=Control.FOCUS_NONE
	_pump_object_list()
	refresh_assets()
	var active_surface: String=canvas.active_surface_id
	surface_picker.clear()
	for s in p.surfaces:
		surface_picker.add_item("支持面 · "+s.surface_id)
		surface_picker.set_item_metadata(surface_picker.item_count-1,s.surface_id)
		if s.surface_id==active_surface: surface_picker.select(surface_picker.item_count-1)
	canvas.queue_redraw()
	select_entity(selected_id)
	if is_instance_valid(path_panel): path_panel.refresh()
	if is_instance_valid(plot_panel):plot_panel.refresh()
	if is_instance_valid(terrain_panel):terrain_panel.refresh()
	if is_instance_valid(room_panel):room_panel.refresh()
	if is_instance_valid(district_panel):district_panel.refresh()
	if is_instance_valid(library_panel):library_panel.refresh()
	_refreshing = false
	last_refresh_ms=(Time.get_ticks_usec()-began)/1000.0

func _pump_object_list() -> void:
	if _list_cursor<0 or not is_instance_valid(object_list):return
	var began:=Time.get_ticks_usec();var budget_end:=mini(_list_cursor+400,_list_project.materialized_snapshot.entities.size())
	while object_list.item_count>_list_project.materialized_snapshot.entities.size():
		object_list.remove_item(object_list.item_count-1)
		if Time.get_ticks_usec()-began>4000:return
	while _list_cursor<budget_end:
		var i:=_list_cursor;var e: Dictionary=_list_project.materialized_snapshot.entities[i]
		var label: String=str(e.get("label",e.entity_id))
		if e.kind=="asset" and _list_project.asset_refs.has(e.asset_ref):label=_list_project.asset_refs[e.asset_ref].label+" · "+str(e.get("role","手工"))
		label=("[固定] " if e.get("management")=="fixed" else ("[自动] " if e.get("management")=="generated" else ""))+label
		if e.get("hidden",false):label="[隐藏] "+label
		if e.get("locked",false):label="[锁定] "+label
		if i<object_list.item_count:
			if object_list.get_item_text(i)!=label:object_list.set_item_text(i,label)
			if object_list.get_item_metadata(i)!=e.entity_id:object_list.set_item_metadata(i,e.entity_id)
		else:object_list.add_item(label);object_list.set_item_metadata(i,e.entity_id)
		if e.entity_id in selection_ids:
			if not object_list.is_selected(i):object_list.select(i,false)
		elif object_list.is_selected(i):object_list.deselect(i)
		_list_cursor+=1
		if Time.get_ticks_usec()-began>4000:break
	if _list_cursor>=_list_project.materialized_snapshot.entities.size():
		_object_rows=_list_project.materialized_snapshot.entities;_list_cursor=-1;_list_project={}
		object_list.mouse_filter=Control.MOUSE_FILTER_STOP;object_list.focus_mode=Control.FOCUS_ALL

func select_entity(id: String) -> void:
	if canvas.has_pending_input() and id!=selected_id:
		status.text="请先完成／应用或取消画布输入，再切换选择。"
		return
	if id != selected_id and _property_dirty:
		canvas.selected_id = selected_id
		status.text = "请先应用或取消对象属性输入，再选择其他对象。"
		return
	selected_id = id
	if id not in selection_ids:selection_ids=[id] if not id.is_empty() else []
	if canvas.mode=="socket_snap" and id!=canvas.snap_source_entity_id: canvas.snap_target_entity_id=id
	canvas.selected_id = id
	var was_refreshing := _refreshing
	_refreshing = true
	socket_picker.clear()
	for e in session.view().materialized_snapshot.entities:
		if e.entity_id == id and not _property_dirty:
			name_field.text = str(e.get("label",""))
			x_field.value = e.ground_xy[0]
			y_field.value = e.ground_xy[1]
			scale_field.value = float(e.get("scale",1.0))
			orientation_field.value = float(e.get("orientation",0.0))
			for i in range(surface_picker.item_count):
				if surface_picker.get_item_metadata(i)==e.surface_id: surface_picker.select(i)
			for socket in EntityGeometry.sockets(session.view(),e):
				socket_picker.add_item("接点 · "+socket.socket_id);socket_picker.set_item_metadata(socket_picker.item_count-1,socket.socket_id)
			if e.kind=="compound" and is_instance_valid(room_panel):room_panel.show_entity(id)
			if e.kind=="ribbon" and canvas.mode!="socket_snap":
				if e.get("role")=="district_street":district_panel.select_recipe(e.recipe_id)
				elif is_instance_valid(path_panel):path_panel.select_recipe(e.recipe_id,"")
	_refreshing = was_refreshing
	canvas.queue_redraw()

func report(result: Dictionary) -> void:
	status.text = "操作完成。" if result.ok else str(result.error)
	if result.ok:
		if not session.dependency_issues.is_empty(): status.text="只读缺资源："+"；".join(session.dependency_issues)
		else:
			var materialized: Dictionary=session.view().materialized_snapshot
			var diagnostics: Array=materialized.get("diagnostics",[])
			if not diagnostics.is_empty(): status.text="诊断 %d 项："%diagnostics.size()+"；".join(diagnostics.slice(0,3).map(func(d):return str(d.message)))
			elif materialized.get("stats",{}).get("candidate_count",0)>0: status.text="候选 %d；本次重建 %d 段，复用 %d 段。"%[materialized.stats.candidate_count,materialized.stats.rebuilt_segments,materialized.stats.reused_segments]

func show_diagnostics() -> void:
	var dialog:=Dialog.new();dialog.title="当前项目诊断";dialog.ok_button_text="关闭";add_child(dialog)
	var text:=TextEdit.new();text.editable=false;text.custom_minimum_size=Vector2(720,360);dialog.content.add_child(text)
	for issue in session.view().materialized_snapshot.get("diagnostics",[]):text.text+=str(issue.get("code",""))+" · "+str(issue.get("message",""))+"\n"
	if text.text.is_empty():text.text="当前派生结果没有诊断。"
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(780,460))

func choose_file(action: String) -> void:
	if canvas.has_pending_input(): status.text="请先完成或取消画布输入；恢复副本可以保留。";return
	if action == "save" and has_pending_fields(): status.text="请先应用或取消属性输入；恢复副本可以保留这些输入。";return
	_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action in ["open","legacy_rivers","asset_pack"] else FileDialog.FILE_MODE_SAVE_FILE
	if action=="asset_pack":file_dialog.filters=PackedStringArray(["*.assetpack.json ; W3 参考画风素材包"])
	else:file_dialog.filters=PackedStringArray(["*.map.json ; 旧 v4 河流（逻辑只读）"]) if action=="legacy_rivers" else PackedStringArray(["*.shwork.json ; 山河工坊项目"])
	if action == "save": file_dialog.current_file = "新工坊.shwork.json"
	file_dialog.popup_centered_ratio(0.75)

func save_current() -> void:
	if has_pending_fields() or canvas.has_pending_input(): status.text="请先应用或取消属性／画布输入；恢复副本可以保留。";return
	if session.current_path.is_empty(): choose_file("save")
	else: queue_save(session.current_path)

func queue_save(path: String) -> Dictionary:
	var result: Dictionary=session.start_io_job(path)
	status.text="正在保存项目…" if result.ok else str(result.error)
	return result

func queue_recovery() -> Dictionary:
	if session.io_in_progress():return {"ok":true,"queued":false}
	var result: Dictionary=session.start_io_job(RECOVERY,"recovery",capture_draft())
	status.text="正在保存恢复副本…" if result.ok else str(result.error)
	return result

func history(redo_action: bool) -> void:
	if canvas.has_pending_input(): status.text="请先完成或取消画布输入。";return
	if has_pending_fields(): status.text="请先应用或取消属性输入。";return
	var ok: bool = session.redo() if redo_action else session.undo()
	if not ok: status.text = "没有可恢复的历史。"

func guard_leave(action: Callable) -> void:
	if session.io_in_progress():status.text="请等待保存完成，再离开当前项目。";return
	if is_instance_valid(export_panel) and export_panel.adapter.busy:status.text="请先取消导出并等待收尾，再离开当前项目。";return
	if not has_unsaved_authoring(): action.call(); return
	confirmation.title = "当前工坊项目尚未保存"
	confirmation.dialog_text = "继续会丢弃当前未保存修改与预览；取消后可先保存项目或恢复副本。"
	for c in confirmation.confirmed.get_connections(): confirmation.confirmed.disconnect(c.callable)
	confirmation.confirmed.connect(func(): canvas.cancel();_property_dirty=false;_title_dirty=false;path_panel.dirty=false;path_panel.point_dirty=false;plot_panel.dirty=false;terrain_panel.dirty=false;terrain_panel.point_dirty=false;room_panel.dirty=false;district_panel.dirty=false;library_panel.dirty=false;library_panel.options_dirty=false;library_panel.label_dirty=false;action.call(), CONNECT_ONE_SHOT)
	confirmation.popup_centered()

func has_unsaved_authoring() -> bool:
	return session.is_dirty() or canvas.has_pending_input() or has_pending_fields()

func has_pending_fields() -> bool:
	var metadata=active_asset_editor()
	if is_instance_valid(library_panel) and (library_panel.dirty or library_panel.options_dirty or library_panel.label_dirty):return true
	return _title_dirty or _property_dirty or (is_instance_valid(path_panel) and (path_panel.dirty or path_panel.point_dirty)) or (is_instance_valid(terrain_panel) and terrain_panel.dirty) or (is_instance_valid(plot_panel) and plot_panel.dirty) or (is_instance_valid(room_panel) and room_panel.dirty) or (is_instance_valid(district_panel) and district_panel.dirty) or (metadata!=null and metadata.has_pending_changes())

func active_asset_editor():
	for child in get_children():
		if child is AssetEditor and child.visible: return child
	return null

func request_canvas_mode(mode: String, prepare: Callable=Callable()) -> void:
	var action:=func():
		canvas.cancel();canvas.mode=mode
		if prepare.is_valid(): prepare.call()
	if not canvas.has_pending_input(): action.call();return
	confirmation.title="画布输入尚未提交"
	confirmation.dialog_text="继续将丢弃当前未提交路径或拖动预览；取消会保留，可先完成或保存恢复副本。"
	for connection in confirmation.confirmed.get_connections(): confirmation.confirmed.disconnect(connection.callable)
	confirmation.confirmed.connect(action,CONNECT_ONE_SHOT);confirmation.popup_centered()

func has_unsaved_editor_session() -> bool:
	return session.io_in_progress() or (has_unsaved_authoring() and (_recovery_revision != session.revision or _recovery_draft != capture_draft()))

func save_recovery() -> Dictionary:
	var draft := capture_draft()
	var result: Dictionary = session.save_recovery(RECOVERY,draft)
	if result.ok: _recovery_revision = session.revision;_recovery_draft=draft
	return result

func capture_draft() -> Dictionary:
	var metadata=active_asset_editor()
	var intent: Dictionary=canvas.pending_edit()
	var result: Dictionary={"tool":canvas.mode,"selection":selected_id,"preview":session.preview_view() if session.has_preview() and intent.is_empty() else {},"pan":[canvas.pan.x,canvas.pan.y],"zoom":canvas.zoom,"fields":{"title":title_field.text,"name":name_field.text,"x":x_field.value,"y":y_field.value,"scale":scale_field.value,"orientation":orientation_field.value,"surface_id":surface_picker.get_selected_metadata(),"asset_ref":canvas.active_asset_ref},"title_dirty":_title_dirty,"property_dirty":_property_dirty,"path_draft":{"points":canvas.path_points.duplicate(true),"type":canvas.path_type,"width":canvas.path_width,"style":canvas.path_style,"seed":canvas.path_seed,"wall_asset_ref":canvas.path_wall_ref,"recipe_id":canvas.selected_recipe_id,"point_id":canvas.selected_point_id},"path_fields":path_panel.capture_draft(),"asset_editor":metadata.capture_draft() if metadata!=null else {}}
	result.plot_draft={"points":canvas.plot_points.duplicate(true),"shape":canvas.plot_shape,"recipe_id":canvas.selected_plot_id,"brush_points":canvas.brush_points.duplicate(true),"brush_template":canvas.brush_template.duplicate(true)}
	result.plot_fields=plot_panel.capture_draft()
	result.terrain_draft={"points":canvas.terrain_points.duplicate(true),"parent":canvas.terrain_parent,"from":canvas.terrain_from,"to":canvas.terrain_to,"selected_id":canvas.selected_terrain_id,"automatic_surface":canvas.automatic_surface}
	result.terrain_fields=terrain_panel.capture_draft()
	result.room_fields=room_panel.capture_draft();result.district_fields=district_panel.capture_draft()
	result.library_fields=library_panel.capture_draft();result.export_fields=export_panel.capture_draft();result.selection_ids=selected_entity_ids()
	result.w5_canvas={"compound_points":canvas.compound_points.duplicate(true),"district_points":canvas.district_points.duplicate(true),"compound_target_id":canvas.compound_target_id,"show_lots":canvas.show_district_lots,"preview_owner":_preview_owner}
	result.pending_edit=intent
	return result

func restore_recovery() -> void:
	var result: Dictionary = session.load_recovery(RECOVERY)
	if not result.ok: report(result);return
	var draft: Dictionary = session.recovered_draft
	canvas.cancel()
	canvas.mode = str(draft.get("tool","select"))
	selected_id = str(draft.get("selection",""))
	if draft.get("pan") is Array and draft.pan.size() == 2: canvas.pan=Vector2(draft.pan[0],draft.pan[1])
	canvas.zoom = clampf(float(draft.get("zoom",0.7)),0.08,6.0)
	_property_dirty = false
	_title_dirty = false
	refresh()
	_refreshing = true
	var fields: Dictionary = draft.get("fields",{})
	title_field.text = str(fields.get("title",title_field.text))
	name_field.text = str(fields.get("name",name_field.text))
	x_field.value = float(fields.get("x",x_field.value))
	y_field.value = float(fields.get("y",y_field.value))
	scale_field.value=float(fields.get("scale",1.0))
	orientation_field.value=float(fields.get("orientation",0.0))
	canvas.active_asset_ref=str(fields.get("asset_ref",""))
	canvas.active_surface_id=str(fields.get("surface_id","ground"))
	_refreshing = false
	_title_dirty = bool(draft.get("title_dirty",false))
	_property_dirty = bool(draft.get("property_dirty",false))
	var path_draft: Dictionary=draft.get("path_draft",{})
	canvas.path_points=path_draft.get("points",[]).duplicate(true);canvas.path_type=str(path_draft.get("type","road"));canvas.path_width=float(path_draft.get("width",24));canvas.path_style=str(path_draft.get("style","dirt"));canvas.path_seed=int(path_draft.get("seed",42));canvas.path_wall_ref=str(path_draft.get("wall_asset_ref",""));canvas.selected_recipe_id=str(path_draft.get("recipe_id",""));canvas.selected_point_id=str(path_draft.get("point_id",""))
	path_panel.refresh();path_panel.restore_draft(draft.get("path_fields",{}))
	var plot_draft: Dictionary=draft.get("plot_draft",{})
	canvas.plot_points=plot_draft.get("points",[]).duplicate(true);canvas.plot_shape=str(plot_draft.get("shape","polygon"));canvas.brush_points=plot_draft.get("brush_points",[]).duplicate(true);canvas.brush_template=plot_draft.get("brush_template",{}).duplicate(true);canvas.selected_plot_id=str(plot_draft.get("recipe_id",""))
	plot_panel.restore_draft(draft.get("plot_fields",{}))
	var td: Dictionary=draft.get("terrain_draft",{})
	canvas.terrain_points=td.get("points",[]).duplicate(true);canvas.terrain_parent=str(td.get("parent","ground"));canvas.terrain_from=str(td.get("from","ground"));canvas.terrain_to=str(td.get("to","ground"));canvas.selected_terrain_id=str(td.get("selected_id",""));auto_surface.button_pressed=bool(td.get("automatic_surface",true));terrain_panel.restore_draft(draft.get("terrain_fields",{}))
	var metadata_draft: Dictionary=draft.get("asset_editor",{})
	var w5: Dictionary=draft.get("w5_canvas",{})
	selection_ids=draft.get("selection_ids",[]).duplicate();library_panel.restore_draft(draft.get("library_fields",{}));export_panel.restore_draft(draft.get("export_fields",{}))
	canvas.compound_points=w5.get("compound_points",[]).duplicate(true);canvas.district_points=w5.get("district_points",[]).duplicate(true);canvas.compound_target_id=str(w5.get("compound_target_id",""));canvas.show_district_lots=bool(w5.get("show_lots",true));_preview_owner=str(w5.get("preview_owner","plot"));room_panel.restore_draft(draft.get("room_fields",{}));district_panel.restore_draft(draft.get("district_fields",{}))
	if not metadata_draft.is_empty():
		var metadata:=AssetEditor.new();metadata.session=session;metadata.asset_ref=metadata_draft.asset_ref;metadata.selected_entity_id=str(metadata_draft.get("selected_entity_id",""));add_child(metadata);metadata.restore_draft(metadata_draft);metadata.popup_centered(Vector2i(1050,700))
	# Keep a validated preview separate from authority, ready for explicit apply/cancel.
	if not draft.get("pending_edit",{}).is_empty():
		var pending: Dictionary=session.restore_pending_edit(draft.pending_edit)
		if not pending.ok:status.text="恢复项目完成；修改意图未恢复："+str(pending.error);return
		var command: Dictionary=draft.pending_edit.command
		if command.op in ["update_entity","update_path_point"] and Model.pair(command.get("patch",{}).get("ground_xy")):
			if command.op=="update_entity":
				for entity in session.view().materialized_snapshot.entities:
					if entity.entity_id==command.entity_id:canvas._drag_entity=entity;canvas._transient_command=command.duplicate(true);break
			else:
				canvas.selected_recipe_id=command.recipe_id;canvas.selected_point_id=command.point_id
				if not canvas.paths_recipe().is_empty():canvas._transient_command=command.duplicate(true)
			canvas._transient_layer.queue_redraw()
		status.text="已恢复目标输入；请点击“重新验证恢复的修改”，再明确应用或取消。"
		return
	if draft.get("preview") is Dictionary and not draft.preview.is_empty():
		var restored_preview: Dictionary=session.restore_preview(draft.preview)
		if not restored_preview.ok:status.text="恢复项目完成；预览未采用："+str(restored_preview.error);return
	status.text = "恢复项目及未应用输入完成；请明确应用或取消后另存。"

func resume_pending_edit() -> void:
	var result: Dictionary=session.resume_pending_edit()
	if result.ok:
		canvas._transient_command={};canvas._transient_layer.queue_redraw();_preview_owner="recovery"
		status.text="正在重新验证恢复目标；完成后等待应用。"
	else:report(result)

func object_patch() -> Dictionary:
	var patch := {"label":name_field.text,"ground_xy":[x_field.value,y_field.value],"surface_id":str(surface_picker.get_selected_metadata())}
	for e in session.view().materialized_snapshot.entities:
		if e.entity_id==selected_id and e.kind in ["asset","compound"]: patch.merge({"scale":scale_field.value,"orientation":orientation_field.value})
	return patch

func snapshot_for_ui() -> Dictionary:
	return _refresh_snapshot if _refreshing and not _refresh_snapshot.is_empty() else session.view()

func selected_entity_ids() -> Array:
	var valid: Array=session.view().materialized_snapshot.entities.map(func(e):return e.entity_id)
	return selection_ids.filter(func(id):return id in valid)
func select_group(id: String) -> void:
	if canvas.has_pending_input() or has_pending_fields():status.text="先应用或取消未提交输入。";return
	for group in session.view().prefab_instances:
		if group.instance_id==id:
			selection_ids=group.entity_ids.duplicate();selected_id=str(selection_ids[0]) if not selection_ids.is_empty() else "";refresh();return

func _build_asset_tab(tabs: TabContainer) -> void:
	var scroll:=ScrollContainer.new();scroll.name="资产";tabs.add_child(scroll)
	var shelf:=VBoxContainer.new();shelf.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(shelf)
	asset_query=LineEdit.new();asset_query.placeholder_text="搜索名称 / 标签 / ID";asset_query.text_changed.connect(func(_text): refresh_assets());shelf.add_child(asset_query)
	asset_list=ItemList.new();asset_list.custom_minimum_size.y=270;asset_list.fixed_icon_size=Vector2i(64,64);shelf.add_child(asset_list)
	asset_list.item_activated.connect(func(_i): place_asset())
	button(shelf,"放置所选资产",place_asset)
	button(shelf,"编辑所选资产描述",edit_asset)
	source_notice=LineEdit.new();source_notice.placeholder_text="填写本批素材来源（必填）";shelf.add_child(source_notice)
	button(shelf,"批量导入 PNG",func():
		if source_notice.text.strip_edges().is_empty(): status.text="请先填写素材来源。";return
		batch_files.popup_centered_ratio(0.75))
	button(shelf,"导入 W3 参考画风素材包",func():choose_file("asset_pack"))
	button(shelf,"应用参考纸色（当前项目）",func():report(session.dispatch({"op":"set_paper_color","color":"eadbb5"})))
	var debug_toggle:=CheckButton.new();debug_toggle.text="开发诊断 / 原型";shelf.add_child(debug_toggle)
	var debug:=VBoxContainer.new();debug.visible=false;shelf.add_child(debug);debug_toggle.toggled.connect(func(value):debug.visible=value)
	button(debug,"载入 10 件自有灰盒小样",func():
		var result:=Samples.install(session,"user://workshop_s1/prototype_assets_"+Model.new_id("batch"))
		report(result)
		if result.ok: status.text="已导入 10 件自有灰盒，均非正式画风。请选择资产，在画布逐件放置。")
	button(debug,"新增简单高面（W1 原型）",func(): report(session.dispatch({"op":"add_surface_prototype","surface":{"surface_id":"prototype_top","height":60.0,"outline":[[350,250],[1100,250],[1100,780],[350,780]]}})))
	surface_height=SpinBox.new();surface_height.max_value=250;surface_height.value=60;surface_height.prefix="原型高度 ";debug.add_child(surface_height)
	button(debug,"应用高面原型高度",func(): report(session.dispatch({"op":"update_surface_prototype","surface_id":"prototype_top","patch":{"height":surface_height.value}})))
	var hint:=Label.new();hint.text="对象页选择 ground / prototype_top，放置时显式附着。\n台地、崖壁、坡道请使用台地页正式工具。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;debug.add_child(hint)

func refresh_assets() -> void:
	if not is_instance_valid(asset_list): return
	var p: Dictionary=session.view()
	var query:=asset_query.text.strip_edges().to_lower()
	if _asset_rows==p.asset_refs and _asset_query==query:return
	_asset_rows=p.asset_refs;_asset_query=query
	var chosen: Variant=asset_list.get_item_metadata(asset_list.get_selected_items()[0]) if not asset_list.get_selected_items().is_empty() else ""
	asset_list.clear()
	for key in p.asset_refs:
		var a: Dictionary=p.asset_refs[key]
		if not query.is_empty() and not (a.label+" "+key+" "+" ".join(a.tags)).to_lower().contains(query): continue
		asset_list.add_item(a.label+" · "+a.asset_version,canvas.texture_for(a))
		asset_list.set_item_metadata(asset_list.item_count-1,key)
		if key==chosen: asset_list.select(asset_list.item_count-1)

func place_asset() -> void:
	if asset_list.get_selected_items().is_empty(): status.text="请先在资产库选择一件。";return
	if _property_dirty: status.text="请先应用或取消对象属性。";return
	request_canvas_mode("asset",func():
		canvas.active_asset_ref=str(asset_list.get_item_metadata(asset_list.get_selected_items()[0]));canvas.active_orientation=float(session.view().asset_refs[canvas.active_asset_ref].get("default_orientation",0.0))
		status.text="正在点放："+session.view().asset_refs[canvas.active_asset_ref].label+"；支持面 "+canvas.active_surface_id+"。右键 / Esc 取消。")

func edit_asset() -> void:
	if asset_list.get_selected_items().is_empty(): status.text="请先在资产库选择一件。";return
	var editor:=AssetEditor.new();editor.session=session;editor.asset_ref=str(asset_list.get_item_metadata(asset_list.get_selected_items()[0]));editor.selected_entity_id=selected_id
	add_child(editor);editor.saved.connect(func(_key): refresh_assets());editor.popup_centered(Vector2i(1050,700))

func show_batch(paths: Array) -> void:
	var importer:=Importer.new()
	var batch:=importer.inspect_batch(paths,source_notice.text,"fixed_oblique_pending")
	if not batch.ok: status.text=batch.error;return
	var dialog:=Dialog.new();dialog.title="批量导入 · 逐件确认";dialog.ok_button_text="确认仅导入所选合格项";add_child(dialog)
	var checks: Array=[]
	for item in batch.items:
		var checkbox:=CheckBox.new();checkbox.text=("合格 · " if item.ok else "失败 · ")+item.path.get_file()+(" · "+item.error if not item.ok else "")
		checkbox.disabled=not item.ok;checkbox.button_pressed=item.ok;dialog.content.add_child(checkbox);checks.append(checkbox)
	dialog.confirmed.connect(func():
		var accepted: Array=[]
		for i in range(checks.size()):
			if checks[i].button_pressed and not checks[i].disabled: accepted.append(i)
		report(importer.commit_batch(session,batch,accepted));dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(800,500))

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if file_dialog.visible or confirmation.visible: return
	for child in get_children():
		if child is Dialog and child.visible: return
	if event.ctrl_pressed:
		if event.keycode == KEY_S: save_current();get_viewport().set_input_as_handled()
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if event.keycode == KEY_Z: history(event.shift_pressed);get_viewport().set_input_as_handled()
		if event.keycode == KEY_Y: history(true);get_viewport().set_input_as_handled()

func choose_support(choices: Array,entity: Dictionary) -> void:
	var dialog:=Dialog.new();dialog.title="此处可见多个合法支持面，请明确选择";dialog.ok_button_text="取消放置";add_child(dialog)
	for choice in choices:
		button(dialog.content,choice.surface_id+" · 高度 "+str(choice.height),func():
			if entity.get("brush_choice",false):canvas._brush_next_surface=choice.surface_id;canvas.active_surface_id=choice.surface_id;status.text="笔刷支持面已选为 "+choice.surface_id+"，请重新落笔。"
			else:
				var selected:=entity.duplicate(true);selected.surface_id=choice.surface_id;selected.ground_xy=choice.ground_xy;canvas.place_entity(selected)
			dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(650,350))
