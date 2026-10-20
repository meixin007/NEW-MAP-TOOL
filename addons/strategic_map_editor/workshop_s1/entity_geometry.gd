@tool
extends RefCounted
const Compound=preload("compound_model.gd")
const Asset = preload("asset_descriptor.gd")
const SurfaceProject = preload("surface_projection.gd")

static func resolved(project: Dictionary, entity: Dictionary) -> Dictionary:
	if entity.get("kind")!="asset" or not project.asset_refs.has(entity.get("asset_ref")): return {}
	var a: Dictionary=project.asset_refs[entity.asset_ref]
	var direction:=Asset.orientation(a,float(entity.get("orientation",0.0)))
	if not direction.ok: return {}
	var ref: String=direction.asset_id if direction.asset_id.contains("@") else direction.asset_id+"@"+a.asset_version
	if not project.asset_refs.has(ref): return {}
	return {"descriptor":project.asset_refs[ref],"rotation":deg_to_rad(float(direction.rotation)),"ref":ref}

static func footprint(project: Dictionary, entity: Dictionary) -> PackedVector2Array:
	if entity.get("kind")=="compound":return Compound.footprint(entity)
	var info:=resolved(project,entity)
	if info.is_empty(): return PackedVector2Array()
	var result:=PackedVector2Array()
	var origin:=Vector2(entity.ground_xy[0],entity.ground_xy[1])
	for point in info.descriptor.ground_footprint: result.append(origin+Vector2(point[0],point[1]).rotated(float(info.rotation))*float(entity.get("scale",1.0)))
	return result

static func sockets(project: Dictionary, entity: Dictionary) -> Array:
	if entity.get("kind")=="compound":
		var entrance:=Compound.entrance(entity)
		return [] if entrance.is_empty() else [entrance]
	var info:=resolved(project,entity)
	if info.is_empty(): return []
	var a: Dictionary=info.descriptor
	var origin:=Vector2(entity.ground_xy[0],entity.ground_xy[1])
	var surface: String=str(entity.get("surface_id","ground"))
	var local_height: float=float(entity.get("local_height",0.0))
	var screen:=SurfaceProject.project_point(project,origin,surface,local_height)
	var unit: float=float(a.nominal_size_units[0])/float(a.region_px[2])*float(entity.get("scale",1.0))
	var result: Array=[]
	for socket in a.sockets:
		var pixel:=Vector2(socket.position_px[0],socket.position_px[1])-Vector2(a.anchor_px[0],a.anchor_px[1])
		var p:=SurfaceProject.ground_point(project,screen+pixel.rotated(float(info.rotation))*unit,surface,local_height)
		result.append({"socket_id":socket.socket_id,"role":socket.role,"ground_xy":[p.x,p.y],"direction_deg":float(socket.direction_deg)+rad_to_deg(float(info.rotation))})
	return result

static func area(points: PackedVector2Array) -> float:
	var total:=0.0
	for i in range(points.size()): total+=points[i].cross(points[(i+1)%points.size()])
	return absf(total)*0.5

static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size()<3 or b.size()<3: return false
	for polygon in Geometry2D.intersect_polygons(a,b):
		if area(polygon)>0.01: return true
	return false

static func snap(project: Dictionary, source: Dictionary, source_socket: String, target: Dictionary, target_socket: String) -> Dictionary:
	var a: Dictionary={}
	var b: Dictionary={}
	for s in sockets(project,source):
		if s.socket_id==source_socket: a=s
	for s in sockets(project,target):
		if s.socket_id==target_socket: b=s
	if a.is_empty() or b.is_empty(): return {"ok":false,"error":"接点不存在。"}
	if a.role!=b.role or absf(wrapf(float(a.direction_deg)-float(b.direction_deg)-180.0,-180.0,180.0))>3.0: return {"ok":false,"error":"接点角色或朝向不相容。"}
	if source.surface_id!=target.surface_id: return {"ok":false,"error":"不能跨不明支持面吸附。"}
	var delta:=Vector2(b.ground_xy[0],b.ground_xy[1])-Vector2(a.ground_xy[0],a.ground_xy[1])
	return {"ok":true,"ground_xy":[float(source.ground_xy[0])+delta.x,float(source.ground_xy[1])+delta.y]}
