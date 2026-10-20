@tool
extends VBoxContainer
const C=preload("../compound_model.gd")
const Model=preload("../project_model.gd")
var host
var objects: ItemList
var rooms: ItemList
var walls: ItemList
var holes: ItemList
var floor_points: ItemList
var floor_x: SpinBox
var floor_y: SpinBox
var kind: OptionButton
var use: OptionButton
var material_picker: OptionButton
var roof: CheckBox
var room_roof: CheckBox
var roof_style: OptionButton
var room_x: SpinBox
var room_y: SpinBox
var room_w: SpinBox
var room_d: SpinBox
var wall_height: SpinBox
var roof_rise: SpinBox
var door_edge: SpinBox
var door_width: SpinBox
var wall_style: OptionButton
var outer_height: SpinBox
var opening_at: SpinBox
var opening_width: SpinBox
var opening_height: SpinBox
var selected_id: String=""
var dirty:=false
var _refreshing:=false
var _pending_id: String=""
var _room_index: int=0
var _wall_index: int=0
var _wall_dirty:=false
func spin(label: String,value: float,lo: float,hi: float,step: float=1) -> SpinBox:
	var f:=SpinBox.new();f.prefix=label+" ";f.min_value=lo;f.max_value=hi;f.step=step;f.value=value;add_child(f)
	f.value_changed.connect(func(_v):mark_dirty());f.get_line_edit().text_changed.connect(func(_v):mark_dirty());return f
