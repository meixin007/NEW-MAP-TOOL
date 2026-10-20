@tool
extends RefCounted
const T=preload("terrain_geometry.gd")
const P=preload("surface_projection.gd")
const E=preload("entity_geometry.gd")
static func candidates(p: Dictionary,screen: Vector2,template: Dictionary) -> Array:
	var result: Array=[]
	for s in p.surfaces:
		var ground:=P.ground_point(p,screen,s.surface_id,float(template.get("local_height",0)))
		if not ground.is_finite():continue
		var e:=template.duplicate(true);e.ground_xy=[ground.x,ground.y];e.surface_id=s.surface_id
		var footprint:=E.footprint(p,e) if e.get("kind")=="asset" else T.capsule(ground-Vector2(0.1,0),ground+Vector2(0.1,0),1)
		if T.contains(p,s.surface_id,footprint):result.append({"surface_id":s.surface_id,"ground_xy":e.ground_xy,"height":P.height(p,s.surface_id,0,ground)})
	return result
