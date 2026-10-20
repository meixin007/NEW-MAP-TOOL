@tool
extends VBoxContainer
const D=preload("../district_generator.gd")
const Model=preload("../project_model.gd")
var host
var recipes: ItemList
var lots: ItemList
var roads: ItemList
var points: ItemList
var layout: OptionButton
var use: OptionButton
var material_picker: OptionButton
var lot_role: OptionButton
var density: SpinBox
var vacancy: SpinBox
var future: SpinBox
var seed: SpinBox
var cell_x: SpinBox
var cell_y: SpinBox
var plot_w: SpinBox
var plot_d: SpinBox
var street_width: SpinBox
var safety: SpinBox
var point_x: SpinBox
var point_y: SpinBox
var selected_recipe_id: String=""
var selected_lot_id: String=""
var dirty:=false
var _refreshing:=false
var _pending_id: String=""
var _job_command: Dictionary={}
var _roads_initialized:=false
func spin(label: String,value: float,lo: float,hi: float,step: float=1) -> SpinBox:
	var f:=SpinBox.new();f.prefix=label+" ";f.min_value=lo;f.max_value=hi;f.step=step;f.value=value;add_child(f)
	f.value_changed.connect(func(_v):mark_dirty());f.get_line_edit().text_changed.connect(func(_v):mark_dirty());return f
