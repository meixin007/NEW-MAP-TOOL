@tool
extends RefCounted
const E=preload("entity_geometry.gd")
const P=preload("surface_projection.gd")
static func hex_round(point: Vector2,size: float) -> Vector2:
	var q: float=(sqrt(3.0)/3*point.x-point.y/3)/size;var r: float=(2.0/3*point.y)/size;var x:=roundf(q);var z:=roundf(r);var y:=roundf(-q-r)
	var dx:=absf(x-q);var dy:=absf(y+q+r);var dz:=absf(z-r)
	if dx>dy and dx>dz:x=-y-z
	elif dz>dy:z=-x-y
	return Vector2(sqrt(3.0)*(x+z/2),1.5*z)*size
static func drag(p: Dictionary,e: Dictionary,point: Vector2,zoom: float) -> Dictionary:
	var moved: Dictionary=e.duplicate(true);moved.ground_xy=[point.x,point.y];var best:=16.0;var chosen:=point;var reason: String="none"
	# Compatible explicit sockets have priority; all distances are screen pixels.
	for source in E.sockets(p,moved):
		var source_point:=P.project_point(p,Vector2(source.ground_xy[0],source.ground_xy[1]),moved.surface_id,moved.local_height)
		for target in p.materialized_snapshot.entities:
			if target.entity_id==e.entity_id or target.surface_id!=e.surface_id or target.get("hidden",false):continue
			for socket in E.sockets(p,target):
				if socket.role!=source.role or absf(wrapf(float(socket.direction_deg)-float(source.direction_deg)-180,-180,180))>3:continue
				var end:=P.project_point(p,Vector2(socket.ground_xy[0],socket.ground_xy[1]),target.surface_id,target.local_height);var distance:=end.distance_to(source_point)*zoom
				if distance<best:best=distance;chosen=point+Vector2(socket.ground_xy[0]-source.ground_xy[0],socket.ground_xy[1]-source.ground_xy[1]);reason="socket"
	if reason=="socket":return {"ground_xy":[chosen.x,chosen.y],"reason":reason}
	if p.style_profile.get("grid_snap",false):
		var size: float=p.style_profile.get("grid_size",32)
		chosen=hex_round(point,size) if p.style_profile.get("grid_kind","square")=="hex" else point.snapped(Vector2.ONE*size)
		return {"ground_xy":[chosen.x,chosen.y],"reason":"grid"}
	if p.style_profile.get("edge_snap",false):
		var screen:=P.project_point(p,point,e.surface_id,e.local_height);best=8
		for target in p.materialized_snapshot.entities:
			if target.entity_id==e.entity_id or target.surface_id!=e.surface_id or target.kind not in ["asset","compound"] or target.get("hidden",false):continue
			var polygon:=E.footprint(p,target)
			for i in range(polygon.size()):
				var a:=P.project_point(p,polygon[i],e.surface_id,e.local_height);var b:=P.project_point(p,polygon[(i+1)%polygon.size()],e.surface_id,e.local_height);var q:=Geometry2D.get_closest_point_to_segment(screen,a,b);var distance:=q.distance_to(screen)*zoom
				if distance<best:best=distance;chosen=P.ground_point(p,q,e.surface_id,e.local_height);reason="edge"
	return {"ground_xy":[chosen.x,chosen.y],"reason":reason}
