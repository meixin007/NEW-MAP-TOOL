@tool
extends RefCounted
const Terrain=preload("terrain_geometry.gd")
const Asset = preload("asset_descriptor.gd")
const EntityGeometry = preload("entity_geometry.gd")
const Ribbon = preload("../art_ribbon.gd")
const SurfaceProject = preload("surface_projection.gd")
const Canonical = preload("canonical.gd")
const VERSION := "path.sha256-utf8-distance-milli.v1"
const GEOMETRY_VERSION := "grid1024.socket-spaces.v2" # Identity VERSION remains stable.
const MAX_CANDIDATES := 2000

static func digest(value: Variant) -> String:
	return Canonical.digest(value)
static func candidate_key(recipe_id: String, candidate_id: String) -> String:
	return recipe_id+"/"+candidate_id
static func identity(recipe_id: String, candidate_id: String) -> String:
	return "entity_"+(VERSION+":"+recipe_id+":"+candidate_id).sha256_text().substr(0,32)
static func point_by_id(recipe: Dictionary, id: String) -> Dictionary:
	for point in recipe.control_points:
		if point.point_id==id: return point
	return {}
static func validate(recipe: Dictionary, project: Dictionary) -> String:
	for field in ["recipe_id","kind","path_type","name","control_points","segments","seed","surface_id","style","roles","wall_asset_ref","roadside","source_feature_id"]:
		if not recipe.has(field): return "路径缺少字段："+field
	if not recipe.recipe_id is String or recipe.recipe_id.is_empty() or recipe.kind!="path" or recipe.path_type not in ["road","wall","river"] or not recipe.name is String: return "路径类型或身份无效。"
	if not recipe.control_points is Array or recipe.control_points.size()<2 or recipe.control_points.size()>256 or not recipe.segments is Array or recipe.segments.size()!=recipe.control_points.size()-1: return "路径需要 2—256 个控制点及连续段身份。"
	if not Asset.numeric(recipe.seed) or float(recipe.seed)!=floorf(float(recipe.seed)) or not recipe.roles is Array or recipe.roles.size()>32 or not recipe.roadside is Dictionary: return "路径种子、角色或道旁配方无效。"
	if recipe.style not in ["dirt","stone","water"]: return "未知路径地表样式。"
	var surfaces: Array=project.surfaces.map(func(s):return s.surface_id)
	if recipe.surface_id not in surfaces: return "路径缺少明确支持面。"
	if Terrain.surface(project,recipe.surface_id).get("kind")=="ramp" and recipe.path_type!="road":return "坡道仅连接道路；城墙／河流请选择平面。"
	var ids: Dictionary={}
	for p in recipe.control_points:
		if not p is Dictionary or not p.get("point_id") is String or p.point_id.is_empty() or ids.has(p.point_id) or not Asset.pair(p.get("ground_xy")) or not Asset.numeric(p.get("width")) or float(p.width)<6 or float(p.width)>256: return "控制点身份、位置或宽度无效。"
		if p.ground_xy[0]<0 or p.ground_xy[1]<0 or p.ground_xy[0]>project.legacy_document.canvas_size[0] or p.ground_xy[1]>project.legacy_document.canvas_size[1]: return "路径控制点超出画布。"
		ids[p.point_id]=true
	var segments: Dictionary={}
	for i in range(recipe.segments.size()):
		var s: Variant=recipe.segments[i]
		if not s is Dictionary or not s.get("segment_id") is String or s.segment_id.is_empty() or segments.has(s.segment_id) or s.get("from")!=recipe.control_points[i].point_id or s.get("to")!=recipe.control_points[i+1].point_id: return "路径段身份或引用不连续。"
		segments[s.segment_id]=true
		if Vector2(recipe.control_points[i].ground_xy[0],recipe.control_points[i].ground_xy[1]).distance_to(Vector2(recipe.control_points[i+1].ground_xy[0],recipe.control_points[i+1].ground_xy[1]))<1: return "路径段过短或控制点重复。"
	var roles: Dictionary={}
	var role_points: Dictionary={}
	for role in recipe.roles:
		if not role is Dictionary or not role.get("role_id") is String or roles.has(role.role_id) or not ids.has(role.get("point_id")) or not Asset.pair(role.get("ground_xy")) or not Asset.numeric(role.get("orientation")) or not project.asset_refs.has(role.get("asset_ref")): return "固定角色或接点引用无效。"
		if digest(point_by_id(recipe,role.point_id).ground_xy)!=digest(role.ground_xy): return "控制点已绑定固定角色；请先明确移动角色或脱离，不能让门位漂移。"
		if role_points.has(role.point_id): return "同一控制点不能有两份角色。"
		role_points[role.point_id]=true
		roles[role.role_id]=true
	if not recipe.source_feature_id is String: return "旧河流来源引用必须为文本。"
	if recipe.path_type=="wall" and not project.asset_refs.has(recipe.wall_asset_ref): return "城墙路径需要已固定版本的墙段资产。"
	if not recipe.roadside.is_empty():
		var side: Dictionary=recipe.roadside
		if recipe.path_type!="road" or not project.asset_refs.has(side.get("asset_ref")) or side.get("side") not in ["left","right","both"] or not Asset.numeric(side.get("spacing")) or float(side.spacing)<64 or not Asset.numeric(side.get("offset")) or float(side.offset)<16: return "道旁资产、侧向、间距或退距无效。"
	return ""

