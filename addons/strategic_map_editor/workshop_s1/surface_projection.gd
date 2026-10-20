@tool
extends RefCounted
## One projection for draw, picking, snapping and later export.
const Terrain=preload("terrain_geometry.gd")
## Linear part at ground (including a ramp's height gradient). Directions never
## include translation. At clamped ramp ends use the adjacent flat tangent.
static func tangent(project: Dictionary, surface_id: String, ground: Vector2) -> Transform2D:
	var m: Array=project.style_profile.ground_matrix
	var axis: Array=project.style_profile.height_axis
	var gradient:=Vector2.ZERO
	var s:=Terrain.surface(project,surface_id)
	if s.get("kind")=="ramp":
		var a:=Terrain.vec(s.start)
		var d:=Terrain.vec(s.end)-a
		var t: float=(ground-a).dot(d)/d.length_squared()
		if t>=0.0 and t<=1.0:
			gradient=d*((Terrain.absolute_height(project,s.to_surface_id)-Terrain.absolute_height(project,s.from_surface_id))/d.length_squared())
	var v:=Vector2(axis[0],axis[1])
	return Transform2D(Vector2(m[0],m[1])+v*gradient.x,Vector2(m[2],m[3])+v*gradient.y,Vector2.ZERO)

static func projected_direction(project: Dictionary, direction: Vector2, surface_id: String="ground", ground: Vector2=Vector2.ZERO) -> Vector2:
	return (tangent(project,surface_id,ground)*direction).normalized()

static func ground_direction(project: Dictionary, direction: Vector2, surface_id: String="ground", ground: Vector2=Vector2.ZERO) -> Vector2:
	var basis:=tangent(project,surface_id,ground)
	if absf(basis.determinant())<0.01:return Vector2.ZERO
	return (basis.affine_inverse()*direction).normalized()

static func height(project: Dictionary, surface_id: String, local_height: float = 0.0, ground: Vector2=Vector2.ZERO) -> float:
	return Terrain.absolute_height(project,surface_id,ground)+local_height

static func project_point(project: Dictionary, ground: Vector2, surface_id: String = "ground", local_height: float = 0.0) -> Vector2:
	var m: Array = project.style_profile.ground_matrix
	var axis: Array = project.style_profile.height_axis
	return Vector2(m[0]*ground.x+m[2]*ground.y,m[1]*ground.x+m[3]*ground.y)+Vector2(axis[0],axis[1])*height(project,surface_id,local_height,ground)

static func ground_point(project: Dictionary, point: Vector2, surface_id: String = "ground", local_height: float = 0.0) -> Vector2:
	var m: Array = project.style_profile.ground_matrix
	var axis: Array = project.style_profile.height_axis
	var s:=Terrain.surface(project,surface_id)
	if s.get("kind")=="ramp":
		var a:=Terrain.vec(s.start);var d:=Terrain.vec(s.end)-a
		var h0:=Terrain.absolute_height(project,s.from_surface_id);var h1:=Terrain.absolute_height(project,s.to_surface_id)
		var gradient: Vector2=d*((h1-h0)/d.length_squared());var v:=Vector2(axis[0],axis[1])
		var transform:=Transform2D(Vector2(m[0],m[1])+v*gradient.x,Vector2(m[2],m[3])+v*gradient.y,v*(h0-gradient.dot(a)+local_height))
		if absf(transform.determinant())<0.01:return Vector2(INF,INF)
		var g: Vector2=transform.affine_inverse()*point;var t: float=(g-a).dot(d)/d.length_squared()
		if t>=0 and t<=1:return g
		var flat:=Transform2D(Vector2(m[0],m[1]),Vector2(m[2],m[3]),v*((h0 if t<0 else h1)+local_height))
		return flat.affine_inverse()*point
	var p := point-Vector2(axis[0],axis[1])*height(project,surface_id,local_height)
	var det: float = m[0]*m[3]-m[1]*m[2]
	return Vector2((m[3]*p.x-m[2]*p.y)/det,(-m[1]*p.x+m[0]*p.y)/det)