func picker(labels: Array) -> OptionButton:
	var f:=OptionButton.new();add_child(f)
	for label in labels:f.add_item(label)
	f.item_selected.connect(func(_i):mark_dirty());return f
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint:=Label.new();hint.text="先在对象／台地页选放置面，再画两角。\n屋顶、房间、院墙门洞和地板空洞分别保留。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	host.button(self,"应用参考斜俯视（当前项目）",func():host.report(host.session.dispatch({"op":"set_reference_projection"}));host.canvas.fit_map())
	kind=picker(["院落","独立房间"]);use=picker(["住宅","市集","仓储"])
	material_picker=picker([])
	host.button(self,"画房间／院落（两角）",func():dirty=false;host.request_canvas_mode("compound_draw"))
	objects=ItemList.new();objects.custom_minimum_size.y=130;add_child(objects);objects.item_selected.connect(func(i):select_compound(str(objects.get_item_metadata(i))))
	floor_points=ItemList.new();floor_points.custom_minimum_size.y=90;add_child(floor_points)
	floor_x=spin("地板顶点局部 X",0,-2000,2000);floor_y=spin("地板顶点局部 Y",0,-2000,2000)
	floor_points.item_selected.connect(func(i):
		var e:=current()
		if not e.is_empty() and i<e.room_plan.outer.size():_refreshing=true;floor_x.value=e.room_plan.outer[i][0];floor_y.value=e.room_plan.outer[i][1];_refreshing=false)
	host.button(self,"预览地板轮廓顶点",func():
		var e:=current();var selected:=floor_points.get_selected_items()
		if e.is_empty() or selected.is_empty():host.status.text="先选择地板顶点。";return
		var plan: Dictionary=e.room_plan.duplicate(true);plan.outer[selected[0]]=[floor_x.value,floor_y.value];preview_plan(plan))
	roof=CheckBox.new();roof.text="显示本组屋顶";roof.button_pressed=true;add_child(roof);roof.toggled.connect(func(_v):mark_dirty())
	rooms=ItemList.new();rooms.custom_minimum_size.y=110;add_child(rooms);rooms.item_selected.connect(select_room)
	room_x=spin("房间局部 X",0,-1000,1000);room_y=spin("房间局部 Y",0,-1000,1000);room_w=spin("房间宽",100,16,512);room_d=spin("房间深",70,16,512)
	wall_height=spin("房间墙高",18,4,80);roof_rise=spin("屋脊抬高",10,0,60);door_edge=spin("房间门边 0—3",2,0,3);door_width=spin("房间门宽",14,6,128)
	roof_style=picker(["歇山／四坡 hip","双坡 gable","市集棚顶 awning"])
	room_roof=CheckBox.new();room_roof.text="显示所选房间屋顶";room_roof.button_pressed=true;add_child(room_roof);room_roof.toggled.connect(func(_v):mark_dirty())
	host.button(self,"预览房间／屋顶参数",preview_rooms)
	host.button(self,"在组内添加房间（两角）",func():
		if current().is_empty():host.status.text="先选择院落。";return
		host.request_canvas_mode("compound_room",func():host.canvas.compound_target_id=selected_id))
	host.button(self,"删除所选房间（预览）",func():
		var e:=current()
		if e.is_empty():return
		var plan: Dictionary=e.room_plan.duplicate(true)
		if _room_index>=0 and _room_index<plan.rooms.size():plan.rooms.remove_at(_room_index);preview_plan(plan))
	walls=ItemList.new();walls.custom_minimum_size.y=100;add_child(walls);walls.item_selected.connect(select_wall)
	wall_style=picker(["灰泥墙 plaster","木墙 timber","无墙 none"]);outer_height=spin("所选院墙高",12,4,80)
	opening_at=spin("门洞沿边比例",0.5,0,1,0.05);opening_width=spin("门洞宽",24,6,128);opening_height=spin("门洞高",12,4,80)
	for f in [wall_style]:f.item_selected.connect(func(_v):
		if not _refreshing:_wall_dirty=true)
	for f in [outer_height,opening_at,opening_width,opening_height]:f.value_changed.connect(func(_v):
		if not _refreshing:_wall_dirty=true)
	host.button(self,"预览院墙／门洞",preview_wall)
	host.button(self,"移除所选边全部门洞（预览）",func():
		var e:=current()
		if e.is_empty() or e.room_plan.walls.is_empty():return
		var plan: Dictionary=e.room_plan.duplicate(true);plan.walls[_wall_index].openings=[];preview_plan(plan))
	holes=ItemList.new();holes.custom_minimum_size.y=90;add_child(holes)
	host.button(self,"添加地板空洞（两角）",func():
		if current().is_empty():host.status.text="先选择房间／院落。";return
		host.request_canvas_mode("compound_hole",func():host.canvas.compound_target_id=selected_id))
	host.button(self,"删除所选空洞（预览）",func():
		var e:=current();var chosen:=holes.get_selected_items()
		if e.is_empty() or chosen.is_empty():return
		var plan: Dictionary=e.room_plan.duplicate(true);plan.holes.remove_at(chosen[0]);preview_plan(plan))
	host.button(self,"应用房间预览（一次撤销）",apply_preview)
	host.button(self,"取消房间输入／预览",cancel)
	host.button(self,"院落转为手工（保留身份）",func():host.report(host.session.dispatch({"op":"detach_entity","entity_id":selected_id})))
	host.button(self,"固定所选院落",func():host.report(host.session.dispatch({"op":"fix_entity","entity_id":selected_id})))
	refresh()
func mark_dirty() -> void:
	if _refreshing:return
	dirty=true
	if host.session.has_preview():host.session.cancel_preview();host.canvas._last_revision=-1;host.canvas.queue_redraw()
	if host.session.job_in_progress():host.session.cancel_preview_job()
func current() -> Dictionary:
	for e in host.snapshot_for_ui().materialized_snapshot.entities:
		if e.entity_id==selected_id and e.kind=="compound":return e
	return {}
func refresh() -> void:
	if not is_instance_valid(objects):return
	_refreshing=true;objects.clear();var p: Dictionary=host.snapshot_for_ui()
	for e in p.materialized_snapshot.entities:
		if e.kind!="compound":continue
		objects.add_item(("[手工] " if e.management=="manual" else "[固定] " if e.management=="fixed" else "[自动] ")+e.label);objects.set_item_metadata(objects.item_count-1,e.entity_id)
		if e.entity_id==selected_id:objects.select(objects.item_count-1)
	var chosen: String=str(material_picker.get_selected_metadata()) if material_picker.item_count>0 else ""
	material_picker.clear();material_picker.add_item("屋顶 · 程序底色");material_picker.set_item_metadata(0,"")
	for ref in p.asset_refs:
		if p.asset_refs[ref].tags.has("surface_material"):
			material_picker.add_item(p.asset_refs[ref].label);material_picker.set_item_metadata(material_picker.item_count-1,ref)
			if ref==chosen:material_picker.select(material_picker.item_count-1)
	_refreshing=false
	if not dirty:load_entity()
