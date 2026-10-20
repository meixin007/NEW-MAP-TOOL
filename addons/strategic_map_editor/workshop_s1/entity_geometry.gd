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
		if entrance.is_empty():return []
		var g:=Vector2(entrance.ground_xy[0],entrance.ground_xy[1])
		var ground_direction:=Vector2.from_angle(deg_to_rad(float(entrance.direction_deg)))
		var projected:=SurfaceProject.projected_direction(project,ground_direction,entity.surface_id,g)
		entrance.direction_ground=rad_to_deg(ground_direction.angle())
		entrance.direction_projected=rad_to_deg(projected.angle())
		entrance.direction_deg=entrance.direction_projected # Legacy alias is projected.
		return [entrance]
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
		var angle: float=float(socket.direction_deg)+rad_to_deg(float(info.rotation))
		var ground_direction:=SurfaceProject.ground_direction(project,Vector2.from_angle(deg_to_rad(angle)),surface,p)
		result.append({"socket_id":socket.socket_id,"role":socket.role,"ground_xy":[p.x,p.y],"direction_deg":angle,"direction_projected":angle,"direction_ground":rad_to_deg(ground_direction.angle())})
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
	# Compare effective socket heights after translating, so sloping supports do
	# not reject otherwise valid connections merely because origins differ.
	var translated:=Vector2(a.ground_xy[0],a.ground_xy[1])+delta
	var target_point:=Vector2(b.ground_xy[0],b.ground_xy[1])
	if absf(SurfaceProject.height(project,source.surface_id,source.local_height,translated)-SurfaceProject.height(project,target.surface_id,target.local_height,target_point))>0.01:
		return {"ok":false,"error":"接点高度不相容；请先明确调整支持面或局部高度。"}
	var moved:=source.duplicate(true)
	moved.ground_xy=[float(source.ground_xy[0])+delta.x,float(source.ground_xy[1])+delta.y]
	for socket in sockets(project,moved):
		if socket.socket_id!=source_socket:continue
		var actual:=SurfaceProject.project_point(project,Vector2(socket.ground_xy[0],socket.ground_xy[1]),source.surface_id,source.local_height)
		var expected:=SurfaceProject.project_point(project,target_point,target.surface_id,target.local_height)
		if actual.distance_to(expected)>0.01:return {"ok":false,"error":"移动后的坡道接点不再重合；未吸附。"}
	return {"ok":true,"ground_xy":[float(source.ground_xy[0])+delta.x,float(source.ground_xy[1])+delta.y]}
