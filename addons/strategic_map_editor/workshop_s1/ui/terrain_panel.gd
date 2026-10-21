@tool
extends VBoxContainer
const T=preload("../terrain_geometry.gd")
const Model=preload("../project_model.gd")
var host
var surfaces: ItemList
var vertices: ItemList
var parent: OptionButton
var from_surface: OptionButton
var to_surface: OptionButton
var height: SpinBox
var spread: SpinBox
var vertex_x: SpinBox
var vertex_y: SpinBox
var ramp_width: SpinBox
var start_x: SpinBox
var start_y: SpinBox
var end_x: SpinBox
var end_y: SpinBox
var gradient: SpinBox
var direction: SpinBox
var point_dirty:=false
var _vertex_index: int=-1
var edge: OptionButton
var top_color: LineEdit
var edge_color: LineEdit
var ramp_style: OptionButton
var selected_id: String=""
var dirty:=false
var _refreshing:=false
var _pending_id: String=""
func spin(caption: String,v: float,lo: float,hi: float) -> SpinBox:
	var f:=SpinBox.new();f.prefix=caption+" ";f.min_value=lo;f.max_value=hi;f.value=v;add_child(f)
	f.value_changed.connect(func(_v):mark_dirty());f.get_line_edit().text_changed.connect(func(_v):mark_dirty());return f
func picker(caption: String) -> OptionButton:
	var label:=Label.new();label.text=caption;add_child(label)
	var f:=OptionButton.new();add_child(f);f.item_selected.connect(func(_v):mark_dirty());return f
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint:=Label.new();hint.text="固定斜俯视；顶面／边坡均可编辑。\n先选父面再画轮廓；最多三层。\n坡道两端分别点击所选上下平面。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	parent=picker("新台地／嵌套父面")
	height=spin("相对高度",60,4,512)
	host.button(self,"画台地矩形（两角）",func():begin("terrain_rectangle"))
	host.button(self,"画台地多边形",func():begin("terrain_polygon"))
	host.button(self,"完成台地轮廓（Enter）",func():host.canvas.finish_terrain())
	from_surface=picker("坡道起面");to_surface=picker("坡道终面")
	ramp_width=spin("坡道宽度",64,12,256)
	ramp_style=picker("坡道地表");ramp_style.add_item("土路");ramp_style.add_item("石路")
	host.button(self,"画坡道（分别点击两端）",func():begin("terrain_ramp"))
	surfaces=ItemList.new();surfaces.custom_minimum_size.y=145;add_child(surfaces);surfaces.item_selected.connect(func(i):select_surface(str(surfaces.get_item_metadata(i))))
	host.button(self,"使用 ground 放置",func():host.canvas.active_surface_id="ground";host.refresh();host.status.text="放置面已设为 ground。")
	host.button(self,"使用所选支持面放置",func():
		if current().is_empty():return
		host.canvas.active_surface_id=selected_id;host.refresh();host.status.text="放置面已设为 "+selected_id)
	vertices=ItemList.new();vertices.custom_minimum_size.y=125;add_child(vertices);vertices.item_selected.connect(load_vertex)
	vertex_x=spin("所选顶点 X",0,0,100000);vertex_y=spin("所选顶点 Y",0,0,100000)
	edge=picker("所选顶点 → 下一点的边类型")
	for label in ["无边带 none","缓坡 slope","岸坎 bank","崖壁 cliff"]:edge.add_item(label)
	edge.select(3);spread=spin("所选边展开宽度",0,0,256);direction=spin("所选边纹理方向",0,-60,60);gradient=spin("坡脚渐变强度",1,0,1);gradient.step=0.05
	for field in [vertex_x,vertex_y,spread,direction,gradient]:
		field.value_changed.connect(func(_v):
			if not _refreshing:point_dirty=true)
	edge.item_selected.connect(func(_v):
		if not _refreshing:point_dirty=true)
	top_color=LineEdit.new();top_color.placeholder_text="顶面色 #c5bf89";top_color.text="c5bf89";add_child(top_color);top_color.text_changed.connect(func(_v):mark_dirty())
	edge_color=LineEdit.new();edge_color.placeholder_text="边带色 #b69d70";edge_color.text="b69d70";add_child(edge_color);edge_color.text_changed.connect(func(_v):mark_dirty())
	start_x=spin("坡道起点 X",0,0,100000);start_y=spin("坡道起点 Y",0,0,100000);end_x=spin("坡道终点 X",0,0,100000);end_y=spin("坡道终点 Y",0,0,100000)
	host.button(self,"预览地形属性／顶点／所选边",preview_selected)
	host.button(self,"在所选边插入中点（预览）",func():edit_vertex("insert"))
	host.button(self,"删除所选顶点（预览）",func():edit_vertex("delete"))
	host.button(self,"应用地形预览（一次撤销）",apply_preview)
	host.button(self,"取消地形输入／预览",cancel)
	host.button(self,"锁定所选地形",func():host.report(host.session.dispatch({"op":"lock_terrain","surface_id":selected_id,"locked":true})))
	host.button(self,"解锁所选地形",func():host.report(host.session.dispatch({"op":"lock_terrain","surface_id":selected_id,"locked":false})))
	host.button(self,"删除所选地形（保留依赖）",func():host.report(host.session.dispatch({"op":"delete_terrain","surface_id":selected_id})))
	refresh()
