@tool
extends VBoxContainer
const Model = preload("../project_model.gd")
const Paths = preload("../path_generator.gd")
const Dialog = preload("../../dialog_shell.gd")
var host
var recipes: ItemList
var points: ItemList
var title_field: LineEdit
var seed: SpinBox
var style: OptionButton
var x: SpinBox
var y: SpinBox
var width: SpinBox
var wall_asset: OptionButton
var role_asset: OptionButton
var role_angle: SpinBox
var roadside_asset: OptionButton
var roadside_side: OptionButton
var spacing: SpinBox
var offset: SpinBox
var dirty := false
var point_dirty := false
var _refreshing := false

func _spin(caption: String, value: float, minimum: float, maximum: float) -> SpinBox:
	var f:=SpinBox.new();f.prefix=caption+" ";f.min_value=minimum;f.max_value=maximum;f.value=value;add_child(f);return f
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for pair in [["road","画道路"],["wall","画城墙"],["river","画河流（复用旧 ribbon）"]]:
		host.button(self,pair[1],func(): begin_path(pair[0]))
	host.button(self,"导入旧 v4 河流（逻辑只读）",func(): host.choose_file("legacy_rivers"))
	host.button(self,"完成路径（Enter）",func(): host.canvas.finish_path())
	recipes=ItemList.new();recipes.custom_minimum_size.y=130;add_child(recipes)
	recipes.item_selected.connect(func(i): select_recipe(str(recipes.get_item_metadata(i)),""))
	title_field=LineEdit.new();title_field.placeholder_text="路径名称";add_child(title_field)
	seed=_spin("种子",42,-2147483648,2147483647)
	style=OptionButton.new()
	for text in ["dirt","stone","water"]: style.add_item(text)
	add_child(style)
	host.button(self,"应用路径名称 / 种子 / 样式",apply_recipe)
	wall_asset=OptionButton.new();add_child(wall_asset)
	host.button(self,"采用所选墙段版本",func():
		if wall_asset.selected<0: host.status.text="缺少墙段资产，请先导入。";return
		host.report(host.session.dispatch({"op":"update_recipe","recipe_id":host.canvas.selected_recipe_id,"patch":{"wall_asset_ref":wall_asset.get_selected_metadata()}})))
	points=ItemList.new();points.custom_minimum_size.y=120;add_child(points)
	points.item_selected.connect(func(i): select_recipe(host.canvas.selected_recipe_id,str(points.get_item_metadata(i))))
	x=_spin("控制点 X",0,0,100000)
	y=_spin("控制点 Y",0,0,100000)
	width=_spin("点宽度",24,6,256)
	host.button(self,"应用控制点 / 宽度",apply_point)
	host.button(self,"拖动路径控制点",func(): host.request_canvas_mode("path_edit"))
	host.button(self,"加控制点（点路径）",func(): host.request_canvas_mode("path_insert"))
	host.button(self,"删除内部控制点",func(): host.report(host.session.dispatch({"op":"remove_path_point","recipe_id":host.canvas.selected_recipe_id,"point_id":host.canvas.selected_point_id})))
	role_asset=OptionButton.new();add_child(role_asset)
	role_angle=_spin("角色方向",0,0,359)
	host.button(self,"在所选控制点插门 / 角楼",add_role)
	roadside_asset=OptionButton.new();add_child(roadside_asset)
	roadside_side=OptionButton.new()
	for text in ["右侧 / 上侧","左侧 / 下侧","两侧"]: roadside_side.add_item(text)
	add_child(roadside_side)
	spacing=_spin("道旁间距",200,64,2000)
	offset=_spin("道旁退距",100,16,1000)
	host.button(self,"应用有限道旁布置",apply_roadside)
	host.button(self,"移除道旁布置",func(): host.report(host.session.dispatch({"op":"update_recipe","recipe_id":host.canvas.selected_recipe_id,"patch":{"roadside":{}}})))
	host.button(self,"取消未应用路径属性",func(): dirty=false;point_dirty=false;refresh())
	host.button(self,"删除配方（需要确认）",remove_recipe)
	var hint:=Label.new();hint.text="逐点画线，Enter 一次提交；拖点松开提交，Esc 取消。\n墙段只用已制作方向，不足短墙会报告。选自动子对象可固定／删除／脱离。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	title_field.text_changed.connect(func(_s):
		if not _refreshing: dirty=true)
	seed.value_changed.connect(func(_v):
		if not _refreshing: dirty=true)
	style.item_selected.connect(func(_i):
		if not _refreshing: dirty=true)
	for field in [x,y,width]:
		field.value_changed.connect(func(_v):
			if not _refreshing: point_dirty=true)
	refresh()

func _fill(picker: OptionButton, categories: Array) -> void:
	var old: Variant=picker.get_selected_metadata() if picker.selected>=0 else ""
	picker.clear()
	for key in host.snapshot_for_ui().asset_refs:
		var a: Dictionary=host.snapshot_for_ui().asset_refs[key]
		if a.category not in categories: continue
		picker.add_item(a.label+" @ "+a.asset_version);picker.set_item_metadata(picker.item_count-1,key)
		if key==old: picker.select(picker.item_count-1)