func show_entity(id: String) -> void:
	if id==selected_id or dirty:return
	selected_id=id;load_entity()
func select_compound(id: String) -> void:
	if dirty or host.canvas.has_pending_input():host.status.text="先应用或取消房间输入。";return
	selected_id=id;host.select_entity(id);load_entity()
func load_entity() -> void:
	var e:=current();rooms.clear();walls.clear();holes.clear();floor_points.clear()
	if e.is_empty():return
	_refreshing=true;var p: Dictionary=e.room_plan;roof.button_pressed=p.roof_visible;kind.select(0 if p.kind=="courtyard" else 1);use.select(["residential","market","storage"].find(p.function))
	for i in range(material_picker.item_count):
		if material_picker.get_item_metadata(i)==p.roof_material:material_picker.select(i)
	for r in p.rooms:rooms.add_item(r.room_id+" · "+str(r.rect))
	for w in p.walls:walls.add_item(w.edge_id+" · "+w.style+" · 门洞 "+str(w.openings.size()))
	for hole in p.holes:holes.add_item("空洞 · "+str(hole))
	for q in p.outer:floor_points.add_item(str(q))
	_room_index=clampi(_room_index,0,p.rooms.size()-1);rooms.select(_room_index);select_room(_room_index)
	if not p.walls.is_empty():_wall_index=clampi(_wall_index,0,p.walls.size()-1);walls.select(_wall_index);select_wall(_wall_index)
	if holes.item_count>0:holes.select(0)
	_refreshing=false;_wall_dirty=false
func select_room(i: int) -> void:
	var e:=current()
	if e.is_empty() or i>=e.room_plan.rooms.size():return
	if dirty and not _refreshing:rooms.select(_room_index);host.status.text="先预览或取消当前房间参数。";return
	_room_index=i;var r: Dictionary=e.room_plan.rooms[i];var old:=_refreshing;_refreshing=true
	room_x.value=r.rect[0];room_y.value=r.rect[1];room_w.value=r.rect[2];room_d.value=r.rect[3];wall_height.value=r.wall_height;roof_rise.value=r.roof_rise;door_edge.value=r.door_edge;door_width.value=r.door_width;roof_style.select(["hip","gable","awning"].find(r.roof_style));room_roof.button_pressed=r.roof_visible;_refreshing=old
func select_wall(i: int) -> void:
	var e:=current()
	if e.is_empty() or i>=e.room_plan.walls.size():return
	if _wall_dirty and not _refreshing:walls.select(_wall_index);host.status.text="先预览或取消院墙参数。";return
	_wall_index=i;var w: Dictionary=e.room_plan.walls[i];var old:=_refreshing;_refreshing=true;wall_style.select(["plaster","timber","none"].find(w.style));outer_height.value=w.height
	if not w.openings.is_empty():opening_at.value=w.openings[0].at;opening_width.value=w.openings[0].width;opening_height.value=w.openings[0].height
	_refreshing=old
func drawn(points: Array,tool: String) -> void:
	var lo:=Vector2(minf(points[0][0],points[1][0]),minf(points[0][1],points[1][1]));var hi:=Vector2(maxf(points[0][0],points[1][0]),maxf(points[0][1],points[1][1]))
	if tool=="compound_draw":
		var plan:=C.plan("courtyard" if kind.selected==0 else "room",hi.x-lo.x,hi.y-lo.y,["residential","market","storage"][use.selected]);plan.roof_material=str(material_picker.get_selected_metadata());plan.roof_visible=roof.button_pressed
		var e:=C.entity(Model.new_id("compound"),host.canvas.active_surface_id,Vector2((lo.x+hi.x)*0.5,hi.y),plan);_pending_id=e.entity_id;preview({"op":"add_manual","entity":e})
	else:
		var e:=current()
		if e.is_empty():return
		var plan: Dictionary=e.room_plan.duplicate(true)
		if tool=="compound_hole":plan.holes.append(C.rect(lo.x,lo.y,hi.x-lo.x,hi.y-lo.y))
		else:plan.rooms.append(C.room(Model.new_id("room"),[lo.x,lo.y,hi.x-lo.x,hi.y-lo.y]))
		preview_plan(plan)
