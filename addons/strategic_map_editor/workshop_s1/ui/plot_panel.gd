@tool
extends VBoxContainer
const Model=preload("../project_model.gd")
const Brush=preload("../brush_sampler.gd")
const Geometry=preload("../plot_geometry.gd")
var host
var recipes: ItemList
var points: ItemList
var kind: OptionButton
var primary: OptionButton
var secondary: OptionButton
var weight: SpinBox
var extra_box: VBoxContainer
var extra_rows: Array=[]
var density: SpinBox
var seed: SpinBox
var spacing_x: SpinBox
var spacing_y: SpinBox
var scale_min: SpinBox
var scale_max: SpinBox
var cluster: SpinBox
var radius: SpinBox
var point_x: SpinBox
var point_y: SpinBox
var selected_recipe_id: String=""
var dirty:=false
var _refreshing:=false
var _auto_commit:=false
var _pending_id: String=""
var _recovered_command: Dictionary={}
func spin(caption: String, value: float, lo: float, hi: float, step: float=1) -> SpinBox:
	var field:=SpinBox.new();field.prefix=caption+" ";field.min_value=lo;field.max_value=hi;field.step=step;field.value=value;add_child(field)
	field.value_changed.connect(func(_v):mark_dirty())
	field.get_line_edit().text_changed.connect(func(_text):mark_dirty())
	return field
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for item in [["rectangle","画矩形区域（两角）"],["ellipse","画圆 / 椭圆区域"],["hexagon","画六边形区域"],["polygon","画多边形区域"]]:
		host.button(self,item[1],func():begin_shape(item[0]))
	var outlines:=CheckBox.new();outlines.text="显示区域轮廓";outlines.button_pressed=true;outlines.toggled.connect(func(value):host.canvas.show_plot_boundaries=value;host.canvas.queue_redraw());add_child(outlines)
	host.button(self,"完成区域 / 洞（Enter）",func():host.canvas.finish_plot())
	kind=OptionButton.new()
	for label in ["林地 forest","普通散布 scatter","农田 farmland","地表 ground","永久留白 clearance"]:kind.add_item(label)
	add_child(kind)
	kind.item_selected.connect(func(i):
		if _refreshing:return
		mark_dirty()
		if i==2:spacing_x.value=200;spacing_y.value=130;scale_min.value=0.85;scale_max.value=1.0
		elif i==0:spacing_x.value=72;spacing_y.value=56;scale_min.value=0.8;scale_max.value=1.0)
	primary=OptionButton.new();add_child(primary);secondary=OptionButton.new();add_child(secondary)
	for picker in [primary,secondary]:picker.item_selected.connect(func(_i):mark_dirty())
	weight=spin("第二资产权重",0.4,0.01,100,0.05)
	extra_box=VBoxContainer.new();add_child(extra_box)
	host.button(self,"添加混用素材（最多16种）",func():add_weight_row())
	density=spin("密度",0.8,0,1,0.05);seed=spin("种子",42,0,2147483647)
	spacing_x=spin("格距 X",72,16,512);spacing_y=spin("格距 Y",56,16,512)
	scale_min=spin("尺寸最小",0.8,0.1,8,0.05);scale_max=spin("尺寸最大",1.0,0.1,8,0.05)
	cluster=spin("团簇强度",0.35,0,1,0.05);radius=spin("笔刷半径",90,8,512)
	host.button(self,"放置笔刷（一笔一次撤销）",func():begin_brush("place"))
	host.button(self,"擦除笔刷（保留固定 / 手工）",func():begin_brush("erase"))
	var hint:=Label.new();hint.text="固定世界格；笔迹不按事件堆叠。中键平移。\n擦除保留固定/锁定/手工对象，删除意图随项目保存。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	recipes=ItemList.new();recipes.custom_minimum_size.y=150;recipes.item_selected.connect(func(i):select_recipe(str(recipes.get_item_metadata(i))));add_child(recipes)
	host.button(self,"预览所选区域参数",preview_selected)
	host.button(self,"应用区域预览（一次撤销）",apply_preview)
	host.button(self,"取消区域预览 / 计算",cancel_job)
	host.button(self,"恢复未完成的计算意图（预览）",func():
		if _recovered_command.is_empty():host.status.text="没有待恢复的计算意图。";return
		start_job(_recovered_command))
	host.button(self,"提交恢复的笔迹草稿（预览）",func():
		if host.canvas.brush_points.is_empty():host.status.text="没有恢复的笔迹草稿。";return
		var r: Dictionary=host.canvas.brush_template.duplicate(true);r.recipe_id=Model.new_id("brush");r.stroke_points=Brush.normalize(host.canvas.brush_points);host.canvas.brush_points.clear();_pending_id=r.recipe_id;start_job({"op":"apply_brush","recipe":r}))
	host.button(self,"画洞（所选区域内）",func():
		if current().get("kind")!="plot":host.status.text="请先选择一个区域。";return
		host.request_canvas_mode("plot_hole",func():host.canvas.selected_plot_id=selected_recipe_id;host.canvas.plot_shape="polygon"))
	points=ItemList.new();points.custom_minimum_size.y=110;points.item_selected.connect(func(i):
		var r:=current()
		if i<r.get("outer",[]).size():_refreshing=true;point_x.value=r.outer[i][0];point_y.value=r.outer[i][1];_refreshing=false);add_child(points)
	point_x=spin("顶点 X",0,0,100000);point_y=spin("顶点 Y",0,0,100000)
	host.button(self,"移动所选区域顶点",func():
		var r:=current();var selected:=points.get_selected_items()
		if r.get("kind")!="plot" or selected.is_empty():host.status.text="请选择区域外轮廓顶点。";return
		var outer: Array=r.outer.duplicate(true);outer[selected[0]]=[point_x.value,point_y.value]
		start_job({"op":"update_recipe","recipe_id":selected_recipe_id,"patch":{"outer":outer,"shape":"polygon"}}))
	host.button(self,"删除最后一个洞",func():
		var r:=current()
		if r.get("holes",[]).is_empty():return
		var holes: Array=r.holes.duplicate(true);holes.pop_back();start_job({"op":"update_recipe","recipe_id":selected_recipe_id,"patch":{"holes":holes}}))
	host.button(self,"锁定所选区域",func():host.report(host.session.dispatch({"op":"set_recipe_locked","recipe_id":selected_recipe_id,"locked":true})))
	host.button(self,"解锁所选区域",func():host.report(host.session.dispatch({"op":"set_recipe_locked","recipe_id":selected_recipe_id,"locked":false})))
	host.button(self,"删除所选区域（确认）",delete_recipe)
	refresh()