func refresh() -> void:
	if not is_instance_valid(recipes): return
	_refreshing=true
	var project: Dictionary=host.snapshot_for_ui()
	recipes.clear()
	for recipe in project.recipes:
		if recipe.kind!="path":continue
		recipes.add_item(recipe.name+" · "+recipe.path_type);recipes.set_item_metadata(recipes.item_count-1,recipe.recipe_id)
		if recipe.recipe_id==host.canvas.selected_recipe_id: recipes.select(recipes.item_count-1)
	_fill(wall_asset,["wall"]);_fill(role_asset,["gate","tower"]);_fill(roadside_asset,["building"])
	var recipe: Dictionary=host.canvas.paths_recipe()
	points.clear()
	if not recipe.is_empty():
		if not dirty:
			title_field.text=recipe.name;seed.value=float(recipe.seed);style.select(["dirt","stone","water"].find(recipe.style))
		for point in recipe.control_points:
			points.add_item("%d · (%.0f, %.0f) w %.0f"%[points.item_count+1,point.ground_xy[0],point.ground_xy[1],point.width]);points.set_item_metadata(points.item_count-1,point.point_id)
			if point.point_id==host.canvas.selected_point_id:
				points.select(points.item_count-1)
				if not point_dirty: x.value=point.ground_xy[0];y.value=point.ground_xy[1];width.value=point.width
	_refreshing=false
func select_recipe(id: String, point_id: String) -> void:
	if host.canvas.has_pending_input() and not host.canvas._point_dragging:
		host.status.text="请先完成或取消画布输入，再切换路径。";return
	if dirty or point_dirty: host.status.text="请先应用或取消路径属性，再切换路径／控制点。";return
	host.canvas.selected_recipe_id=id
	var recipe: Dictionary=host.canvas.paths_recipe()
	host.canvas.selected_point_id=point_id if not point_id.is_empty() else (str(recipe.control_points[0].point_id) if not recipe.is_empty() else "")
	host.canvas.mode="path_edit";refresh();host.canvas.queue_redraw()
func begin_path(type: String) -> void:
	if dirty or point_dirty or host._property_dirty: host.status.text="请先应用或取消属性输入。";return
	if host.canvas.path_type!=type:
		_refreshing=true;width.value=120 if type=="river" else 24;style.select(2 if type=="river" else 0);_refreshing=false
	host.request_canvas_mode("path_draw",func():
		host.canvas.path_type=type;host.canvas.path_width=width.value;host.canvas.path_style=style.get_item_text(style.selected);host.canvas.path_seed=int(seed.value)
		host.canvas.path_wall_ref=str(wall_asset.get_selected_metadata()) if wall_asset.selected>=0 else ""
		host.status.text="逐点画"+{"road":"道路","wall":"城墙","river":"河流"}[type]+"，Enter 完成；右键 / Esc 取消。")
func apply_recipe() -> void:
	var result: Dictionary=host.queue_candidate({"op":"update_recipe","recipe_id":host.canvas.selected_recipe_id,"patch":{"name":title_field.text,"seed":int(seed.value),"style":style.get_item_text(style.selected)}},"path_recipe",true)
	if result.ok:dirty=false
func apply_point() -> void:
	var result: Dictionary=host.queue_candidate({"op":"update_path_point","recipe_id":host.canvas.selected_recipe_id,"point_id":host.canvas.selected_point_id,"patch":{"ground_xy":[x.value,y.value],"width":width.value}},"path_point",true)
	if result.ok:point_dirty=false
func add_role() -> void:
	if role_asset.selected<0: host.status.text="缺少关门／角楼方向资产。";return
	var recipe: Dictionary=host.canvas.paths_recipe()
	if recipe.is_empty(): host.status.text="请先选择路径与控制点。";return
	var point:=Paths.point_by_id(recipe,host.canvas.selected_point_id)
	if point.is_empty(): host.status.text="请选择控制点。";return
	var role: Dictionary={"role_id":Model.new_id("role"),"point_id":point.point_id,"ground_xy":point.ground_xy.duplicate(),"asset_ref":role_asset.get_selected_metadata(),"orientation":role_angle.value}
	host.queue_candidate({"op":"add_path_role","recipe_id":recipe.recipe_id,"role":role},"path_recipe",true)
func apply_roadside() -> void:
	if roadside_asset.selected<0: host.status.text="缺少院落／仓储资产。";return
	var side: Dictionary={"asset_ref":roadside_asset.get_selected_metadata(),"side":["right","left","both"][roadside_side.selected],"spacing":spacing.value,"offset":offset.value}
	host.queue_candidate({"op":"update_recipe","recipe_id":host.canvas.selected_recipe_id,"patch":{"roadside":side}},"path_recipe",true)
func remove_recipe() -> void:
	var dialog:=Dialog.new();dialog.title="删除路径配方";dialog.dialog_text="将删除此配方管理的生成结果；手工脱离对象保留。有固定对象时拒绝删除。整个操作可一次撤销。";host.add_child(dialog)
	dialog.confirmed.connect(func(): host.report(host.session.dispatch({"op":"remove_recipe","recipe_id":host.canvas.selected_recipe_id,"confirmed":true}));dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()
func capture_draft() -> Dictionary:
	return {"dirty":dirty,"point_dirty":point_dirty,"name":title_field.text,"seed":seed.value,"style":style.selected,"x":x.value,"y":y.value,"width":width.value}
func restore_draft(draft: Dictionary) -> void:
	_refreshing=true
	title_field.text=str(draft.get("name",title_field.text));seed.value=float(draft.get("seed",seed.value));style.select(clampi(int(draft.get("style",0)),0,2))
	x.value=float(draft.get("x",x.value));y.value=float(draft.get("y",y.value));width.value=float(draft.get("width",width.value))
	_refreshing=false;dirty=bool(draft.get("dirty",false));point_dirty=bool(draft.get("point_dirty",false))