static func diagnostic(recipe: Dictionary, segment_id: String, code: String, message: String) -> Dictionary:
	return {"recipe_id":recipe.recipe_id,"segment_id":segment_id,"code":code,"message":message}
static func entity(recipe: Dictionary, candidate_id: String, segment_id: String, xy: Vector2, kind: String, role: String) -> Dictionary:
	return {"entity_id":identity(recipe.recipe_id,candidate_id),"kind":kind,"ground_xy":[snappedf(xy.x,1.0/1024),snappedf(xy.y,1.0/1024)],"surface_id":recipe.surface_id,"local_height":0.0,"label":recipe.name+" · "+role,"management":"generated","recipe_id":recipe.recipe_id,"candidate_id":candidate_id,"segment_id":segment_id,"role":role}
static func asset_entity(recipe: Dictionary, candidate_id: String, segment_id: String, xy: Vector2, ref: String, angle: float, role: String) -> Dictionary:
	var e:=entity(recipe,candidate_id,segment_id,xy,"asset",role)
	e.merge({"asset_ref":ref,"orientation":angle,"scale":1.0})
	return e
static func strip(a: Vector2, b: Vector2, start_width: float, end_width: float) -> Array:
	var angle: float=(b-a).angle()
	var normal:=Vector2.RIGHT.rotated(angle+PI*0.5)
	var polygon: Array=[[a.x+normal.x*start_width*0.5,a.y+normal.y*start_width*0.5],[b.x+normal.x*end_width*0.5,b.y+normal.y*end_width*0.5]]
	for j in range(1,9):
		var p:=b+Vector2.RIGHT.rotated(angle+PI*0.5-j*PI/8)*end_width*0.5
		polygon.append([p.x,p.y])
	var start:=a-normal*start_width*0.5
	polygon.append([start.x,start.y])
	for j in range(1,8):
		var p:=a+Vector2.RIGHT.rotated(angle-PI*0.5-j*PI/8)*start_width*0.5
		polygon.append([p.x,p.y])
	return polygon.map(func(p):return [snappedf(float(p[0]),1.0/1024),snappedf(float(p[1]),1.0/1024)])
static func _role_entity(recipe: Dictionary, role: Dictionary) -> Dictionary:
	return asset_entity(recipe,"role/"+role.role_id,"",Vector2(role.ground_xy[0],role.ground_xy[1]),role.asset_ref,float(role.orientation),"role")
static func _role_for_point(recipe: Dictionary, point_id: String) -> Dictionary:
	for role in recipe.roles:
		if role.point_id==point_id: return _role_entity(recipe,role)
	return {}
static func _connection(project: Dictionary, e: Dictionary, angle: float) -> Dictionary:
	for socket in EntityGeometry.sockets(project,e):
		if socket.role=="wall" and absf(wrapf(float(socket.direction_projected)-angle,-180.0,180.0))<3: return socket
	return {}
