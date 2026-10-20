@tool
extends RefCounted
const SurfaceProject = preload("surface_projection.gd")
const TerrainRender=preload("terrain_render.gd")
const Terrain=preload("terrain_geometry.gd")
const CompoundRender=preload("compound_render.gd")
const Asset = preload("asset_descriptor.gd")

static func bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0],Vector2.ZERO)
	for p in points: result=result.expand(p)
	return result

static func build(project: Dictionary) -> Array:
	return inspect(project).entries
static func inspect(project: Dictionary) -> Dictionary:
	var entries: Array = []
	var m: Array=project.style_profile.ground_matrix
	for e in project.materialized_snapshot.get("entities",[]):
		if e.get("hidden",false):continue
		var p := SurfaceProject.project_point(project,Vector2(e.ground_xy[0],e.ground_xy[1]),e.surface_id,float(e.local_height))
		if e.kind == "marker":
			entries.append({"entity":e,"position":p,"depth":float(e.ground_xy[1]),"entity_id":e.entity_id,"paint_bounds":Rect2(p-Vector2(18,36),Vector2(36,44)),"render_layer":1})
		elif e.kind == "ribbon":
			var polygons: Array=[]
			var all_points:=PackedVector2Array()
			for polygon in e.polygons:
				var projected:=PackedVector2Array()
				for point in polygon: projected.append(SurfaceProject.project_point(project,Vector2(point[0],point[1]),e.surface_id,float(e.local_height)))
				polygons.append(projected);all_points.append_array(projected)
			if not all_points.is_empty(): entries.append({"entity":e,"position":p,"depth":float(e.ground_xy[1]),"entity_id":e.entity_id,"paint_bounds":bounds(all_points),"polygons":polygons,"render_layer":1})
		elif e.kind=="compound":entries.append_array(CompoundRender.entries(project,e))
		elif e.kind == "asset":
			var descriptor: Dictionary = project.asset_refs[e.asset_ref]
			var orientation := Asset.orientation(descriptor,float(e.orientation))
			if not orientation.ok: continue
			var ref: String = orientation.asset_id if orientation.asset_id.contains("@") else orientation.asset_id+"@"+descriptor.asset_version
			if not project.asset_refs.has(ref): continue
			descriptor = project.asset_refs[ref]
			var unit: float = float(descriptor.nominal_size_units[0])/float(descriptor.region_px[2])*float(e.scale)
			var rotation := deg_to_rad(float(orientation.rotation))
			var anchor := Vector2(descriptor.anchor_px[0],descriptor.anchor_px[1])
			var paint := PackedVector2Array()
			for pixel in descriptor.paint_envelope: paint.append(p+(Vector2(pixel[0],pixel[1])-anchor).rotated(rotation)*unit)
			var footprint := PackedVector2Array()
			for point in descriptor.ground_footprint: footprint.append(Vector2(e.ground_xy[0],e.ground_xy[1])+Vector2(point[0],point[1]).rotated(rotation)*float(e.scale))
			var parts: Array = descriptor.render_parts
			if parts.is_empty(): parts=[{"region_px":[0,0,descriptor.region_px[2],descriptor.region_px[3]],"depth_offset":0.0}]
			for part in parts:
				var r: Array = part.region_px
				entries.append({"entity":e,"entity_id":e.entity_id,"position":p,"depth":float(e.ground_xy[1])+float(part.depth_offset),"paint_bounds":bounds(paint),"paint_polygon":paint,"ground_footprint":footprint,"descriptor":descriptor,"rotation":rotation,"unit":unit,"local_rect":Rect2((Vector2(r[0],r[1])-anchor)*unit,Vector2(r[2],r[3])*unit),"source_rect":Rect2(float(descriptor.region_px[0])+float(r[0]),float(descriptor.region_px[1])+float(r[1]),float(r[2]),float(r[3])),"render_layer":0 if descriptor.category=="ground" else 2})
	for f in project.legacy_document.features:
		if f.kind == "label":
			var p := SurfaceProject.project_point(project,Vector2(f.points[0][0],f.points[0][1]))
			entries.append({"entity":{"kind":"legacy_label","label":f.name},"position":p,"depth":float(f.points[0][1]),"entity_id":f.id,"paint_bounds":Rect2(p-Vector2(10,22),Vector2(180,30)),"render_layer":2})
	for entry in entries:
		if entry.entity.kind=="compound":continue
		var xy: Array=entry.entity.get("ground_xy",[])
		if xy.size()==2:entry.depth=float(m[1])*float(xy[0])+float(m[3])*float(xy[1])+float(entry.depth)-float(xy[1])
	entries.sort_custom(func(a,b):
		if a.render_layer != b.render_layer: return a.render_layer < b.render_layer
		if not is_equal_approx(a.depth,b.depth):return a.depth<b.depth
		return a.entity_id<b.entity_id if a.entity_id!=b.entity_id else a.get("part_order",0)<b.get("part_order",0))
	return TerrainRender.arrange(project,entries) if Terrain.enabled(project) else {"ok":true,"entries":entries}

static func pick(entries: Array, point: Vector2) -> String:
	for i in range(entries.size()-1,-1,-1):
		if entries[i].entity.get("locked",false):continue
		if not entries[i].paint_bounds.has_point(point): continue
		if entries[i].entity.kind=="terrain":
			for mesh in entries[i].parts:
				if Geometry2D.is_point_in_polygon(point,mesh.polygon):return entries[i].entity_id
		elif entries[i].entity.kind in ["ribbon","compound"]:
			for polygon in entries[i].polygons:
				if Geometry2D.is_point_in_polygon(point,polygon): return entries[i].entity_id
		else: return entries[i].entity_id
	return ""
