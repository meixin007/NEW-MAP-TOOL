@tool
extends RefCounted
const C=preload("compound_model.gd")
const A=preload("asset_descriptor.gd")
const P=preload("surface_projection.gd")
static func bounds(poly: PackedVector2Array) -> Rect2:
	var box:=Rect2(poly[0],Vector2.ZERO)
	for q in poly:box=box.expand(q)
	return box
static func append(out: Array,p: Dictionary,e: Dictionary,local: PackedVector2Array,heights: Array,color: Color,layer: int=2,material: String="",outline: bool=true) -> void:
	var poly:=PackedVector2Array();var uv:=PackedVector2Array();var depth: float=-INF
	for i in range(local.size()):
		var world:=C.world(e,local[i]);var m: Array=p.style_profile.ground_matrix;depth=maxf(depth,float(m[1])*world.x+float(m[3])*world.y)
		poly.append(P.project_point(p,world,e.surface_id,float(e.local_height)+float(heights[i])*float(e.scale)));uv.append(Vector2(local[i].x/128,local[i].y/96))
	if A.polygon_ok(Array(poly).map(func(q):return [q.x,q.y])):
		out.append({"entity":e,"entity_id":e.entity_id,"position":P.project_point(p,C.world(e,Vector2.ZERO),e.surface_id,float(e.local_height)),"depth":depth,"part_order":out.size(),"paint_bounds":bounds(poly),"polygons":[poly],"color":color,"material":material,"uvs":uv,"outline":outline,"render_layer":layer})
static func wall(out: Array,p: Dictionary,e: Dictionary,a: Vector2,b: Vector2,height: float,openings: Array,style: String,color: Color,windows: bool=false) -> void:
	if style=="none":return
	var length:=a.distance_to(b);var intervals: Array=[]
	for opening in openings:intervals.append({"a":float(opening.at)-float(opening.width)/(length*2),"b":float(opening.at)+float(opening.width)/(length*2),"height":float(opening.height)})
	intervals.sort_custom(func(x,y):return x.a<y.a)
	var start:=0.0
	for gap in intervals:
		if gap.a>start:append(out,p,e,PackedVector2Array([a.lerp(b,start),a.lerp(b,gap.a),a.lerp(b,gap.a),a.lerp(b,start)]),[0,0,height,height],color)
		if gap.height<height:append(out,p,e,PackedVector2Array([a.lerp(b,gap.a),a.lerp(b,gap.b),a.lerp(b,gap.b),a.lerp(b,gap.a)]),[gap.height,gap.height,height,height],color)
		start=gap.b
	if start<1:append(out,p,e,PackedVector2Array([a.lerp(b,start),b,b,a.lerp(b,start)]),[0,0,height,height],color)
	# The cap is an actual narrow horizontal band, kept independently of the roof switch.
	var normal:=Vector2((b-a).y,-(b-a).x).normalized()*1.5
	append(out,p,e,PackedVector2Array([a-normal,b-normal,b+normal,a+normal]),[height,height,height,height],Color("8e8063"))
	if windows and length>36:
		for t in [0.22,0.78]:
			var mid:=a.lerp(b,t);var d: Vector2=(b-a).normalized()*5
			append(out,p,e,PackedVector2Array([mid-d,mid+d,mid+d,mid-d]),[height*0.4,height*0.4,height*0.8,height*0.8],Color("776a51"))
static func entries(p: Dictionary,e: Dictionary) -> Array:
	var out: Array=[];var plan: Dictionary=e.room_plan
	for polygon in C.floor_parts(plan):append(out,p,e,polygon,Array(range(polygon.size())).map(func(_q):return 0),Color(plan.floor_color),0,"",false)
	for room in plan.rooms:
		var r: Array=room.rect;var ring:=A.packed(C.rect(r[0],r[1],r[2],r[3]))
		for i in range(4):
			if plan.kind=="room" and not plan.walls.is_empty():continue
			var door: Array=[{"at":0.5,"width":room.door_width,"height":minf(14,room.wall_height)}] if i==room.door_edge else []
			wall(out,p,e,ring[i],ring[(i+1)%4],room.wall_height,door,"timber",Color(plan.wall_color).darkened(0.1 if i in [1,2] else 0),true)
		if not plan.roof_visible or not room.roof_visible:continue
		var x: float=r[0]-4;var y: float=r[1]-4;var w: float=r[2]+8;var d: float=r[3]+8
		var tl:=Vector2(x,y);var tr:=Vector2(x+w,y);var br:=Vector2(x+w,y+d);var bl:=Vector2(x,y+d)
		var a:=Vector2(x+w*0.18,y+d*0.5);var b:=Vector2(x+w*0.82,y+d*0.5)
		if d>w:
			a=Vector2(x+w*0.5,y+d*0.18);b=Vector2(x+w*0.5,y+d*0.82)
		var h: float=room.wall_height+2;var ridge: float=h+float(room.roof_rise);var material: String=plan.roof_material
		var tint:=Color.WHITE if not material.is_empty() else Color(plan.roof_color)
		if room.roof_style=="awning":
			append(out,p,e,PackedVector2Array([tl,tr,br,bl]),[h+2,h+2,h,h],Color("c5aa74"));continue
		if room.roof_style=="gable":
			if w>=d:a.x=x;b.x=x+w
			else:a.y=y;b.y=y+d
		if w>=d:
			append(out,p,e,PackedVector2Array([tl,tr,b,a]),[h,h,ridge,ridge],tint,2,material)
			append(out,p,e,PackedVector2Array([a,b,br,bl]),[ridge,ridge,h,h],tint.darkened(0.12),2,material)
			append(out,p,e,PackedVector2Array([tl,a,bl]),[h,ridge,h],tint.darkened(0.06),2,material)
			append(out,p,e,PackedVector2Array([tr,br,b]),[h,h,ridge],tint.darkened(0.2),2,material)
		else:
			append(out,p,e,PackedVector2Array([tl,a,b,bl]),[h,ridge,ridge,h],tint,2,material)
			append(out,p,e,PackedVector2Array([a,tr,br,b]),[ridge,h,h,ridge],tint.darkened(0.16),2,material)
			append(out,p,e,PackedVector2Array([tl,tr,a]),[h,h,ridge],tint.darkened(0.06),2,material)
			append(out,p,e,PackedVector2Array([bl,b,br]),[h,ridge,h],tint.darkened(0.2),2,material)
	for w in plan.walls:
		wall(out,p,e,A.packed(plan.outer)[int(w.edge_index)],A.packed(plan.outer)[(int(w.edge_index)+1)%plan.outer.size()],w.height,w.openings,w.style,Color(plan.wall_color))
	return out
