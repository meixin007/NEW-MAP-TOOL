@tool
extends RefCounted
## W4 authoring geometry. No scene nodes, resources, caches or mutable shared state.
const Asset=preload("asset_descriptor.gd")
const TERRACE_FIELDS=["surface_id","kind","parent_surface_id","height","outline","edge_styles","edge_widths","top_color","edge_color","locked"]
const RAMP_FIELDS=["surface_id","kind","height","from_surface_id","to_surface_id","start","end","width","style","locked"]

static func enabled(p: Dictionary) -> bool:
	return p.surfaces.any(func(s):return s.get("kind") in ["terrace","ramp"])
static func surface(p: Dictionary, id: String) -> Dictionary:
	for s in p.surfaces:
		if s.surface_id==id:return s
	return {}
static func vec(a: Array) -> Vector2:
	return Vector2(a[0],a[1])
static func area(poly: PackedVector2Array) -> float:
	var n:=0.0
	for i in range(poly.size()):n+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(n)*0.5
static func overlaps(a: PackedVector2Array,b: PackedVector2Array) -> bool:
	for part in Geometry2D.intersect_polygons(a,b):
		if area(part)>0.02:return true
	return false
static func enclosed(a: PackedVector2Array,b: PackedVector2Array) -> bool:
	for part in Geometry2D.clip_polygons(a,b):
		if area(part)>0.02:return false
	return true
static func lineage(p: Dictionary,id: String) -> Array:
	var result: Array=[]
	while id!="ground" and not id.is_empty() and not result.has(id):
		result.append(id);id=str(surface(p,id).get("parent_surface_id","ground"))
	return result
static func absolute_height(p: Dictionary,id: String,point: Vector2=Vector2.ZERO) -> float:
	var s:=surface(p,id)
	if s.is_empty() or id=="ground":return 0.0
	if s.get("kind")=="ramp":
		var a:=vec(s.start);var d:=vec(s.end)-a
		return lerpf(absolute_height(p,s.from_surface_id),absolute_height(p,s.to_surface_id),clampf((point-a).dot(d)/d.length_squared(),0,1))
	var h:=0.0
	for ancestor in lineage(p,id):h+=float(surface(p,ancestor).height)
	return h
static func capsule(a: Vector2,b: Vector2,width: float) -> PackedVector2Array:
	var result:=PackedVector2Array();var angle: float=(b-a).angle()
	for j in range(9):result.append(b+Vector2.from_angle(angle+PI*0.5-j*PI/8)*width*0.5)
	for j in range(9):result.append(a+Vector2.from_angle(angle-PI*0.5-j*PI/8)*width*0.5)
	return result
static func outline(s: Dictionary) -> PackedVector2Array:
	return capsule(vec(s.start),vec(s.end),float(s.width)) if s.get("kind")=="ramp" else Asset.packed(s.get("outline",[]))
static func edge_bands(s: Dictionary) -> Array:
	var ring:=outline(s);var result: Array=[]
	if s.get("kind")!="terrace":return result
	var sign: float=1.0 if not Geometry2D.is_polygon_clockwise(ring) else -1.0
	for i in range(ring.size()):
		var a:=ring[i];var b:=ring[(i+1)%ring.size()]
		var d: Vector2=(b-a).normalized();var n:=Vector2(d.y,-d.x)*sign
		var w:=float(s.edge_widths[i]);var spread: float=w if s.edge_styles[i] in ["slope","bank"] else 0.0
		result.append({"a":a,"b":b,"normal":n,"outer_a":a+n*spread,"outer_b":b+n*spread,"style":s.edge_styles[i],"polygon":PackedVector2Array([a,b,b+n*spread,a+n*spread])})
	return result
static func coverage(s: Dictionary) -> Array:
	var result: Array=[outline(s)]
	var bands:=edge_bands(s)
	for b in bands:
		if area(b.polygon)>0.02:result.append(b.polygon)
	for i in range(bands.size()):
		var a: Dictionary=bands[(i-1+bands.size())%bands.size()];var b: Dictionary=bands[i]
		var join:=PackedVector2Array([b.a,a.outer_b,b.outer_a])
		if area(join)>0.02:result.append(join)
	return result