static func _segment(recipe: Dictionary, project: Dictionary, index: int) -> Dictionary:
	var segment: Dictionary=recipe.segments[index]
	var a: Dictionary=recipe.control_points[index]
	var b: Dictionary=recipe.control_points[index+1]
	var start:=Vector2(a.ground_xy[0],a.ground_xy[1])
	var end:=Vector2(b.ground_xy[0],b.ground_xy[1])
	var direction: Vector2=(end-start).normalized()
	var screen_direction:=SurfaceProject.project_point(project,end)-SurfaceProject.project_point(project,start)
	var angle:=fposmod(rad_to_deg(screen_direction.angle()),360.0)
	var entities: Array=[]
	var diagnostics: Array=[]
	if recipe.path_type in ["road","river"]:
		var ribbon:=entity(recipe,"ribbon/"+segment.segment_id,segment.segment_id,(start+end)*0.5,"ribbon",recipe.path_type)
		ribbon.style="water" if recipe.path_type=="river" else recipe.style
		ribbon.max_width=maxf(float(a.width),float(b.width))
		ribbon.polygons=[]
		if recipe.path_type=="river":
			var lo:=maxi(0,index-1)
			var hi:=mini(recipe.control_points.size()-1,index+2)
			var points: Array=[]
			var widths: Array=[]
			for i in range(lo,hi+1): points.append(recipe.control_points[i].ground_xy);widths.append(recipe.control_points[i].width)
			var samples: Array=Ribbon.sample(points,widths)
			for i in range((index-lo)*8,(index-lo)*8+8): ribbon.polygons.append(strip(samples[i].position,samples[i+1].position,float(samples[i].width),float(samples[i+1].width)))
			ribbon.source_algorithm="legacy_art_ribbon.sample"
		else: ribbon.polygons=[strip(start,end,float(a.width),float(b.width))]
		entities.append(ribbon)
	else:
		var source: Dictionary=project.asset_refs[recipe.wall_asset_ref]
		var allowed:=Asset.orientation(source,angle)
		if not allowed.ok: return {"entities":[],"diagnostics":[diagnostic(recipe,segment.segment_id,"missing_orientation",allowed.error)]}
		var piece:=asset_entity(recipe,"temporary",segment.segment_id,Vector2.ZERO,recipe.wall_asset_ref,angle,"wall")
		var left:=_connection(project,piece,fposmod(angle+180,360))
		var right:=_connection(project,piece,angle)
		if left.is_empty() or right.is_empty(): return {"entities":[],"diagnostics":[diagnostic(recipe,segment.segment_id,"missing_wall_socket","墙段缺少朝向相容的 wall 接点。可手动摆放。 ")]}
		var start_role:=_role_for_point(recipe,a.point_id)
		var end_role:=_role_for_point(recipe,b.point_id)
		if not start_role.is_empty():
			var socket:=_connection(project,start_role,angle)
			if socket.is_empty(): return {"entities":[],"diagnostics":[diagnostic(recipe,segment.segment_id,"missing_role_socket","起点角色缺少对应接点。 ")]}
			start=Vector2(socket.ground_xy[0],socket.ground_xy[1])
		if not end_role.is_empty():
			var socket:=_connection(project,end_role,fposmod(angle+180,360))
			if socket.is_empty(): return {"entities":[],"diagnostics":[diagnostic(recipe,segment.segment_id,"missing_role_socket","终点角色缺少对应接点。 ")]}
			end=Vector2(socket.ground_xy[0],socket.ground_xy[1])
		var offset_a:=Vector2(left.ground_xy[0],left.ground_xy[1])
		var offset_b:=Vector2(right.ground_xy[0],right.ground_xy[1])
		var span: float=(offset_b-offset_a).dot(direction)
		var available: float=(end-start).dot(direction)
		if span<1 or absf((offset_b-offset_a).cross(direction))>0.01: return {"entities":[],"diagnostics":[diagnostic(recipe,segment.segment_id,"bad_wall_socket","墙段接点与路径不共线。 ")]}
		var count:=maxi(0,int(floor((available+0.01)/span)))
		if count>MAX_CANDIDATES: return {"ok":false,"error":"路径候选超过安全预算，请缩短路径。"}
		for i in range(count):
			var distance:=i*span
			var xy:=start+direction*distance-offset_a
			entities.append(asset_entity(recipe,"wall/"+segment.segment_id+"/"+str(roundi(distance*1000)),segment.segment_id,xy,recipe.wall_asset_ref,angle,"wall"))
		var gap:=available-count*span
		if available<0 or gap>0.05: diagnostics.append(diagnostic(recipe,segment.segment_id,"short_gap","剩余 %.2f map_unit 无合法短墙；未拉伸 PNG，可加短段或手动接点吸附。"%maxf(gap,0)))
	if recipe.path_type=="road" and not recipe.roadside.is_empty():
		var side: Dictionary=recipe.roadside
		var length:=start.distance_to(end)
		var count:=mini(128,int(length/float(side.spacing)))
		var normal:=Vector2(-direction.y,direction.x)
		for sign_value in ([1.0,-1.0] if side.side=="both" else [1.0 if side.side=="left" else -1.0]):
			for i in range(count):
				var token: String=recipe.recipe_id+":"+segment.segment_id+":"+str(int(recipe.seed))+":"+str(i)
				var jitter: float=float(token.sha256_text().substr(0,8).hex_to_int()%10001)/10000.0-0.5
				var distance: float=(i+0.5)*float(side.spacing)+jitter*float(side.spacing)*0.1
				var xy:=start+direction*distance+normal*float(sign_value)*float(side.offset)
				var facing:=SurfaceProject.projected_direction(project,-normal*float(sign_value),recipe.surface_id,xy)
				var desired:=fposmod(rad_to_deg(facing.angle())-90.0,360.0)
				var allowed:=Asset.orientation(project.asset_refs[side.asset_ref],desired)
				if not allowed.ok:diagnostics.append(diagnostic(recipe,segment.segment_id,"missing_front_variant",allowed.error));continue
				var building:=asset_entity(recipe,"roadside/"+segment.segment_id+"/"+str(int(sign_value))+"/cell_"+str(i),segment.segment_id,xy,side.asset_ref,desired,"roadside")
				for socket in EntityGeometry.sockets(project,building):
					if socket.role in ["road","entrance"]:
						building.entrance_corridor=strip(Vector2(socket.ground_xy[0],socket.ground_xy[1]),start+direction*distance,16.0,16.0)
						break
				entities.append(building)
	return {"ok":true,"entities":entities,"diagnostics":diagnostics}

