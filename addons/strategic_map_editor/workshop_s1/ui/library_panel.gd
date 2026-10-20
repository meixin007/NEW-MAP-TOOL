@tool
extends VBoxContainer
const Library=preload("../template_library.gd")
const Adapter=preload("../export_adapter.gd")
var host
var kind: OptionButton
var title: LineEdit
var version: LineEdit
var carry: CheckBox
var recipe_list: ItemList
var groups: ItemList
var angle: SpinBox
var factor: SpinBox
var dx: SpinBox
var dy: SpinBox
var grid_kind: OptionButton
var grid_size: SpinBox
var grid_visible: CheckBox
var grid_snap: CheckBox
var edge_snap: CheckBox
var legend: TextEdit
var current_template: Dictionary={}
var dirty:=false
var _refreshing:=false
var dialog: FileDialog
var _file_action: String=""
var _clipboard: Dictionary={}
var selected_group_id: String=""
var options_dirty:=false
var label_list: ItemList
var label_text: LineEdit
var label_x: SpinBox
var label_y: SpinBox
var selected_label_id: String=""
var label_dirty:=false
func spin(caption: String,value: float,lo: float,hi: float,step: float=1) -> SpinBox:
	var field:=SpinBox.new();field.prefix=caption+" ";field.min_value=lo;field.max_value=hi;field.step=step;field.value=value;add_child(field);return field
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint:=Label.new();hint.text="对象列表按 Ctrl／Shift 多选；组合只复制快照。\n配方预设保留参数，并另建生成身份。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	kind=OptionButton.new();add_child(kind)
	for label in ["素材组合（图像／附件）","地图组合（当前摆放）","配方预设（继续调参）"]:kind.add_item(label)
	kind.select(1);title=LineEdit.new();title.text="新组合";add_child(title);version=LineEdit.new();version.text="v1";version.placeholder_text="模板版本";add_child(version)
	carry=CheckBox.new();carry.text="配方复制携带内部固定／删除意图";add_child(carry)
	recipe_list=ItemList.new();recipe_list.select_mode=ItemList.SELECT_MULTI;recipe_list.custom_minimum_size.y=110;add_child(recipe_list)
	host.button(self,"保存所选为模板",func():save_dialog(false))
	host.button(self,"打开模板文件",func():_file_action="open";dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.popup_centered_ratio(0.7))
	host.button(self,"当前模板另存新版本",func():save_dialog(true))
	host.button(self,"放置当前模板（点画布）",func():
		if current_template.is_empty():host.status.text="先打开或保存模板。";return
		host.request_canvas_mode("template_place"))
	host.button(self,"复制所选对象",func():
		var result:=Library.capture(host.snapshot_for_ui(),host.selected_entity_ids(),"map_group",title.text)
		if result.ok:_clipboard=result.template;host.status.text="组合已复制，选择粘贴后点画布。"
		else:host.report(result))
	host.button(self,"粘贴组合（点画布）",func():
		if _clipboard.is_empty():host.status.text="先复制组合。";return
		current_template=_clipboard.duplicate(true);host.request_canvas_mode("template_place"))
	groups=ItemList.new();groups.custom_minimum_size.y=100;add_child(groups)
	groups.item_selected.connect(func(i):selected_group_id=str(groups.get_item_metadata(i));host.select_group(selected_group_id))
	host.button(self,"解组所选（一次撤销）",func():
		var selected:=groups.get_selected_items()
		if selected.is_empty():host.status.text="先选一个组合。";return
		host.report(host.session.dispatch({"op":"ungroup_instance","instance_id":groups.get_item_metadata(selected[0])})))
	angle=spin("组合旋转角度",0,-359,359);factor=spin("组合缩放",1,0.1,8,0.05);dx=spin("平移 X",0,-100000,100000);dy=spin("平移 Y",0,-100000,100000)
	for f in [angle,factor,dx,dy]:f.value_changed.connect(func(_v):
		if not _refreshing:dirty=true;host.canvas.cancel())
	for f in [angle,factor,dx,dy]:f.get_line_edit().text_changed.connect(func(_raw):
		if not _refreshing:dirty=true;host.canvas.cancel())
	host.button(self,"预览整组变换",transform_preview)
	host.button(self,"预览所选配方几何变换",func():transform_preview(true))
	host.button(self,"应用整组预览（一次撤销）",func():
		var result: Dictionary=host.session.commit_preview();host.report(result)
		if result.ok:dirty=false)
	host.button(self,"取消组合输入／预览",func():dirty=false;host.canvas.cancel();refresh())
	host.button(self,"隐藏所选对象",func():visibility(true))
	host.button(self,"显示所选对象",func():visibility(false))
	grid_kind=OptionButton.new();grid_kind.add_item("方格");grid_kind.add_item("六角格");add_child(grid_kind);grid_size=spin("网格尺寸",32,8,512)
	grid_visible=CheckBox.new();grid_visible.text="显示网格";add_child(grid_visible);grid_snap=CheckBox.new();grid_snap.text="启用网格吸附";add_child(grid_snap);edge_snap=CheckBox.new();edge_snap.text="启用普通边线吸附";add_child(edge_snap)
	legend=TextEdit.new();legend.custom_minimum_size.y=100;legend.placeholder_text="图例每行：名称|颜色，如 林地|687d4c";add_child(legend)
	grid_kind.item_selected.connect(func(_i):
		if not _refreshing:options_dirty=true)
	grid_size.value_changed.connect(func(_v):
		if not _refreshing:options_dirty=true)
	for f in [grid_visible,grid_snap,edge_snap]:f.toggled.connect(func(_v):
		if not _refreshing:options_dirty=true)
	legend.text_changed.connect(func():
		if not _refreshing:options_dirty=true)
	host.button(self,"应用网格／吸附／图例",apply_options)
	label_text=LineEdit.new();label_text.text="注记";label_text.placeholder_text="标签文字";add_child(label_text)
	label_x=spin("标签 X",0,0,100000);label_y=spin("标签 Y",0,0,100000)
	label_list=ItemList.new();label_list.custom_minimum_size.y=100;add_child(label_list);label_list.item_selected.connect(func(i):select_label(str(label_list.get_item_metadata(i))))
	label_text.text_changed.connect(func(_s):
		if not _refreshing:label_dirty=true)
	for field in [label_x,label_y]:field.value_changed.connect(func(_v):
		if not _refreshing:label_dirty=true)
	host.button(self,"添加标签（点画布）",func():label_dirty=false;host.request_canvas_mode("label_place"))
	host.button(self,"预览标签修改",func():
		host.session.begin_preview();var result: Dictionary=host.session.preview({"op":"update_label","feature_id":selected_label_id,"label":label_text.text,"ground_xy":[label_x.value,label_y.value]})
		if not result.ok:host.session.cancel_preview();host.report(result)
		else:label_dirty=false;host.canvas._last_revision=-1;host.canvas.queue_redraw())
	host.button(self,"应用标签预览（一次撤销）",func():host.report(host.session.commit_preview()))
	host.button(self,"取消标签输入／预览",func():label_dirty=false;host.canvas.cancel();select_label(selected_label_id))
	host.button(self,"删除所选标签",func():host.report(host.session.dispatch({"op":"delete_label","feature_id":selected_label_id})))
	host.button(self,"取消网格／图例输入",func():options_dirty=false;refresh())
	dialog=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.filters=PackedStringArray(["*.shtemplate.json ; 山河工坊模板"]);host.add_child(dialog);dialog.file_selected.connect(file_chosen)
	refresh()
