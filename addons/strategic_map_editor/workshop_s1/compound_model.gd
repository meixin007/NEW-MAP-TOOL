@tool
extends RefCounted
## W5 semantic room groups. Local origin is the front entrance, not a baked roof sprite.
const A=preload("asset_descriptor.gd")
const T=preload("terrain_geometry.gd")
const FIELDS=["kind","function","outer","holes","walls","rooms","roof_visible","floor_color","wall_color","roof_color","roof_material","wall_material"]
const ROOM_FIELDS=["room_id","rect","wall_height","roof_rise","door_edge","door_width","roof_style","roof_visible"]
static func rect(x: float,y: float,w: float,d: float) -> Array:
	return [[x,y],[x+w,y],[x+w,y+d],[x,y+d]]
static func room(id: String,r: Array,door: int=2) -> Dictionary:
	return {"room_id":id,"rect":r,"wall_height":18.0,"roof_rise":10.0,"door_edge":door,"door_width":14.0,"roof_style":"hip","roof_visible":true}
static func plan(kind: String,width: float=180,depth: float=160,function: String="residential") -> Dictionary:
	var walls: Array=[]
	for i in range(4):walls.append({"edge_id":"edge_"+str(i),"edge_index":i,"height":12.0,"style":"plaster","openings":[{"opening_id":"entrance","at":0.5,"width":24.0,"height":12.0}] if i==2 else []})
	var rooms: Array=[];var holes: Array=[]
	if kind=="room":
		rooms=[room("main",[-width*0.5,-depth,width,depth])]
		for w in walls:
			w.height=18.0
			if not w.openings.is_empty():w.openings[0].width=14.0;w.openings[0].height=14.0
	else:
		var wing:=32.0;var rear:=36.0
		holes=[rect(-width*0.5+wing+8,-depth+rear+8,width-2*wing-16,depth-rear-38)]
		rooms=[room("rear",[-width*0.5+6,-depth+6,width-12,rear]),room("west",[-width*0.5+6,-depth+rear+10,wing-10,depth-rear-28],1),room("east",[width*0.5-wing+4,-depth+rear+10,wing-10,depth-rear-28],3)]
		if function=="market":
			for r in rooms:r.roof_style="awning";r.wall_height=10;r.roof_rise=2
	return {"kind":kind,"function":function,"outer":rect(-width*0.5,-depth,width,depth),"holes":holes,"walls":walls,"rooms":rooms,"roof_visible":true,"floor_color":"d9c79c","wall_color":"d1be97","roof_color":"6e7066","roof_material":"","wall_material":""}
static func entity(id: String,surface: String,position: Vector2,layout: Dictionary) -> Dictionary:
	return {"entity_id":id,"kind":"compound","label":"院落" if layout.kind=="courtyard" else "房间","surface_id":surface,"ground_xy":[position.x,position.y],"local_height":0.0,"scale":1.0,"orientation":0.0,"management":"manual","room_plan":layout.duplicate(true)}
static func world(e: Dictionary,p: Vector2) -> Vector2:
	return T.vec(e.ground_xy)+p.rotated(deg_to_rad(float(e.orientation)))*float(e.scale)
static func footprint(e: Dictionary) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in e.room_plan.outer:result.append(world(e,T.vec(p)))
	return result
static func entrance(e: Dictionary) -> Dictionary:
	var plan: Dictionary=e.room_plan
	for wall in plan.walls:
		for opening in wall.openings:
			if opening.opening_id!="entrance":continue
			var a:=T.vec(plan.outer[int(wall.edge_index)]);var b:=T.vec(plan.outer[(int(wall.edge_index)+1)%plan.outer.size()]);var d: Vector2=(b-a).normalized()
			var sign: float=1 if not Geometry2D.is_polygon_clockwise(A.packed(plan.outer)) else -1
			var p:=world(e,a.lerp(b,float(opening.at)));var outward:=Vector2(d.y,-d.x).rotated(deg_to_rad(float(e.orientation)))*sign
			return {"socket_id":"entrance","role":"road","ground_xy":[p.x,p.y],"direction_deg":fposmod(rad_to_deg(outward.angle()),360),"width":float(opening.width)*float(e.scale)}
	var p:=world(e,Vector2.ZERO)
	if not plan.walls.is_empty():return {}
	return {"socket_id":"entrance","role":"road","ground_xy":[p.x,p.y],"direction_deg":fposmod(90+float(e.orientation),360),"width":float(plan.rooms[0].door_width)*float(e.scale)}
