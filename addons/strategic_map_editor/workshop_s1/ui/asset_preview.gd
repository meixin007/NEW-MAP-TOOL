@tool
extends Control
const Asset = preload("../asset_descriptor.gd")
signal edited
var descriptor: Dictionary = {}
var texture: Texture2D
var mode := "anchor"
var socket_index := 0
var _scale := 1.0
var _origin := Vector2.ZERO
var _dragging := false

func _ready() -> void:
	custom_minimum_size=Vector2(360,320)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	clip_contents=true
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("283430"))
	if descriptor.is_empty(): return
	var r: Array=descriptor.region_px
	_scale=minf((size.x-60)/float(r[2]),(size.y-60)/float(r[3]))
	_origin=(size-Vector2(r[2],r[3])*_scale)*0.5
	var rect:=Rect2(_origin,Vector2(r[2],r[3])*_scale)
	draw_rect(rect,Color("d8d4c4"))
	if texture!=null: draw_texture_rect_region(texture,rect,Rect2(r[0],r[1],r[2],r[3]))
	var anchor:=_origin+Vector2(descriptor.anchor_px[0],descriptor.anchor_px[1])*_scale
	draw_line(anchor-Vector2(10,0),anchor+Vector2(10,0),Color("d28d26"),2)
	draw_line(anchor-Vector2(0,10),anchor+Vector2(0,10),Color("d28d26"),2)
	var unit: float=float(descriptor.nominal_size_units[0])/float(r[2])
	var ground:=PackedVector2Array()
	for p in descriptor.ground_footprint: ground.append(anchor+Vector2(p[0],p[1])*_scale/unit)
	if ground.size()>1: ground.append(ground[0]);draw_polyline(ground,Color("438d59"),2)
	draw_rect(rect,Color("ceab47"),false,2)
	for i in range(descriptor.sockets.size()):
		var s: Dictionary=descriptor.sockets[i]
		var p:=_origin+Vector2(s.position_px[0],s.position_px[1])*_scale
		draw_circle(p,5,Color("48a5d1"))
		draw_line(p,p+Vector2.RIGHT.rotated(deg_to_rad(float(s.direction_deg)))*20,Color("48a5d1"),2)
		draw_string(ThemeDB.fallback_font,p+Vector2(8,-6),s.socket_id,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	draw_string(ThemeDB.fallback_font,Vector2(10,20),"像素标尺：0—%d × 0—%d | 黄 paint · 绿 ground · 蓝 socket"%[r[2],r[3]],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
func _gui_input(event: InputEvent) -> void:
	if descriptor.is_empty(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging=event.pressed
		if _dragging: _edit_at(event.position, true)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_edit_at(event.position, false)
		accept_event()
func _edit_at(screen: Vector2, begin: bool) -> void:
	var r: Array=descriptor.region_px
	var p:=((screen-_origin)/_scale).clamp(Vector2.ZERO,Vector2(r[2],r[3]))
	if mode=="anchor": descriptor.anchor_px=[snappedf(p.x,1),snappedf(p.y,1)]
	elif mode=="ground" and begin:
		var unit: float=float(descriptor.nominal_size_units[0])/float(r[2])
		var point: Vector2=(p-Vector2(descriptor.anchor_px[0],descriptor.anchor_px[1]))*unit
		descriptor.ground_footprint.append([point.x,point.y])
	elif mode=="socket" and socket_index<descriptor.sockets.size(): descriptor.sockets[socket_index].position_px=[snappedf(p.x,1),snappedf(p.y,1)]
	queue_redraw()
	edited.emit()