func picker(labels: Array) -> OptionButton:
	var f:=OptionButton.new();add_child(f)
	for text in labels:f.add_item(text)
	f.item_selected.connect(func(_i):mark_dirty());return f
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint:=Label.new();hint.text="先画主路，再选择道路并画街区边界。\n地块有稳定身份和入口；放不下会说明原因。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	layout=picker(["正交网格","沿道路两侧"]);use=picker(["住宅","市集","仓储"]);material_picker=picker([])
	roads=ItemList.new();roads.select_mode=ItemList.SELECT_MULTI;roads.custom_minimum_size.y=110;roads.multi_selected.connect(func(_i,_s):mark_dirty());add_child(roads)
	density=spin("建筑密度",0.8,0,1,0.05);vacancy=spin("永久留白比例",0.2,0,1,0.05);future=spin("未来扩建比例",0.1,0,1,0.05);seed=spin("种子",42,0,2147483647)
	cell_x=spin("地块格距／沿路间距",240,80,512);cell_y=spin("网格纵距",220,80,512);plot_w=spin("院落宽",180,120,512);plot_d=spin("院落深",160,120,512);street_width=spin("支路宽",14,8,20);safety=spin("安全退距",8,0,64)
	host.button(self,"画矩形街区（两角）",func():begin("district_rectangle"))
	host.button(self,"画多边形街区",func():begin("district_polygon"))
	host.button(self,"完成街区边界（Enter）",func():host.canvas.finish_w5())
	recipes=ItemList.new();recipes.custom_minimum_size.y=120;add_child(recipes);recipes.item_selected.connect(func(i):select_recipe(str(recipes.get_item_metadata(i))))
	host.button(self,"预览街区参数",preview_selected)
	host.button(self,"应用街区预览（一次撤销）",apply_preview)
	host.button(self,"取消街区输入／计算",cancel)
	host.button(self,"恢复街区计算意图（预览）",func():
		if _job_command.is_empty():host.status.text="没有待恢复的街区计算。";return
		start(_job_command))
	var show:=CheckBox.new();show.text="显示地块角色与边界";show.button_pressed=true;add_child(show);show.toggled.connect(func(v):host.canvas.show_district_lots=v;host.canvas.queue_redraw())
	lots=ItemList.new();lots.custom_minimum_size.y=150;add_child(lots);lots.item_selected.connect(func(i):select_lot(str(lots.get_item_metadata(i))))
	lot_role=picker(["可建设地","未来扩建地","永久留白"])
	host.button(self,"点选地块角色",func():host.request_canvas_mode("district_lot"))
	host.button(self,"预览所选地块角色",func():
		var r:=current()
		if r.is_empty() or selected_lot_id.is_empty():host.status.text="先选择一个合法地块。";return
		var roles: Dictionary=r.lot_roles.duplicate(true);roles[selected_lot_id]=["buildable","future","permanent_clearance"][lot_role.selected];_pending_id=r.recipe_id;start({"op":"update_recipe","recipe_id":r.recipe_id,"patch":{"lot_roles":roles}}))
	points=ItemList.new();points.custom_minimum_size.y=100;add_child(points);points.item_selected.connect(func(i):
		var r:=current()
		if not r.is_empty() and i<r.outer.size():_refreshing=true;point_x.value=r.outer[i][0];point_y.value=r.outer[i][1];_refreshing=false)
	point_x=spin("边界顶点 X",0,0,100000);point_y=spin("边界顶点 Y",0,0,100000)
	host.button(self,"预览街区顶点",func():
		var r:=current();var indices:=points.get_selected_items()
		if r.is_empty() or indices.is_empty():host.status.text="先选街区顶点。";return
		var ring: Array=r.outer.duplicate(true);ring[indices[0]]=[point_x.value,point_y.value];start({"op":"update_recipe","recipe_id":r.recipe_id,"patch":{"outer":ring}}))
	host.button(self,"在街区内画排除洞",func():
		if current().is_empty():host.status.text="先选街区。";return
		begin("district_hole"))
	host.button(self,"锁定所选街区",func():host.report(host.session.dispatch({"op":"set_recipe_locked","recipe_id":selected_recipe_id,"locked":true})))
	host.button(self,"解锁所选街区",func():host.report(host.session.dispatch({"op":"set_recipe_locked","recipe_id":selected_recipe_id,"locked":false})))
	host.button(self,"删除所选街区（确认）",func():
		var dialog=host.Dialog.new();dialog.title="删除街区配方";dialog.dialog_text="将移除自动街区，固定对象须先脱离；手工院落继续保留。可一次撤销。";host.add_child(dialog);dialog.confirmed.connect(func():host.report(host.session.dispatch({"op":"remove_recipe","recipe_id":selected_recipe_id,"confirmed":true}));dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered())
	refresh()
func chosen_roads() -> Array:
	var result: Array=[]
	for i in roads.get_selected_items():result.append(str(roads.get_item_metadata(i)))
	return result
func mark_dirty() -> void:
	if _refreshing:return
	dirty=true
	if host.session.has_preview() or host.session.job_in_progress():host.canvas.cancel();host.status.text="街区输入改变，旧候选已取消。"
func current() -> Dictionary:
	for r in host.snapshot_for_ui().recipes:
		if r.recipe_id==selected_recipe_id and r.kind=="district":return r
	return {}
func refresh() -> void:
	if not is_instance_valid(recipes):return
	_refreshing=true;var p: Dictionary=host.snapshot_for_ui();recipes.clear();var selected_roads:=chosen_roads();roads.clear()
	for r in p.recipes:
		if r.kind=="district":
			recipes.add_item(("[锁] " if r.locked else "")+r.name+" · "+r.layout);recipes.set_item_metadata(recipes.item_count-1,r.recipe_id)
			if r.recipe_id==selected_recipe_id:recipes.select(recipes.item_count-1)
		elif r.kind=="path" and r.path_type=="road" and r.surface_id==host.canvas.active_surface_id:
			roads.add_item("主路 · "+r.name);roads.set_item_metadata(roads.item_count-1,r.recipe_id)
			if r.recipe_id in selected_roads or not _roads_initialized:roads.select(roads.item_count-1,false)
	if roads.item_count>0:_roads_initialized=true
	var selected: String=str(material_picker.get_selected_metadata()) if material_picker.item_count>0 else "";material_picker.clear();material_picker.add_item("屋顶 · 程序底色");material_picker.set_item_metadata(0,"")
	for ref in p.asset_refs:
		if p.asset_refs[ref].tags.has("surface_material"):
			material_picker.add_item(p.asset_refs[ref].label);material_picker.set_item_metadata(material_picker.item_count-1,ref)
			if ref==selected:material_picker.select(material_picker.item_count-1)
	lots.clear();points.clear()
	for lot in p.materialized_snapshot.get("lots",[]):
		if lot.recipe_id!=selected_recipe_id:continue
		lots.add_item(lot.candidate_id+" · "+lot.lot_role+" · "+lot.status);lots.set_item_metadata(lots.item_count-1,lot.candidate_id)
		if lot.candidate_id==selected_lot_id:lots.select(lots.item_count-1)
	var r:=current()
	if not r.is_empty():
		for q in r.outer:points.add_item(str(q))
	_refreshing=false
func select_recipe(id: String) -> void:
	if host.canvas.has_pending_input() or dirty:host.status.text="先应用或取消街区输入。";return
	selected_recipe_id=id;_pending_id=id;var r:=current()
	if r.is_empty():return
	_refreshing=true;layout.select(0 if r.layout=="orthogonal" else 1);use.select(["residential","market","storage"].find(r.function));density.value=r.density;vacancy.value=r.vacancy;future.value=r.future_fraction;seed.value=r.seed;cell_x.value=r.cell_size[0];cell_y.value=r.cell_size[1];plot_w.value=r.courtyard_size[0];plot_d.value=r.courtyard_size[1];street_width.value=r.street_width;safety.value=r.safety_margin
	for i in range(roads.item_count):
		if roads.get_item_metadata(i) in r.main_road_ids:roads.select(i,false)
		else:roads.deselect(i)
	for i in range(material_picker.item_count):
		if material_picker.get_item_metadata(i)==r.roof_material:material_picker.select(i)
	_refreshing=false;dirty=false;refresh();host.canvas.queue_redraw()
func select_lot(candidate: String) -> void:
	selected_lot_id=candidate
	for lot in host.snapshot_for_ui().materialized_snapshot.get("lots",[]):
		if lot.recipe_id==selected_recipe_id and lot.candidate_id==candidate:_refreshing=true;lot_role.select(["buildable","future","permanent_clearance"].find(lot.lot_role));_refreshing=false;break
func parameters() -> Dictionary:
	return {"layout":"orthogonal" if layout.selected==0 else "along_road","function":["residential","market","storage"][use.selected],"density":density.value,"vacancy":vacancy.value,"future_fraction":future.value,"seed":seed.value,"cell_size":[cell_x.value,cell_y.value],"courtyard_size":[plot_w.value,plot_d.value],"street_width":street_width.value,"safety_margin":safety.value,"main_road_ids":chosen_roads(),"roof_material":str(material_picker.get_selected_metadata())}
func begin(tool: String) -> void:
	dirty=false;host.request_canvas_mode(tool)
func drawn(points: Array,tool: String) -> void:
	if tool=="district_hole":
		var r:=current()
		if r.is_empty():return
		var holes: Array=r.holes.duplicate(true);holes.append(points);_pending_id=r.recipe_id;start({"op":"update_recipe","recipe_id":r.recipe_id,"patch":{"holes":holes}})
	else:
		var r:=D.recipe(Model.new_id("district"),"orthogonal",points,host.canvas.active_surface_id,chosen_roads());r.merge(parameters(),true);_pending_id=r.recipe_id;start({"op":"add_recipe","recipe":r})
func preview_selected() -> void:
	if current().is_empty():host.status.text="先选一个街区。";return
	_pending_id=selected_recipe_id;start({"op":"update_recipe","recipe_id":selected_recipe_id,"patch":parameters()})
func start(command: Dictionary) -> void:
	var result: Dictionary=host.session.start_preview_job(command)
	if not result.ok:host.report(result);return
	host._preview_owner="district";_job_command=command.duplicate(true);dirty=false;host.status.text="街区 1/2：验证地块、道路和入口，可取消。"
func poll() -> void:
	var result: Dictionary=host.session.poll_preview_job()
	match result.status:
		"working":
			if not result.cancelled:host.status.text="街区计算 "+str(result.elapsed_ms)+"ms · 可取消"
		"ready":host.canvas._last_revision=-1;host.canvas.queue_redraw();host.status.text="街区 2/2：预览就绪，等待明确应用。"
		"failed":host.status.text=str(result.error)
		"discarded":host.status.text=result.message
func apply_preview() -> void:
	var result: Dictionary=host.session.commit_preview();host.report(result)
	if result.ok:dirty=false;_job_command.clear();selected_recipe_id=_pending_id;refresh();select_recipe(selected_recipe_id);host.canvas._last_revision=-1;host.canvas.queue_redraw()
func cancel() -> void:
	dirty=false;host.canvas.cancel();_job_command.clear();refresh();host.status.text="街区输入与计算已取消。"
func capture_draft() -> Dictionary:
	var values: Dictionary={};var raw: Dictionary={}
	for key in ["density","vacancy","future","seed","cell_x","cell_y","plot_w","plot_d","street_width","safety","point_x","point_y"]:values[key]=get(key).value;raw[key]=get(key).get_line_edit().text
	return {"recipe_id":selected_recipe_id,"pending_id":_pending_id,"lot_id":selected_lot_id,"dirty":dirty,"values":values,"raw_numbers":raw,"parameters":parameters(),"job_command":_job_command.duplicate(true),"lot_role":lot_role.selected,"point_index":points.get_selected_items()[0] if not points.get_selected_items().is_empty() else -1}
func restore_draft(d: Dictionary) -> void:
	selected_recipe_id=str(d.get("recipe_id",""));_pending_id=str(d.get("pending_id",""));selected_lot_id=str(d.get("lot_id",""));_job_command=d.get("job_command",{}).duplicate(true);_refreshing=true
	for key in d.get("values",{}):get(key).value=d.values[key]
	for key in d.get("raw_numbers",{}):get(key).get_line_edit().text=d.raw_numbers[key]
	var params: Dictionary=d.get("parameters",{});layout.select(0 if params.get("layout","orthogonal")=="orthogonal" else 1);use.select(["residential","market","storage"].find(params.get("function","residential")));lot_role.select(int(d.get("lot_role",0)))
	for i in range(material_picker.item_count):
		if material_picker.get_item_metadata(i)==params.get("roof_material",""):material_picker.select(i)
	for i in range(roads.item_count):
		if roads.get_item_metadata(i) in params.get("main_road_ids",[]):roads.select(i,false)
		else:roads.deselect(i)
	_refreshing=false;dirty=bool(d.get("dirty",false));refresh()