func mark_dirty() -> void:
	if _refreshing:return
	dirty=true
	if host.session.job_in_progress():host.session.cancel_preview_job()
	if host.session.has_preview():host.session.cancel_preview();host.canvas._last_revision=-1;host.canvas.queue_redraw();host.status.text="地形输入已改变，旧预览取消；请重新预览。"
func current() -> Dictionary:
	return T.surface(host.snapshot_for_ui(),selected_id)
func refresh() -> void:
	if not is_instance_valid(surfaces):return
	_refreshing=true
	var p: Dictionary=host.snapshot_for_ui();surfaces.clear()
	for s in p.surfaces:
		if not s.has("kind"):continue
		surfaces.add_item(("[锁] " if s.locked else "")+s.surface_id+" · "+s.kind);surfaces.set_item_metadata(surfaces.item_count-1,s.surface_id)
		if s.surface_id==selected_id:surfaces.select(surfaces.item_count-1)
	for f in [parent,from_surface,to_surface]:
		var chosen: String=str(f.get_selected_metadata()) if f.item_count>0 else "ground"
		f.clear()
		for s in p.surfaces:
			if s.get("kind")=="ramp":continue
			f.add_item(s.surface_id);f.set_item_metadata(f.item_count-1,s.surface_id)
			if s.surface_id==chosen:f.select(f.item_count-1)
	_refreshing=false
	if not dirty:load_fields()
func choose(f: OptionButton,id: String) -> void:
	for i in range(f.item_count):
		if f.get_item_metadata(i)==id:f.select(i)
func select_surface(id: String) -> void:
	if host.canvas.has_pending_input() or dirty:host.status.text="请先应用或取消当前地形输入。";return
	selected_id=id;host.canvas.selected_terrain_id=id;load_fields();host.canvas.queue_redraw()
func load_fields() -> void:
	var s:=current();vertices.clear()
	if s.is_empty():return
	_refreshing=true
	if s.get("kind")=="terrace":
		height.value=s.height;choose(parent,s.parent_surface_id);top_color.text=s.top_color;edge_color.text=s.edge_color
		for i in range(s.outline.size()):vertices.add_item(str(i)+" · "+str(s.outline[i])+" → "+s.edge_styles[i])
		if vertices.item_count>0:vertices.select(0);load_vertex(0)
	elif s.get("kind")=="ramp":
		choose(from_surface,s.from_surface_id);choose(to_surface,s.to_surface_id);start_x.value=s.start[0];start_y.value=s.start[1];end_x.value=s.end[0];end_y.value=s.end[1];ramp_width.value=s.width;ramp_style.select(0 if s.style=="dirt" else 1)
	_refreshing=false