func _fill_extra_picker(picker: OptionButton, refs: Dictionary, chosen: String) -> void:
	picker.clear();picker.add_item("混用资产 · 未选择");picker.set_item_metadata(0,"")
	for ref in refs:
		picker.add_item(refs[ref].label);picker.set_item_metadata(picker.item_count-1,ref)
		if ref==chosen:picker.select(picker.item_count-1)
func add_weight_row(ref: String="", amount: float=1.0) -> Dictionary:
	if extra_rows.size()>=14:
		host.status.text="一个区域最多16种加权素材。";return {}
	var box:=VBoxContainer.new();extra_box.add_child(box)
	var picker:=OptionButton.new();box.add_child(picker);_fill_extra_picker(picker,host.snapshot_for_ui().asset_refs,ref)
	var controls:=HBoxContainer.new();box.add_child(controls)
	var field:=SpinBox.new();field.prefix="混用权重 ";field.min_value=0.01;field.max_value=100;field.step=0.01;field.value=amount;field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;controls.add_child(field)
	var row: Dictionary={"box":box,"picker":picker,"weight":field}
	extra_rows.append(row)
	picker.item_selected.connect(func(_i):mark_dirty());field.value_changed.connect(func(_v):mark_dirty());field.get_line_edit().text_changed.connect(func(_s):mark_dirty())
	host.button(controls,"移除",func():extra_rows.erase(row);extra_box.remove_child(box);box.queue_free();mark_dirty())
	mark_dirty();return row
func clear_extra_weights() -> void:
	for row in extra_rows:extra_box.remove_child(row.box);row.box.queue_free()
	extra_rows.clear();mark_dirty()
func _restore_weights(weights: Array) -> void:
	for i in range(primary.item_count):
		if not weights.is_empty() and primary.get_item_metadata(i)==weights[0].asset_ref:primary.select(i)
	secondary.select(0)
	for i in range(secondary.item_count):
		if weights.size()>1 and secondary.get_item_metadata(i)==weights[1].asset_ref:secondary.select(i);weight.value=weights[1].weight
	clear_extra_weights()
	for i in range(2,weights.size()):add_weight_row(str(weights[i].asset_ref),float(weights[i].weight))
func mark_dirty() -> void:
	if _refreshing:return
	dirty=true
	if host.session.job_in_progress() or host.session.has_preview():
		host.session.cancel_preview_job();host.session.cancel_preview();host.canvas._last_revision=-1;host.canvas.queue_redraw();host.status.text="输入已改变，旧候选已取消；请重新预览。"
func refresh_brush_template() -> void:
	var mode: String=str(host.canvas.brush_template.get("brush_mode","place"))
	host.canvas.brush_template=Brush.recipe("",mode,[],radius.value,str(primary.get_selected_metadata()) if primary.selected>=0 else "",host.canvas.active_surface_id)
	host.canvas.brush_template.merge(parameters(),true)
	if mode=="erase":host.canvas.brush_template.plot_type="scatter"