static func build(recipe: Dictionary, project: Dictionary, previous: Dictionary) -> Dictionary:
	var entities: Array=[]
	var diagnostics: Array=[]
	var cache: Dictionary={}
	var rebuilt:=0
	var reused:=0
	for role in recipe.roles: entities.append(_role_entity(recipe,role))
	for index in range(recipe.segments.size()):
		var segment: Dictionary=recipe.segments[index]
		var params:=recipe.duplicate(true)
		params.erase("control_points");params.erase("segments")
		params.erase("topology_mapping")
		params.roles=recipe.roles.filter(func(r):return r.point_id in [recipe.control_points[index].point_id,recipe.control_points[index+1].point_id])
		var points: Array=recipe.control_points.slice(maxi(0,index-1) if recipe.path_type=="river" else index,mini(recipe.control_points.size(),index+3) if recipe.path_type=="river" else index+2)
		var asset_inputs: Dictionary={}
		var references: Array=[recipe.wall_asset_ref,recipe.roadside.get("asset_ref","")]
		for role in recipe.roles: references.append(role.asset_ref)
		for ref in references:
			if not project.asset_refs.has(ref): continue
			asset_inputs[ref]=project.asset_refs[ref]
			var a: Dictionary=project.asset_refs[ref]
			for variant in a.orientation_variants.values():
				var key: String=variant if variant.contains("@") else variant+"@"+a.asset_version
				if project.asset_refs.has(key): asset_inputs[key]=project.asset_refs[key]
		var signature:=digest([VERSION,GEOMETRY_VERSION,params,points,segment,asset_inputs,project.style_profile.ground_matrix,project.style_profile.height_axis,project.surfaces])
		var result: Dictionary
		if previous.has(segment.segment_id) and previous[segment.segment_id].get("hash")==signature:
			result=previous[segment.segment_id].duplicate(true);reused+=1
		else:
			result=_segment(recipe,project,index)
			if result.get("ok",true)==false: return result
			result.hash=signature;rebuilt+=1
		cache[segment.segment_id]=result
		entities.append_array(result.entities);diagnostics.append_array(result.diagnostics)
		if entities.size()>MAX_CANDIDATES: return {"ok":false,"error":"配方候选超过 2000 件；正式项目未修改。"}
	return {"ok":true,"entities":entities,"diagnostics":diagnostics,"cache":cache,"rebuilt":rebuilt,"reused":reused}