func selection_recipes() -> Array:
	var ids: Array=[]
	for i in recipe_list.get_selected_items():ids.append(recipe_list.get_item_metadata(i))
	return ids
func save_dialog(new_version: bool) -> void:
	if host.canvas.has_pending_input() or host.has_pending_fields():host.status.text="先应用或取消未提交输入。";return
	if new_version:
		if current_template.is_empty():host.status.text="先打开一个模板。";return
		current_template=current_template.duplicate(true);current_template.version=version.text;current_template.preview_ref=current_template.template_id+"_"+version.text+".png"
	else:
		var captured:=Library.capture(host.snapshot_for_ui(),host.selected_entity_ids(),Library.KINDS[kind.selected],title.text,selection_recipes(),carry.button_pressed)
		if not captured.ok:host.report(captured);return
		current_template=captured.template;current_template.version=version.text;current_template.preview_ref=current_template.template_id+"_"+version.text+".png"
	_file_action="save";dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.current_file=title.text+"_"+version.text+".shtemplate.json";dialog.popup_centered_ratio(0.7)
func file_chosen(path: String) -> void:
	if _file_action=="open":
		var result: Dictionary=host.session.read_template(path);host.report(result)
		if result.ok:current_template=result.template;title.text=current_template.label;version.text=current_template.version
	else:
		var adapter:=Adapter.new();add_child(adapter);var image: Image=await adapter.template_thumbnail(host.session,current_template);adapter.queue_free()
		if image==null:host.status.text="模板不能重建为合法预览；文件未写入。";return
		host.report(host.session.save_template(path,current_template,image.save_png_to_buffer()))