func current() -> Dictionary:
	for r in host.snapshot_for_ui().recipes:
		if r.recipe_id==selected_recipe_id:return r
	return {}
func refresh() -> void:
	if not is_instance_valid(recipes):return
	_refreshing=true
	var p: Dictionary=host.snapshot_for_ui()
	var selected: Variant=primary.get_selected_metadata() if primary.selected>=0 else ""
	var second: Variant=secondary.get_selected_metadata() if secondary.selected>=0 else ""
	primary.clear();secondary.clear();secondary.add_item("第二资产 · 无");secondary.set_item_metadata(0,"")
	for key in p.asset_refs:
		primary.add_item(p.asset_refs[key].label);primary.set_item_metadata(primary.item_count-1,key)
		secondary.add_item(p.asset_refs[key].label);secondary.set_item_metadata(secondary.item_count-1,key)
		if key==selected:primary.select(primary.item_count-1)
		if key==second:secondary.select(secondary.item_count-1)
	for row in extra_rows:_fill_extra_picker(row.picker,p.asset_refs,str(row.picker.get_selected_metadata()))
	recipes.clear()
	for r in p.recipes:
		if r.kind not in ["plot","brush"]:continue
		recipes.add_item(("[锁定] " if r.locked else "")+r.name+" · "+r.plot_type);recipes.set_item_metadata(recipes.item_count-1,r.recipe_id)
		if r.recipe_id==selected_recipe_id:recipes.select(recipes.item_count-1)
	points.clear()
	for pnt in current().get("outer",[]):points.add_item(str(points.item_count+1)+" · "+str(pnt))
	_refreshing=false
func parameters() -> Dictionary:
	var type: String=["forest","scatter","farmland","ground","clearance"][kind.selected]
	var weights: Array=[]
	if type!="clearance":
		if primary.selected>=0:weights.append({"asset_ref":str(primary.get_selected_metadata()),"weight":1.0})
		if secondary.selected>0 and secondary.get_selected_metadata()!=primary.get_selected_metadata():weights.append({"asset_ref":str(secondary.get_selected_metadata()),"weight":weight.value})
		for row in extra_rows:
			if row.picker.selected>0:weights.append({"asset_ref":str(row.picker.get_selected_metadata()),"weight":row.weight.value})
	return {"plot_type":type,"surface_id":host.canvas.active_surface_id,"seed":int(seed.value),"density":density.value,"spacing":[spacing_x.value,spacing_y.value],"scale_range":[scale_min.value,scale_max.value],"asset_weights":weights,"cluster_strength":cluster.value}
func begin_shape(shape: String) -> void:
	host.request_canvas_mode("plot_draw",func():host.canvas.plot_shape=shape;host.status.text="选择区域类型和资产后，单击两角；多边形逐点单击并 Enter 完成。")
func begin_brush(mode: String) -> void:
	host.request_canvas_mode("plot_brush",func():
		host.canvas.brush_template=Brush.recipe("",mode,[],radius.value,str(primary.get_selected_metadata()) if primary.selected>=0 else "",host.canvas.active_surface_id)
		host.canvas.brush_template.merge(parameters(),true)
		if mode=="erase":host.canvas.brush_template.plot_type="scatter"
		host.status.text="按住左键绘制一笔；松开后一次提交，Esc取消。固定/锁定/手工对象保留。")
func drawn(outer: Array, shape: String, hole: bool) -> void:
	if hole:
		var r:=current();var holes: Array=r.get("holes",[]).duplicate(true);holes.append(outer)
		start_job({"op":"update_recipe","recipe_id":selected_recipe_id,"patch":{"holes":holes}});return
	var id:=Model.new_id("plot");var r: Dictionary=parameters()
	r.merge({"recipe_id":id,"kind":"plot","name":{"forest":"林地","farmland":"农田","scatter":"散布","ground":"地表","clearance":"永久留白"}[r.plot_type],"shape":shape,"outer":outer,"holes":[],"locked":false})
	_pending_id=id;start_job({"op":"add_recipe","recipe":r})
func stroke(recipe: Dictionary) -> void:
	_pending_id=recipe.recipe_id;start_job({"op":"apply_brush","recipe":recipe},true)
func start_job(command: Dictionary, auto_commit: bool=false) -> void:
	var result: Dictionary=host.session.start_preview_job(command)
	if not result.ok:host.report(result)
	else:host._preview_owner="plot";_auto_commit=auto_commit;host.status.text="阶段 1/2：正在验证和构建候选，可取消。"
func poll() -> void:
	var result: Dictionary=host.session.poll_preview_job()
	match result.status:
		"working":
			if not result.cancelled:host.status.text=result.stage+" · "+str(result.elapsed_ms)+"ms · 可取消"
		"ready":
			host.canvas._last_revision=-1;host.canvas.queue_redraw()
			host.status.text=result.stage+" · 候选 "+str(result.candidate_count)
			if _auto_commit:apply_preview()
		"failed":host.status.text=str(result.error)
		"discarded":host.status.text=result.message