static func contains(p: Dictionary,id: String,footprint: PackedVector2Array,landings: bool=false) -> bool:
	var s:=surface(p,id)
	if s.is_empty() or footprint.size()<3:return false
	if id=="ground":
		var size:=vec(p.legacy_document.canvas_size)
		if not enclosed(footprint,PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])):return false
	elif not enclosed(footprint,outline(s)):return false
	if s.get("kind")=="ramp":return true
	for child in p.surfaces:
		if child.get("parent_surface_id")==id:
			for polygon in coverage(child):
				if overlaps(footprint,polygon):return false
		if child.get("kind")=="ramp" and id in [child.from_surface_id,child.to_surface_id]:
			var a:=vec(child.start);var b:=vec(child.end);var d: Vector2=(b-a).normalized()
			# Explicit ribbon joins may overlap the flat endpoint landing, never the ramp interior.
			var inset: float=float(child.width)*0.5 if landings else 0.0
			var core:=capsule(a+d*inset,b-d*inset,maxf(1.0,float(child.width)-0.1))
			if landings:
				var n:=Vector2(d.y,-d.x)*float(child.width)*0.5
				core=PackedVector2Array([a+d*inset+n,b-d*inset+n,b-d*inset-n,a+d*inset-n])
			if overlaps(footprint,core):return false
	return true
static func command(p: Dictionary,c: Dictionary) -> Dictionary:
	if c.op=="add_terrain":
		if not c.get("surface") is Dictionary:return {"ok":false,"error":"地形输入必须为字典。"}
		p.surfaces.append(c.surface.duplicate(true));return {"ok":true}
	var s:=surface(p,str(c.get("surface_id","")))
	if s.is_empty() or s.surface_id=="ground" or not s.has("kind"):return {"ok":false,"error":"请选中 W4 台地或坡道。"}
	if c.op=="lock_terrain":
		if not c.get("locked") is bool:return {"ok":false,"error":"锁定值无效。"}
		s.locked=c.locked;return {"ok":true}
	if s.locked:return {"ok":false,"error":"地形已锁定，请先明确解锁。"}
	if c.op=="delete_terrain":
		if p.surfaces.any(func(v):return v.get("parent_surface_id")==s.surface_id or v.get("from_surface_id")==s.surface_id or v.get("to_surface_id")==s.surface_id) or p.recipes.any(func(r):return r.surface_id==s.surface_id):return {"ok":false,"error":"台地仍有子面／坡道／配方依赖，未删除。"}
		p.surfaces.erase(s)
	else:
		if not c.get("patch") is Dictionary:return {"ok":false,"error":"地形补丁无效。"}
		for key in c.patch:
			if key in ["surface_id","kind","locked"]:return {"ok":false,"error":"不能通过属性补丁改身份、类型或锁定。"}
		s.merge(c.patch.duplicate(true),true)
	return {"ok":true}