func placed(point: Array) -> void:
	var result: Dictionary=host.session.dispatch({"op":"instantiate_template","template":current_template,"ground_xy":point});host.report(result)
func transform_preview(recipes_only: bool=false) -> void:
	var ids: Array=host.selected_entity_ids()
	var pivot: Array=[]
	var command: Dictionary={"op":"transform_recipes","recipe_ids":selection_recipes()} if recipes_only else {"op":"transform_entities","entity_ids":ids}
	if not recipes_only:
		for group in host.snapshot_for_ui().prefab_instances:
			if group.instance_id==selected_group_id and group.entity_ids.size()==ids.size() and group.entity_ids.all(func(id):return id in ids):command={"op":"transform_instance","instance_id":selected_group_id};break
	for e in host.snapshot_for_ui().materialized_snapshot.entities:
		if not ids.is_empty() and e.entity_id==ids[0]:pivot=e.ground_xy;break
	if pivot.is_empty():
		var recipe_ids: Array=selection_recipes()
		if command.op=="transform_instance":
			for group in host.snapshot_for_ui().prefab_instances:
				if group.instance_id==selected_group_id:recipe_ids=group.recipe_ids
		for r in host.snapshot_for_ui().recipes:
			if r.recipe_id in recipe_ids:pivot=r.control_points[0].ground_xy if r.kind=="path" else r.stroke_points[0] if r.kind=="brush" else r.outer[0];break
	if pivot.is_empty():host.status.text="先选择对象、组合或配方。";return
	command.merge({"pivot":pivot,"angle":angle.value,"factor":factor.value,"offset":[dx.value,dy.value]})
	host.session.begin_preview();var result: Dictionary=host.session.preview(command)
	if not result.ok:host.session.cancel_preview();host.report(result)
	else:dirty=false;host.status.text="整组预览完成；缺方向变体或任何冲突会整组拒绝。"
	host.canvas._last_revision=-1;host.canvas.queue_redraw()
func visibility(hidden: bool) -> void:
	var ids: Array=host.selected_entity_ids()
	# One combined transaction preserves history and does not silently unlock objects.
	host.report(host.session.dispatch({"op":"set_entities_hidden","entity_ids":ids,"hidden":hidden}))
func apply_options() -> void:
	var rows: Array=[]
	for line in legend.text.split("\n"):
		if line.strip_edges().is_empty():continue
		var split:=line.split("|")
		if split.size()!=2:host.status.text="图例每行使用 名称|颜色。";return
		rows.append({"label":split[0].strip_edges(),"color":split[1].strip_edges()})
	var result: Dictionary=host.session.dispatch({"op":"set_editor_options","patch":{"grid_kind":"square" if grid_kind.selected==0 else "hex","grid_size":grid_size.value,"grid_visible":grid_visible.button_pressed,"grid_snap":grid_snap.button_pressed,"edge_snap":edge_snap.button_pressed,"legend":rows}})
	host.report(result)
	if result.ok:options_dirty=false;refresh()