func load_vertex(i: int) -> void:
	var s:=current()
	if s.get("kind")!="terrace" or i>=s.outline.size():return
	if not _refreshing and point_dirty and i!=_vertex_index:
		if _vertex_index>=0:vertices.select(_vertex_index)
		host.status.text="请先预览／应用或取消所选顶点与边输入。";return
	_vertex_index=i
	var previous:=_refreshing;_refreshing=true;gradient.value=float(s.get("edge_gradients",s.outline.map(func(_v):return 1))[i]);direction.value=float(s.get("edge_directions",s.outline.map(func(_v):return 0))[i]);vertex_x.value=s.outline[i][0];vertex_y.value=s.outline[i][1];edge.select(["none","slope","bank","cliff"].find(s.edge_styles[i]));spread.value=s.edge_widths[i];_refreshing=previous
func begin(mode: String) -> void:
	if host.session.has_preview():host.status.text="先应用或取消现有预览。";return
	# New shape uses current fields; entering draw mode makes their pending use explicit.
	dirty=false
	host.request_canvas_mode(mode,func():
		host.canvas.terrain_parent=str(parent.get_selected_metadata());host.canvas.terrain_from=str(from_surface.get_selected_metadata());host.canvas.terrain_to=str(to_surface.get_selected_metadata());host.status.text="台地点取中；Enter 完成，右键／Esc 取消。")
func drawn(points: Array,mode: String) -> void:
	var id:=Model.new_id("ramp" if mode=="terrain_ramp" else "terrace");var s: Dictionary
	if mode=="terrain_ramp":s={"surface_id":id,"kind":"ramp","height":0,"from_surface_id":str(from_surface.get_selected_metadata()),"to_surface_id":str(to_surface.get_selected_metadata()),"start":points[0],"end":points[1],"width":ramp_width.value,"style":"dirt" if ramp_style.selected==0 else "stone","locked":false}
	else:s={"surface_id":id,"kind":"terrace","parent_surface_id":str(parent.get_selected_metadata()),"height":height.value,"outline":points,"edge_styles":points.map(func(_v):return ["none","slope","bank","cliff"][edge.selected]),"edge_widths":points.map(func(_v):return spread.value),"top_color":top_color.text,"edge_color":edge_color.text,"locked":false}
	_pending_id=id;preview({"op":"add_terrain","surface":s})
func preview(c: Dictionary) -> void:
	if host.session.job_in_progress():host.status.text="请先取消区域计算。";return
	if host.session.has_preview():host.status.text="请先应用或取消现有预览。";return
	var result: Dictionary=host.queue_candidate(c,"terrain")
	if result.ok:dirty=false;point_dirty=false
	host.canvas._last_revision=-1;host.canvas.queue_redraw()
func preview_selected() -> void:
	var s:=current()
	if s.is_empty():host.status.text="先选择一处 W4 地形。";return
	var patch: Dictionary={}
	if s.kind=="terrace":
		patch={"height":height.value,"parent_surface_id":str(parent.get_selected_metadata()),"outline":s.outline.duplicate(true),"edge_styles":s.edge_styles.duplicate(true),"edge_widths":s.edge_widths.duplicate(true),"edge_gradients":s.get("edge_gradients",s.outline.map(func(_v):return 1)).duplicate(true),"edge_directions":s.get("edge_directions",s.outline.map(func(_v):return 0)).duplicate(true),"top_color":top_color.text,"edge_color":edge_color.text}
		var selected:=vertices.get_selected_items()
		if not selected.is_empty():var i: int=selected[0];patch.outline[i]=[vertex_x.value,vertex_y.value];patch.edge_styles[i]=["none","slope","bank","cliff"][edge.selected];patch.edge_widths[i]=spread.value;patch.edge_directions[i]=direction.value;patch.edge_gradients[i]=gradient.value
	else:patch={"from_surface_id":str(from_surface.get_selected_metadata()),"to_surface_id":str(to_surface.get_selected_metadata()),"start":[start_x.value,start_y.value],"end":[end_x.value,end_y.value],"width":ramp_width.value,"style":"dirt" if ramp_style.selected==0 else "stone"}
	_pending_id=selected_id;preview({"op":"update_terrain","surface_id":selected_id,"patch":patch})