static func validate(p: Dictionary) -> String:
	if p.surfaces.size()>65:return "台地／坡道超过64处安全上限。"
	var ids: Dictionary={}
	for s in p.surfaces:
		if not s is Dictionary or not s.get("surface_id") is String or s.surface_id.is_empty() or ids.has(s.surface_id) or not Asset.numeric(s.get("height")):return "支持面身份或高度无效。"
		ids[s.surface_id]=s
	if not ids.has("ground") or ids.ground.height!=0 or ids.ground.has("kind"):return "必须保留零高度 ground。"
	# Validate every shape before traversing dependencies or inspecting sibling geometry.
	for s in p.surfaces:
		if not s.has("kind"):continue
		if s.kind not in ["terrace","ramp"]:return "未知地形类型。"
		var required: Array=TERRACE_FIELDS if s.kind=="terrace" else RAMP_FIELDS
		for key in required:
			if not s.has(key):return "地形缺少字段："+key
		if s.kind=="terrace":
			if not s.parent_surface_id is String or not ids.has(s.parent_surface_id) or ids[s.parent_surface_id].get("kind")=="ramp":return "台地父面不存在或为坡道。"
			if not Asset.polygon_ok(s.outline) or s.outline.size()>128:return "台地轮廓无效。"
			if not s.edge_styles is Array or not s.edge_widths is Array or s.edge_styles.size()!=s.outline.size() or s.edge_widths.size()!=s.outline.size():return "每条边需要合法样式与展开宽度。"
			for i in range(s.outline.size()):
				if s.edge_styles[i] not in ["none","slope","bank","cliff"] or not Asset.numeric(s.edge_widths[i]):return "地形边参数无效。"
			if s.has("edge_gradients"):
				if not s.edge_gradients is Array or s.edge_gradients.size()!=s.outline.size():return "逐边渐变数量不匹配。"
				for strength in s.edge_gradients:
					if not Asset.numeric(strength) or float(strength)<0 or float(strength)>1:return "坡脚渐变须在0—1。"
			if s.has("edge_directions"):
				if not s.edge_directions is Array or s.edge_directions.size()!=s.outline.size():return "逐边纹理方向数量不匹配。"
				for direction in s.edge_directions:
					if not Asset.numeric(direction) or absf(float(direction))>60:return "纹理方向须在-60至60度。"
		else:
			if not s.from_surface_id is String or not s.to_surface_id is String or not ids.has(s.from_surface_id) or not ids.has(s.to_surface_id) or ids[s.from_surface_id].get("kind")=="ramp" or ids[s.to_surface_id].get("kind")=="ramp":return "坡道端点面必须是已存在的平面。"
			if not Asset.pair(s.start) or not Asset.pair(s.end) or not Asset.numeric(s.width):return "坡道尺寸或坐标无效。"
	for s in p.surfaces:
		if s.surface_id=="ground":continue
		if not s.has("kind"):
			if enabled(p):return "W1 高面请在独立项目保留；不能混入 W4 台地图。"
			if p.surfaces.size()>2 or not Asset.polygon_ok(s.get("outline")) or s.get("parent_surface_id","ground")!="ground" or absf(float(s.height))>10000:return "W1 高面原型无效。"
			continue
		var fields: Array=TERRACE_FIELDS if s.kind=="terrace" else RAMP_FIELDS
		if s.kind not in ["terrace","ramp"]:return "未知地形类型。"
		for field in fields:
			if not s.has(field):return "地形缺少字段："+field
		for field in s:
			if field not in fields and not (s.kind=="terrace" and field in ["edge_directions","edge_gradients"]):return "未知地形字段："+str(field)
		if not s.locked is bool:return "地形锁定值必须为布尔。"
		if s.kind=="terrace":
			if not ids.has(s.parent_surface_id) or ids[s.parent_surface_id].get("kind")=="ramp":return "台地父面不存在或为坡道。"
			if not Asset.polygon_ok(s.outline) or s.outline.size()>128 or Geometry2D.triangulate_polygon(outline(s)).is_empty():return "台地轮廓自交、退化或不可三角化。"
			var chain:=lineage(p,s.surface_id)
			if chain.size()>3 or chain.has(s.parent_surface_id) and s.parent_surface_id==s.surface_id:return "台地最多嵌套三层。"
			var ancestor: String=s.parent_surface_id;var seen: Array=[s.surface_id]
			while ancestor!="ground":
				if seen.has(ancestor):return "台地支持关系形成循环。"
				seen.append(ancestor);ancestor=ids[ancestor].get("parent_surface_id","ground")
			if float(s.height)<4 or float(s.height)>512:return "台地相对高度须在4—512。"
			if not s.edge_styles is Array or not s.edge_widths is Array or s.edge_styles.size()!=s.outline.size() or s.edge_widths.size()!=s.outline.size():return "每条边必须有样式与坡宽。"
			for i in range(s.outline.size()):
				if s.edge_styles[i] not in ["none","slope","bank","cliff"] or not Asset.numeric(s.edge_widths[i]) or float(s.edge_widths[i])<0 or float(s.edge_widths[i])>256:return "边样式或坡宽无效。"
				if s.edge_styles[i] in ["slope","bank"] and float(s.edge_widths[i])<4:return "土坡／岸坎需要至少4单位展开宽度。"
				if vec(s.outline[i]).distance_to(vec(s.outline[(i+1)%s.outline.size()]))<12:return "台地边过短，须移动轮廓点。"
			for key in ["top_color","edge_color"]:
				if not s[key] is String or not Color.html_is_valid(s[key]):return "地形颜色无效。"
			var ring:=outline(s);var bands:=edge_bands(s)
			for i in range(ring.size()):
				for j in range(ring.size()):
					if j==i or j==(i+1)%ring.size() or j==(i-1+ring.size())%ring.size():continue
					if ring[i].distance_to(Geometry2D.get_closest_point_to_segment(ring[i],ring[j],ring[(j+1)%ring.size()]))<12:return "台地狭口小于12单位，请移动轮廓点。"
				if area(bands[i].polygon)>0.02 and overlaps(bands[i].polygon,ring):return "边坡向内折叠，请减小坡宽或修改凹点。"
			for polygon in coverage(s):
				var parent_poly: PackedVector2Array=outline(ids[s.parent_surface_id]) if s.parent_surface_id!="ground" else PackedVector2Array([Vector2.ZERO,Vector2(p.legacy_document.canvas_size[0],0),vec(p.legacy_document.canvas_size),Vector2(0,p.legacy_document.canvas_size[1])])
				if not enclosed(polygon,parent_poly):return "顶面或边坡完整占地超出父面。"
			for other in p.surfaces:
				if other.surface_id==s.surface_id or other.get("parent_surface_id")!=s.parent_surface_id:continue
				for a in coverage(s):
					for b in coverage(other):
						if overlaps(a,b):return "无关联台地交叠；请分开或明确嵌套。"
		else:
			if s.height!=0 or not ids.has(s.from_surface_id) or not ids.has(s.to_surface_id) or s.from_surface_id==s.to_surface_id:return "坡道须连接两个已存在的不同平面。"
			var a: Dictionary=ids[s.from_surface_id];var b: Dictionary=ids[s.to_surface_id]
			if a.get("kind")=="ramp" or b.get("kind")=="ramp" or (a.get("parent_surface_id")!=s.to_surface_id and b.get("parent_surface_id")!=s.from_surface_id):return "坡道仅支持直接父子面，不支持悬桥或跨层洞穴。"
			if not Asset.pair(s.start) or not Asset.pair(s.end) or not Asset.numeric(s.width) or float(s.width)<12 or float(s.width)>256 or s.style not in ["dirt","stone"]:return "坡道端点、宽度或地表样式无效。"
			var start:=vec(s.start);var end:=vec(s.end);var length:=start.distance_to(end)
			var rise:=absf(absolute_height(p,s.to_surface_id)-absolute_height(p,s.from_surface_id))
			if Asset.pair(p.style_profile.get("height_axis")) and p.style_profile.get("ground_matrix") is Array and p.style_profile.ground_matrix.size()==4:
				var m: Array=p.style_profile.ground_matrix;var axis:=vec(p.style_profile.height_axis);var gradient: Vector2=(end-start)*((absolute_height(p,s.to_surface_id)-absolute_height(p,s.from_surface_id))/maxf(length*length,0.001))
				var det: float=(Vector2(m[0],m[1])+axis*gradient.x).cross(Vector2(m[2],m[3])+axis*gradient.y)
				if absf(det)<0.05 or det*(float(m[0])*float(m[3])-float(m[1])*float(m[2]))<=0:return "坡道在当前视角折叠，无法一致拾取；请调整方向或长度。"
			if length<float(s.width)*2 or rise/length>0.75:return "坡道过短或过陡。"
			var without:=p.duplicate(true);without.surfaces=without.surfaces.filter(func(v):return v.get("kind")!="ramp")
			for pair in [[s.from_surface_id,start],[s.to_surface_id,end]]:
				var pad:=capsule(pair[1]-Vector2(0.05,0),pair[1]+Vector2(0.05,0),float(s.width))
				if not contains(without,pair[0],pad):return "坡道端点完整落脚区未受所选面支撑。"
			var high: Dictionary=b if absolute_height(p,b.surface_id)>absolute_height(p,a.surface_id) else a
			var crossings:=0;var ring:=outline(high)
			for i in range(ring.size()):
				if Geometry2D.segment_intersects_segment(start,end,ring[i],ring[(i+1)%ring.size()])!=null:crossings+=1
			if crossings!=1:return "坡道必须穿过且只穿过一道明确台地边。"
			var own:=outline(s)
			for other in p.surfaces:
				if other.surface_id in [s.surface_id,s.from_surface_id,s.to_surface_id] or other.surface_id in lineage(p,high.surface_id) or other.surface_id=="ground":continue
				if overlaps(own,outline(other)):return "坡道与无关台地或另一坡道相交。"
	return ""