func refresh() -> void:
	if not is_instance_valid(groups):return
	_refreshing=true;var p: Dictionary=host.snapshot_for_ui();var chosen:=selection_recipes();recipe_list.clear();groups.clear()
	for r in p.recipes:
		recipe_list.add_item(r.name);recipe_list.set_item_metadata(recipe_list.item_count-1,r.recipe_id)
		if r.recipe_id in chosen:recipe_list.select(recipe_list.item_count-1,false)
	for g in p.prefab_instances:
		groups.add_item(g.label+" · "+g.template_version);groups.set_item_metadata(groups.item_count-1,g.instance_id)
		if g.instance_id==selected_group_id:groups.select(groups.item_count-1)
	if not options_dirty:
		grid_kind.select(1 if p.style_profile.get("grid_kind")=="hex" else 0);grid_size.value=p.style_profile.get("grid_size",32);grid_visible.button_pressed=p.style_profile.get("grid_visible",false);grid_snap.button_pressed=p.style_profile.get("grid_snap",false);edge_snap.button_pressed=p.style_profile.get("edge_snap",false)
		legend.text="\n".join(p.style_profile.get("legend",[]).map(func(row):return row.label+"|"+row.color))
	_refreshing=false
	label_list.clear()
	for feature in p.legacy_document.features:
		if feature.kind=="label":
			label_list.add_item(feature.name);label_list.set_item_metadata(label_list.item_count-1,feature.id)
			if feature.id==selected_label_id:label_list.select(label_list.item_count-1)
	if not label_dirty:select_label(selected_label_id)

func select_label(id: String) -> void:
	if label_dirty:host.status.text="先应用或取消当前标签输入。";return
	selected_label_id=id
	for feature in host.snapshot_for_ui().legacy_document.features:
		if feature.id==id:
			_refreshing=true;label_text.text=feature.name;label_x.value=feature.points[0][0];label_y.value=feature.points[0][1];_refreshing=false;return

func capture_draft() -> Dictionary:
	return {"title":title.text,"version":version.text,"kind":kind.selected,"carry":carry.button_pressed,"selected_group_id":selected_group_id,"dirty":dirty,"options_dirty":options_dirty,"template":current_template.duplicate(true),"clipboard":_clipboard.duplicate(true),"values":[angle.value,factor.value,dx.value,dy.value,grid_size.value],"raw_numbers":[angle.get_line_edit().text,factor.get_line_edit().text,dx.get_line_edit().text,dy.get_line_edit().text,grid_size.get_line_edit().text],"grid_kind":grid_kind.selected,"grid_visible":grid_visible.button_pressed,"grid_snap":grid_snap.button_pressed,"edge_snap":edge_snap.button_pressed,"legend":legend.text,"label_text":label_text.text,"label_id":selected_label_id,"label_dirty":label_dirty,"label_values":[label_x.value,label_y.value],"label_raw":[label_x.get_line_edit().text,label_y.get_line_edit().text]}
func restore_draft(d: Dictionary) -> void:
	if d.is_empty():return
	_refreshing=true;title.text=d.title;version.text=d.version;kind.select(int(d.kind));carry.button_pressed=d.carry;selected_group_id=d.selected_group_id;current_template=d.template.duplicate(true);_clipboard=d.clipboard.duplicate(true)
	var fields: Array=[angle,factor,dx,dy,grid_size]
	for i in range(5):fields[i].value=d.values[i];fields[i].get_line_edit().text=d.raw_numbers[i]
	grid_kind.select(int(d.grid_kind));grid_visible.button_pressed=d.grid_visible;grid_snap.button_pressed=d.grid_snap;edge_snap.button_pressed=d.edge_snap;legend.text=d.legend;dirty=d.dirty;options_dirty=d.options_dirty;label_text.text=d.get("label_text","注记");selected_label_id=d.get("label_id","");label_dirty=d.get("label_dirty",false)
	for i in range(2):
		var field: SpinBox=[label_x,label_y][i];field.value=d.get("label_values",[0,0])[i];field.get_line_edit().text=d.get("label_raw",["0","0"])[i]
	_refreshing=false