func edit_vertex(op: String) -> void:
	var s:=current();var selected:=vertices.get_selected_items()
	if s.get("kind")!="terrace" or selected.is_empty():host.status.text="请选择台地顶点。";return
	var i: int=selected[0];var ring: Array=s.outline.duplicate(true);var styles: Array=s.edge_styles.duplicate();var widths: Array=s.edge_widths.duplicate();var gradients: Array=s.get("edge_gradients",s.outline.map(func(_v):return 1)).duplicate();var directions: Array=s.get("edge_directions",s.outline.map(func(_v):return 0)).duplicate()
	if op=="insert":var mid: Vector2=T.vec(ring[i]).lerp(T.vec(ring[(i+1)%ring.size()]),0.5);ring.insert(i+1,[mid.x,mid.y]);styles.insert(i+1,styles[i]);widths.insert(i+1,widths[i]);directions.insert(i+1,directions[i]);gradients.insert(i+1,gradients[i])
	else:ring.remove_at(i);styles.remove_at(i);widths.remove_at(i);directions.remove_at(i);gradients.remove_at(i)
	_pending_id=selected_id;preview({"op":"update_terrain","surface_id":selected_id,"patch":{"outline":ring,"edge_styles":styles,"edge_widths":widths,"edge_directions":directions,"edge_gradients":gradients}})
func apply_preview() -> void:
	if not host.session.has_preview():host.status.text="没有地形预览。";return
	dirty=false;point_dirty=false;var result: Dictionary=host.session.commit_preview();host.report(result)
	if result.ok:selected_id=_pending_id;host.canvas.selected_terrain_id=selected_id;refresh()
func cancel() -> void:
	dirty=false;point_dirty=false;host.canvas.cancel();refresh();host.status.text="地形输入与预览已取消。"
func capture_draft() -> Dictionary:
	var values: Dictionary={};var raw: Dictionary={}
	for key in ["height","spread","direction","gradient","vertex_x","vertex_y","ramp_width","start_x","start_y","end_x","end_y"]:values[key]=get(key).value;raw[key]=get(key).get_line_edit().text
	return {"selected_id":selected_id,"pending_id":_pending_id,"dirty":dirty,"values":values,"raw_numbers":raw,"point_dirty":point_dirty,"parent":parent.get_selected_metadata(),"from":from_surface.get_selected_metadata(),"to":to_surface.get_selected_metadata(),"edge":edge.selected,"style":ramp_style.selected,"top_color":top_color.text,"edge_color":edge_color.text,"vertex":vertices.get_selected_items()[0] if not vertices.get_selected_items().is_empty() else -1}
func restore_draft(d: Dictionary) -> void:
	_refreshing=true;selected_id=str(d.get("selected_id",""));_pending_id=str(d.get("pending_id",""));load_fields()
	_refreshing=true
	for key in d.get("values",{}):get(key).value=d.values[key]
	choose(parent,str(d.get("parent","ground")));choose(from_surface,str(d.get("from","ground")));choose(to_surface,str(d.get("to","ground")));edge.select(int(d.get("edge",3)));ramp_style.select(int(d.get("style",0)));top_color.text=str(d.get("top_color","c5bf89"));edge_color.text=str(d.get("edge_color","b69d70"))
	var i: int=int(d.get("vertex",-1))
	if i>=0 and i<vertices.item_count:vertices.select(i)

	for key in d.get("raw_numbers",{}):get(key).get_line_edit().text=d.raw_numbers[key]
	point_dirty=bool(d.get("point_dirty",false));dirty=bool(d.get("dirty",false));_refreshing=false