func apply_preview() -> void:
	host._defer_refresh=true
	var result: Dictionary=host.session.commit_preview()
	host._defer_refresh=false
	if result.ok:
		dirty=false
		_recovered_command.clear()
		if not _pending_id.is_empty():selected_recipe_id=_pending_id;host.canvas.selected_plot_id=selected_recipe_id
		host.refresh();host.canvas._last_revision=-1
	host.report(result)
func cancel_job() -> void:
	host.canvas.cancel();_auto_commit=false;host.status.text="区域候选已取消，正式项目未修改。"
func preview_selected() -> void:
	if current().is_empty():host.status.text="请先选择一个区域。";return
	start_job({"op":"update_recipe","recipe_id":selected_recipe_id,"patch":parameters()})
func select_recipe(id: String) -> void:
	if host.canvas.has_pending_input():host.status.text="请先应用或取消当前区域预览。";return
	selected_recipe_id=id;_pending_id=id;host.canvas.selected_plot_id=id
	var r:=current()
	if r.is_empty():return
	_refreshing=true
	kind.select(["forest","scatter","farmland","ground","clearance"].find(r.plot_type))
	seed.value=float(r.seed);density.value=float(r.density);spacing_x.value=r.spacing[0];spacing_y.value=r.spacing[1];scale_min.value=r.scale_range[0];scale_max.value=r.scale_range[1];cluster.value=r.cluster_strength
	_restore_weights(r.asset_weights)
	dirty=false;_refreshing=false;refresh();host.canvas.queue_redraw()
func delete_recipe() -> void:
	if current().is_empty():return
	var dialog=host.Dialog.new();dialog.title="删除区域配方";dialog.dialog_text="将删除所选区域的自动内容；固定对象需先脱离。删除可一次撤销。";host.add_child(dialog)
	dialog.confirmed.connect(func():host.report(host.session.dispatch({"op":"remove_recipe","recipe_id":selected_recipe_id,"confirmed":true}));dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()
func capture_draft() -> Dictionary:
	var raw: Dictionary={}
	for key in ["weight","density","seed","spacing_x","spacing_y","scale_min","scale_max","cluster","radius","point_x","point_y"]:raw[key]=get(key).get_line_edit().text
	var extras: Array=[]
	for row in extra_rows:extras.append({"asset_ref":str(row.picker.get_selected_metadata()),"weight":row.weight.value,"raw":row.weight.get_line_edit().text})
	return {"recipe_id":selected_recipe_id,"dirty":dirty,"parameters":parameters(),"extra_rows":extras,"radius":radius.value,"vertex_index":points.get_selected_items()[0] if not points.get_selected_items().is_empty() else -1,"vertex_xy":[point_x.value,point_y.value],"raw_numbers":raw,"pending_id":_pending_id,"job_command":host.session._job_command.duplicate(true) if host.session.job_in_progress() else _recovered_command.duplicate(true)}
func restore_draft(draft: Dictionary) -> void:
	selected_recipe_id=str(draft.get("recipe_id",""));_pending_id=str(draft.get("pending_id",""))
	_recovered_command=draft.get("job_command",{}).duplicate(true)
	var p: Dictionary=draft.get("parameters",{})
	_refreshing=true
	if not p.is_empty():
		kind.select(maxi(0,["forest","scatter","farmland","ground","clearance"].find(p.plot_type)))
		seed.value=p.seed;density.value=p.density;spacing_x.value=p.spacing[0];spacing_y.value=p.spacing[1];scale_min.value=p.scale_range[0];scale_max.value=p.scale_range[1];cluster.value=p.cluster_strength
		_restore_weights(p.asset_weights)
	if draft.has("extra_rows"):
		clear_extra_weights()
		for value in draft.extra_rows:
			var row:=add_weight_row(str(value.asset_ref),float(value.weight))
			if not row.is_empty():row.weight.get_line_edit().text=str(value.get("raw",row.weight.get_line_edit().text))
	radius.value=float(draft.get("radius",90));dirty=bool(draft.get("dirty",false));_refreshing=false;refresh()
	_refreshing=true
	var vertex: Array=draft.get("vertex_xy",[0,0]);point_x.value=vertex[0];point_y.value=vertex[1]
	var index: int=int(draft.get("vertex_index",-1))
	if index>=0 and index<points.item_count:points.select(index)
	for key in draft.get("raw_numbers",{}):
		if key in ["weight","density","seed","spacing_x","spacing_y","scale_min","scale_max","cluster","radius","point_x","point_y"]:get(key).get_line_edit().text=str(draft.raw_numbers[key])
	_refreshing=false
