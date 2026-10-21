@tool
extends RefCounted
const Geometry = preload("entity_geometry.gd")
const Asset = preload("asset_descriptor.gd")
const Paths = preload("path_generator.gd")

static func _key(e: Dictionary) -> String:
	return Paths.candidate_key(str(e.get("recipe_id","")),str(e.get("candidate_id","")))
static func _ribbon_overlap(ribbon: Dictionary, polygon: PackedVector2Array) -> bool:
	for part in ribbon.get("polygons",[]):
		if Geometry.overlaps(Asset.packed(part),polygon): return true
	return false
static func _blocks(project: Dictionary, e: Dictionary) -> bool:
	if e.get("kind")=="compound":return true
	var info:=Geometry.resolved(project,e)
	return not info.is_empty() and (info.descriptor.category!="ground" or e.get("plot_type")=="farmland")
static func _gate_opening(project: Dictionary, ribbon: Dictionary, gate: Dictionary) -> bool:
	if gate.kind=="compound":
		var socket:=Geometry.Compound.entrance(gate)
		if socket.is_empty():return false
		var point:=Vector2(socket.ground_xy[0],socket.ground_xy[1]);var along:=Vector2.from_angle(deg_to_rad(float(socket.direction_deg)));var cross:=Vector2(-along.y,along.x)*float(socket.width)*0.5
		var opening:=PackedVector2Array([point-along*12+cross,point+along*64+cross,point+along*64-cross,point-along*12-cross]);var valid:=true;var touches:=false
		for poly in ribbon.polygons:
			for intersection in Geometry2D.intersect_polygons(Geometry.footprint(project,gate),Asset.packed(poly)):
				if Geometry.area(intersection)<0.01:continue
				touches=true
				for outside in Geometry2D.clip_polygons(intersection,opening):
					if Geometry.area(outside)>0.01:valid=false
		return valid and touches and ribbon.get("role") in ["road","district_street"]
	var info:=Geometry.resolved(project,gate)
	if ribbon.get("role")!="road" or info.is_empty() or info.descriptor.category!="gate" or float(info.descriptor.get("passage_width_units",0))<=0: return false
	var footprint:=Geometry.footprint(project,gate)
	for socket in Geometry.sockets(project,gate):
		if socket.role!="road": continue
		var p:=Vector2(socket.ground_xy[0],socket.ground_xy[1])
		var radius:=1.0
		for point in footprint: radius=maxf(radius,point.distance_to(p)+1)
		var along:=Vector2.from_angle(deg_to_rad(float(socket.direction_ground)))
		var across:=Vector2(-along.y,along.x)*float(info.descriptor.passage_width_units)*float(gate.get("scale",1.0))*0.5
		var opening:=PackedVector2Array([p-along*radius+across,p+along*radius+across,p+along*radius-across,p-along*radius-across])
		var valid:=true
		var touches:=false
		for polygon in ribbon.polygons:
			for intersection in Geometry2D.intersect_polygons(footprint,Asset.packed(polygon)):
				if Geometry.area(intersection)<0.01: continue
				touches=true
				for outside in Geometry2D.clip_polygons(intersection,opening):
					if Geometry.area(outside)>0.01: valid=false;break
		if valid and touches: return true
	return false

static func resolve(project: Dictionary, candidates: Array) -> Dictionary:
	var overrides: Dictionary=project.manual_overrides
	var result: Array=project.manual_entities.duplicate(true)
	var manual_ids: Dictionary={}
	var diagnostics: Array=[]
	var protected: Array=project.manual_entities.duplicate(true)
	for e in result: manual_ids[e.entity_id]=true
	for e in overrides.fixed.values():
		if e is Dictionary and not manual_ids.has(e.get("entity_id")): protected.append(e.duplicate(true))
	var structural: Array=[]
	var ribbons: Array=[]
	for source in candidates:
		var key:=_key(source)
		if overrides.tombstones.has(key) or overrides.detached.has(key) or manual_ids.has(source.entity_id): continue
		var e: Dictionary=overrides.fixed.get(key,source).duplicate(true)
		if e.kind=="ribbon": ribbons.append(e)
		elif e.get("role")!="roadside": structural.append(e)
	# Preserve fixed children even when a changed generator no longer yields their slot.
	for key in overrides.fixed:
		var e: Dictionary=overrides.fixed[key]
		if overrides.tombstones.has(key) or overrides.detached.has(key) or manual_ids.has(e.entity_id): continue
		if not structural.any(func(item):return item.entity_id==e.entity_id) and not ribbons.any(func(item):return item.entity_id==e.entity_id): structural.append(e.duplicate(true))
	for ribbon in ribbons:
		for obstacle in protected:
			if obstacle.surface_id!=ribbon.surface_id or not _blocks(project,obstacle): continue
			if _ribbon_overlap(ribbon,Geometry.footprint(project,obstacle)) and not _gate_opening(project,ribbon,obstacle):
				return {"ok":false,"error":"路径侵入手工／固定对象占地："+str(obstacle.entity_id)+"。请先调整路径，未移动或删除该对象。"}
	result.append_array(ribbons)
	for e in structural:
		var conflict: String=""
		for obstacle in protected:
			if e.entity_id==obstacle.entity_id or e.surface_id!=obstacle.surface_id or not _blocks(project,obstacle): continue
			if Geometry.overlaps(Geometry.footprint(project,e),Geometry.footprint(project,obstacle)): conflict=obstacle.entity_id;break
		if not conflict.is_empty() and e.management!="fixed":
			diagnostics.append({"recipe_id":e.recipe_id,"segment_id":e.segment_id,"code":"protected_footprint","message":"未放置 "+e.entity_id+"，与手工／固定对象占地冲突："+conflict})
			continue
		result.append(e)
	var blockers: Array=result.filter(func(e):return e.kind in ["asset","compound"] and _blocks(project,e))
	for source in candidates:
		if source.get("role")!="roadside": continue
		var key:=_key(source)
		if overrides.tombstones.has(key) or overrides.detached.has(key) or manual_ids.has(source.entity_id): continue
		if result.any(func(e):return e.entity_id==source.entity_id): continue
		var e: Dictionary=overrides.fixed.get(key,source).duplicate(true)
		var footprint:=Geometry.footprint(project,e)
		var reason: String=""
		for point in footprint:
			if point.x<0 or point.y<0 or point.x>project.legacy_document.canvas_size[0] or point.y>project.legacy_document.canvas_size[1]: reason="占地超出可用画布";break
		for ribbon in ribbons:
			if e.surface_id==ribbon.surface_id and _ribbon_overlap(ribbon,footprint): reason="完整占地与道路／水域重叠";break
		for obstacle in blockers:
			if obstacle.entity_id==e.entity_id or obstacle.surface_id!=e.surface_id: continue
			var polygon:=Geometry.footprint(project,obstacle)
			if Geometry.overlaps(footprint,polygon): reason="与已有对象占地重叠";break
			if e.has("entrance_corridor") and Geometry.overlaps(Asset.packed(e.entrance_corridor),polygon): reason="出入口被占用";break
		if not reason.is_empty() and e.management!="fixed":
			diagnostics.append({"recipe_id":e.recipe_id,"segment_id":e.segment_id,"code":"roadside_rejected","message":e.entity_id+"："+reason})
			continue
		result.append(e);blockers.append(e)
	return {"ok":true,"entities":result,"diagnostics":diagnostics}