static func validate_plan(p: Dictionary,assets: Dictionary) -> String:
	for key in FIELDS:
		if not p.has(key):return "院落缺少字段："+key
	for key in p:
		if key not in FIELDS:return "未知院落字段："+str(key)
	if p.kind not in ["room","courtyard"] or p.function not in ["residential","market","storage"] or not p.roof_visible is bool:return "房间类型、用途或屋顶开关无效。"
	if not A.polygon_ok(p.outer) or p.outer.size()>32 or T.area(A.packed(p.outer))<400:return "院落地板轮廓无效或过小。"
	if not p.holes is Array or p.holes.size()>8 or not p.rooms is Array or p.rooms.is_empty() or p.rooms.size()>16 or not p.walls is Array or p.walls.size()>32:return "院落洞、房间或墙数量无效。"
	for key in ["floor_color","wall_color","roof_color"]:
		if not p[key] is String or not Color.html_is_valid(p[key]):return "院落颜色无效。"
	for key in ["roof_material","wall_material"]:
		if not p[key] is String or (not p[key].is_empty() and (not assets.has(p[key]) or not assets[p[key]].tags.has("surface_material"))):return "院落材质必须引用已固定版本的表面材质。"
	if not p.wall_material.is_empty():return "当前墙面使用可编辑底色，未支持墙面贴图。"
	var outer:=A.packed(p.outer);var holes: Array=[]
	for hole in p.holes:
		if not A.polygon_ok(hole) or hole.size()>32 or not T.enclosed(A.packed(hole),outer):return "院内空洞必须完整位于地板内部。"
		for q in A.packed(hole):
			for i in range(outer.size()):
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q,outer[i],outer[(i+1)%outer.size()]))<0.1:return "院内空洞不能接触地板边界。"
		for old in holes:
			if T.overlaps(old,A.packed(hole)):return "院内空洞不能交叠。"
		holes.append(A.packed(hole))
	var ids: Dictionary={};var room_polygons: Array=[]
	for r in p.rooms:
		if not r is Dictionary:return "房间必须为字典。"
		for key in ROOM_FIELDS:
			if not r.has(key):return "房间缺少字段："+key
		for key in r:
			if key not in ROOM_FIELDS:return "未知房间字段。"
		if not r.room_id is String or r.room_id.is_empty() or ids.has(r.room_id) or not r.rect is Array or r.rect.size()!=4:return "房间身份或矩形无效。"
		ids[r.room_id]=true
		for n in r.rect:
			if not A.numeric(n):return "房间矩形须为有限数。"
		if float(r.rect[2])<16 or float(r.rect[3])<16 or not A.numeric(r.wall_height) or float(r.wall_height)<4 or float(r.wall_height)>80 or not A.numeric(r.roof_rise) or float(r.roof_rise)<0 or float(r.roof_rise)>60 or not A.numeric(r.door_edge) or float(r.door_edge)!=floorf(float(r.door_edge)) or float(r.door_edge)<0 or float(r.door_edge)>3 or not A.numeric(r.door_width) or float(r.door_width)<6 or float(r.door_width)>minf(float(r.rect[2]),float(r.rect[3]))-4 or r.roof_style not in ["hip","gable","awning"] or not r.roof_visible is bool:return "房间尺寸、门洞或屋顶参数无效。"
		var poly:=A.packed(rect(r.rect[0],r.rect[1],r.rect[2],r.rect[3]))
		if not T.enclosed(poly,outer):return "房间完整占地超出院落地板。"
		for hole in holes:
			if T.overlaps(poly,hole):return "房间／屋顶侵入院内空洞，未填满空院。"
		for other in room_polygons:
			if T.overlaps(poly,other):return "房间互相交叠。"
		room_polygons.append(poly)
	var edges: Dictionary={};var edge_ids: Dictionary={};var opening_ids: Dictionary={}
	for w in p.walls:
		if not w is Dictionary or not w.get("edge_id") is String or not A.numeric(w.get("edge_index")) or float(w.edge_index)!=floorf(float(w.edge_index)) or w.edge_index<0 or w.edge_index>=p.outer.size() or edges.has(w.edge_index) or not A.numeric(w.get("height")) or float(w.height)<4 or float(w.height)>80 or w.get("style") not in ["none","plaster","timber"] or not w.get("openings") is Array or w.openings.size()>4:return "墙边身份、类型或高度无效。"
		for key in w:
			if key not in ["edge_id","edge_index","height","style","openings"]:return "未知墙边字段。"
		if w.edge_id.is_empty() or edge_ids.has(w.edge_id) or edges.has(int(w.edge_index)):return "墙边身份或索引重复。"
		edges[int(w.edge_index)]=true;edge_ids[w.edge_id]=true
		var length:=T.vec(p.outer[int(w.edge_index)]).distance_to(T.vec(p.outer[(int(w.edge_index)+1)%p.outer.size()]));var intervals: Array=[]
		for opening in w.openings:
			if not opening is Dictionary or not opening.get("opening_id") is String or not A.numeric(opening.get("at")) or not A.numeric(opening.get("width")) or not A.numeric(opening.get("height")) or float(opening.width)<6 or float(opening.height)<4 or float(opening.height)>float(w.height):return "门洞参数无效。"
			for key in opening:
				if key not in ["opening_id","at","width","height"]:return "未知门洞字段。"
			if opening.opening_id.is_empty() or opening_ids.has(opening.opening_id):return "门洞身份重复或为空。"
			opening_ids[opening.opening_id]=true
			var a: float=float(opening.at)*length-float(opening.width)*0.5;var b: float=a+float(opening.width)
			if a<3 or b>length-3:return "门洞超出墙边或没有保留门柱。"
			for old in intervals:
				if a<old[1] and b>old[0]:return "门洞互相交叠。"
			intervals.append([a,b])
	return ""