func preview_rooms() -> void:
	var e:=current()
	if e.is_empty():host.status.text="先选择院落／房间。";return
	var plan: Dictionary=e.room_plan.duplicate(true);var r: Dictionary=plan.rooms[_room_index]
	r.rect=[room_x.value,room_y.value,room_w.value,room_d.value];r.wall_height=wall_height.value;r.roof_rise=roof_rise.value;r.door_edge=door_edge.value;r.door_width=door_width.value;r.roof_style=["hip","gable","awning"][roof_style.selected];r.roof_visible=room_roof.button_pressed
	plan.roof_visible=roof.button_pressed;plan.roof_material=str(material_picker.get_selected_metadata());plan.function=["residential","market","storage"][use.selected];preview_plan(plan)
func preview_wall() -> void:
	var e:=current()
	if e.is_empty() or e.room_plan.walls.is_empty():host.status.text="请先选择一条院墙。";return
	var plan: Dictionary=e.room_plan.duplicate(true);var w: Dictionary=plan.walls[_wall_index];w.style=["plaster","timber","none"][wall_style.selected];w.height=outer_height.value
	w.openings=[{"opening_id":"entrance" if int(w.edge_index)==2 else "door_"+str(w.edge_index),"at":opening_at.value,"width":opening_width.value,"height":opening_height.value}];preview_plan(plan)
func preview_plan(plan: Dictionary) -> void:
	_pending_id=selected_id;preview({"op":"update_entity","entity_id":selected_id,"patch":{"room_plan":plan}})
func preview(command: Dictionary) -> void:
	if host.session.has_preview() or host.session.job_in_progress():host.status.text="先应用或取消现有候选。";return
	var result: Dictionary=host.queue_candidate(command,"room")
	if result.ok:dirty=false;_wall_dirty=false
	host.canvas._last_revision=-1;host.canvas.queue_redraw()
func apply_preview() -> void:
	var result: Dictionary=host.session.commit_preview();host.report(result)
	if result.ok:dirty=false;_wall_dirty=false;selected_id=_pending_id;host.select_entity(selected_id);refresh()
func cancel() -> void:
	dirty=false;_wall_dirty=false;host.canvas.cancel();refresh()
func capture_draft() -> Dictionary:
	var values: Dictionary={};var raw: Dictionary={}
	for key in ["room_x","room_y","room_w","room_d","wall_height","roof_rise","door_edge","door_width","outer_height","opening_at","opening_width","opening_height","floor_x","floor_y"]:values[key]=get(key).value;raw[key]=get(key).get_line_edit().text
	return {"selected_id":selected_id,"pending_id":_pending_id,"dirty":dirty,"wall_dirty":_wall_dirty,"values":values,"raw_numbers":raw,"kind":kind.selected,"function":use.selected,"material":str(material_picker.get_selected_metadata()),"roof":roof.button_pressed,"room_roof":room_roof.button_pressed,"roof_style":roof_style.selected,"wall_style":wall_style.selected,"room_index":_room_index,"wall_index":_wall_index}
func restore_draft(d: Dictionary) -> void:
	selected_id=str(d.get("selected_id",""));_pending_id=str(d.get("pending_id",""));_room_index=int(d.get("room_index",0));_wall_index=int(d.get("wall_index",0));load_entity();_refreshing=true
	for key in d.get("values",{}):get(key).value=d.values[key]
	for key in d.get("raw_numbers",{}):get(key).get_line_edit().text=d.raw_numbers[key]
	kind.select(int(d.get("kind",0)));use.select(int(d.get("function",0)));roof_style.select(int(d.get("roof_style",0)));wall_style.select(int(d.get("wall_style",0)));roof.button_pressed=bool(d.get("roof",true));room_roof.button_pressed=bool(d.get("room_roof",true))
	for i in range(material_picker.item_count):
		if material_picker.get_item_metadata(i)==d.get("material",""):material_picker.select(i)
	dirty=bool(d.get("dirty",false));_wall_dirty=bool(d.get("wall_dirty",false));_refreshing=false
