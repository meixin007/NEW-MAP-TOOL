@tool
extends RefCounted
const REQUIRED := ["asset_id","asset_version","style_id","texture_ref","texture_sha256","texture_size_px","region_px","anchor_px","nominal_size_units","ground_footprint","paint_envelope","sockets","orientation_variants","shadow_mode","render_parts","state_variants","source_notice","label","tags","category"]

static func numeric(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))
static func pair(v: Variant) -> bool:
	return v is Array and v.size()==2 and numeric(v[0]) and numeric(v[1])
static func packed(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points: result.append(Vector2(p[0],p[1]))
	return result
static func polygon_ok(points: Variant) -> bool:
	if not points is Array or points.size()<3 or points.size()>128: return false
	for p in points:
		if not pair(p) or absf(float(p[0]))>100000 or absf(float(p[1]))>100000: return false
	var ring := packed(points)
	for i in range(ring.size()):
		if ring[i].is_equal_approx(ring[(i+1)%ring.size()]): return false
		for j in range(i+2,ring.size()):
			if i==0 and j==ring.size()-1: continue
			if Geometry2D.segment_intersects_segment(ring[i],ring[(i+1)%ring.size()],ring[j],ring[(j+1)%ring.size()]) != null: return false
	return not Geometry2D.triangulate_polygon(ring).is_empty()
static func safe_relative(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or path.contains("\\"): return false
	for part in path.split("/"):
		if part in ["", ".", ".."]: return false
	return true
static func key(a: Dictionary) -> String:
	return str(a.asset_id)+"@"+str(a.asset_version)
static func validate(a: Dictionary) -> String:
	for field in REQUIRED:
		if not a.has(field): return "资产缺少字段："+field
	for field in ["asset_id","asset_version","style_id","texture_ref","texture_sha256","source_notice","label"]:
		if not a[field] is String or a[field].is_empty(): return "资产文本字段无效："+field
	if a.asset_id.contains("@") or a.asset_version.contains("@"): return "资产身份含保留分隔符。"
	if not safe_relative(a.texture_ref) or a.texture_ref != "assets/"+a.texture_sha256+".png": return "素材必须固定到内容寻址的安全相对 PNG。"
	if a.texture_sha256.length()!=64 or not a.texture_sha256.is_valid_hex_number(false): return "素材 hash 无效。"
	if not pair(a.texture_size_px) or a.texture_size_px[0]<32 or a.texture_size_px[1]<32 or a.texture_size_px[0]>4096 or a.texture_size_px[1]>4096: return "素材尺寸超界。"
	if not a.region_px is Array or a.region_px.size()!=4: return "裁切区域无效。"
	for n in a.region_px:
		if not numeric(n) or float(n)!=floorf(float(n)): return "裁切使用整数像素。"
	var r: Array = a.region_px
	if r[0]<0 or r[1]<0 or r[2]<1 or r[3]<1 or r[0]+r[2]>a.texture_size_px[0] or r[1]+r[3]>a.texture_size_px[1]: return "裁切超出图像。"
	if not pair(a.anchor_px) or a.anchor_px[0]<0 or a.anchor_px[1]<0 or a.anchor_px[0]>r[2] or a.anchor_px[1]>r[3]: return "锚点超出裁切图像。"
	if not pair(a.nominal_size_units) or a.nominal_size_units[0]<1 or a.nominal_size_units[1]<1 or a.nominal_size_units[0]>4096 or a.nominal_size_units[1]>4096: return "标称尺寸无效。"
	if not polygon_ok(a.ground_footprint) or not polygon_ok(a.paint_envelope): return "ground/paint 必须是简单有效多边形。"
	# Conservative full-region envelope includes baked shadows; never shrink culling
	# to a footprint or root merely to make a collision test pass.
	var paint := packed(a.paint_envelope)
	for corner in [Vector2.ZERO,Vector2(r[2],0),Vector2(r[2],r[3]),Vector2(0,r[3])]:
		if not Geometry2D.is_point_in_polygon(corner,paint): return "paint 包络必须覆盖完整裁切范围及阴影。"
	if not a.sockets is Array or not a.orientation_variants is Dictionary or not a.render_parts is Array or not a.state_variants is Dictionary or not a.tags is Array: return "资产关系字段无效。"
	for tag in a.tags:
		if not tag is String: return "资产标签必须为文本。"
	if a.sockets.size()>64 or a.render_parts.size()>32: return "资产接点或拆片过多。"
	var ids := {}
	for socket in a.sockets:
		if not socket is Dictionary or not socket.get("socket_id") is String or ids.has(socket.socket_id) or not pair(socket.get("position_px")) or not numeric(socket.get("direction_deg")) or not socket.get("role") is String: return "接点无效或重名。"
		if socket.position_px[0]<0 or socket.position_px[1]<0 or socket.position_px[0]>r[2] or socket.position_px[1]>r[3]: return "接点超出裁切图像。"
		ids[socket.socket_id] = true
	for angle in a.orientation_variants:
		if not str(angle).is_valid_float() or not a.orientation_variants[angle] is String: return "方向变体表无效。"
	if a.orientation_variants.is_empty(): return "至少登记一个已制作方向。"
	if a.shadow_mode not in ["baked","separate","none"] or a.category not in ["object","wall","gate","tower","building","tree","ground"]: return "阴影或资产类别无效。"
	for part in a.render_parts:
		if not part is Dictionary or not part.get("region_px") is Array or part.region_px.size()!=4 or not numeric(part.get("depth_offset")): return "拆片描述无效。"
		for v in part.region_px:
			if not numeric(v): return "拆片坐标无效。"
		if part.region_px[0]<0 or part.region_px[1]<0 or part.region_px[2]<=0 or part.region_px[3]<=0 or part.region_px[0]+part.region_px[2]>r[2] or part.region_px[1]+part.region_px[3]>r[3]: return "拆片超出裁切范围。"
	return ""

static func orientation(a: Dictionary, angle: float) -> Dictionary:
	var normalized := fposmod(angle,360.0)
	if a.category == "ground": return {"ok":true,"asset_id":a.asset_id,"rotation":normalized}
	for allowed in a.orientation_variants:
		if absf(wrapf(normalized-float(allowed),-180.0,180.0))<0.01: return {"ok":true,"asset_id":a.orientation_variants[allowed],"rotation":0.0}
	return {"ok":false,"error":"缺少 %.1f° 方向变体；不会旋转立面 PNG。"%normalized}

static func with_region(a: Dictionary, region: Array, mode: String="preserve_pixels") -> Dictionary:
	if region.size()!=4: return {"ok":false,"error":"裁切区域须四个像素值。"}
	if mode not in ["preserve_pixels","rescale"]:return {"ok":false,"error":"未知裁切比例模式。"}
	var next := a.duplicate(true)
	if mode=="preserve_pixels":
		var unit: float=float(a.nominal_size_units[0])/float(a.region_px[2])
		next.nominal_size_units=[float(region[2])*unit,float(region[3])*unit]
	# Ground footprint is an independent authored support contract in both modes.
	# Adopting any new version still runs the full protection/support transaction.
	var delta := Vector2(float(region[0])-float(a.region_px[0]),float(region[1])-float(a.region_px[1]))
	next.region_px = region.duplicate()
	next.anchor_px = [float(a.anchor_px[0])-delta.x,float(a.anchor_px[1])-delta.y]
	for socket in next.sockets:
		socket.position_px = [float(socket.position_px[0])-delta.x,float(socket.position_px[1])-delta.y]
	next.paint_envelope = [[0,0],[region[2],0],[region[2],region[3]],[0,region[3]]]
	next.render_parts = []
	var issue := validate(next)
	return {"ok":issue.is_empty(),"error":issue,"descriptor":next}

static func validate_draft(a: Dictionary) -> String:
	if not a.get("ground_footprint") is Array or a.ground_footprint.size()>128: return "恢复中的占地草稿无效。"
	for point in a.ground_footprint:
		if not pair(point) or absf(float(point[0]))>100000 or absf(float(point[1]))>100000: return "恢复中的占地点无效。"
	# An unfinished polygon may have fewer than three points or self-intersections.
	# Keep it as a draft without promoting it to a valid committed asset.
	var candidate:=a.duplicate(true)
	candidate.ground_footprint=[[-1,-1],[1,-1],[1,1],[-1,1]]
	return validate(candidate)