static func validate_entity(p: Dictionary,e: Dictionary,check_support: bool=true) -> String:
	if not e.get("room_plan") is Dictionary or not A.numeric(e.get("orientation")) or not A.numeric(e.get("scale")) or float(e.scale)<0.5 or float(e.scale)>2:return "院落方向、比例或编辑计划无效。"
	var issue:=validate_plan(e.room_plan,p.asset_refs)
	if not issue.is_empty():return issue
	if check_support and not T.contains(p,e.surface_id,footprint(e)):return "院落完整占地未受同一支持面支撑。"
	return ""
static func floor_parts(p: Dictionary) -> Array:
	# Exact even-odd slab decomposition preserves actual holes without painting over them.
	var rings: Array=[p.outer]+p.holes;var ys: Array=[];var result: Array=[]
	for ring in rings:
		for q in ring:
			if not ys.has(float(q[1])):ys.append(float(q[1]))
	ys.sort()
	for i in range(ys.size()-1):
		var lo: float=ys[i];var hi: float=ys[i+1];var mid: float=(lo+hi)*0.5;var events: Array=[]
		for ring in rings:
			for j in range(ring.size()):
				var a:=T.vec(ring[j]);var b:=T.vec(ring[(j+1)%ring.size()])
				if mid<=minf(a.y,b.y) or mid>=maxf(a.y,b.y):continue
				events.append({"mid":lerpf(a.x,b.x,(mid-a.y)/(b.y-a.y)),"lo":lerpf(a.x,b.x,(lo-a.y)/(b.y-a.y)),"hi":lerpf(a.x,b.x,(hi-a.y)/(b.y-a.y))})
		events.sort_custom(func(a,b):return a.mid<b.mid)
		for j in range(0,events.size()-1,2):
			var a: Dictionary=events[j];var b: Dictionary=events[j+1];var poly:=PackedVector2Array([Vector2(a.lo,lo),Vector2(b.lo,lo),Vector2(b.hi,hi),Vector2(a.hi,hi)])
			if T.area(poly)>0.02:result.append(poly)
	return result
