@tool
extends RefCounted
const Asset=preload("asset_descriptor.gd")
const Entities=preload("entity_geometry.gd")
const Paths=preload("path_generator.gd")

static func shape(type: String, a: Array, b: Array) -> Array:
	var lo:=Vector2(minf(a[0],b[0]),minf(a[1],b[1]))
	var hi:=Vector2(maxf(a[0],b[0]),maxf(a[1],b[1]))
	if type=="rectangle":return [[lo.x,lo.y],[hi.x,lo.y],[hi.x,hi.y],[lo.x,hi.y]]
	var points: Array=[]
	var center: Vector2=(lo+hi)*0.5
	var radius: Vector2=(hi-lo)*0.5
	for i in range(6 if type=="hexagon" else 32):
		var angle: float=TAU*i/(6 if type=="hexagon" else 32)
		var p:=center+Vector2(cos(angle)*radius.x,sin(angle)*radius.y)
		points.append([snappedf(p.x,1.0/1024),snappedf(p.y,1.0/1024)])
	return points
static func packed(points: Array) -> PackedVector2Array:
	var p:=Asset.packed(points)
	if Geometry2D.is_polygon_clockwise(p):p.reverse()
	return p
static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():return Rect2()
	var r:=Rect2(points[0],Vector2.ZERO)
	for p in points:r=r.expand(p)
	return r
static func contains_polygon(outer: Array, holes: Array, polygon: PackedVector2Array) -> bool:
	if polygon.size()<3:return false
	for outside in Geometry2D.clip_polygons(polygon,packed(outer)):
		if Entities.area(outside)>0.01:return false
	for hole in holes:
		if Entities.overlaps(polygon,packed(hole)):return false
	return true
static func validate(outer: Variant, holes: Variant) -> String:
	if not Asset.polygon_ok(outer) or not holes is Array or holes.size()>16:return "区域需要简单外轮廓及最多16个有效洞。"
	for i in range(holes.size()):
		if not Asset.polygon_ok(holes[i]) or not contains_polygon(outer,[],packed(holes[i])):return "洞必须完整位于区域内部且不能自交。"
		var ring:=packed(holes[i]);var boundary:=packed(outer)
		for a in range(ring.size()):
			for b in range(boundary.size()):
				if Geometry2D.segment_intersects_segment(ring[a],ring[(a+1)%ring.size()],boundary[b],boundary[(b+1)%boundary.size()])!=null:return "洞不能接触或穿过外边界。"
		for j in range(i):
			if Entities.overlaps(ring,packed(holes[j])):return "洞之间不能重叠或嵌套。"
	return ""
static func stroke_polygons(points: Array, radius: float) -> Array:
	var result: Array=[]
	if points.size()==1:
		return [shape("ellipse",[points[0][0]-radius,points[0][1]-radius],[points[0][0]+radius,points[0][1]+radius])]
	for i in range(points.size()-1):result.append(Paths.strip(Vector2(points[i][0],points[i][1]),Vector2(points[i+1][0],points[i+1][1]),radius*2,radius*2))
	return result
static func overlaps_region(project: Dictionary, entity: Dictionary, region: Dictionary) -> bool:
	if entity.surface_id!=region.surface_id:return false
	var footprint:=Entities.footprint(project,entity)
	for part in Geometry2D.intersect_polygons(footprint,packed(region.outer)):
		var remainder: Array[PackedVector2Array]=[part]
		for hole in region.holes:
			var next: Array[PackedVector2Array]=[]
			for polygon in remainder:next.append_array(Geometry2D.clip_polygons(polygon,packed(hole)))
			remainder=next
		for polygon in remainder:
			if Entities.area(polygon)>0.01:return true
	return false
static func stroke_hits(project: Dictionary, entity: Dictionary, stroke: Dictionary) -> bool:
	if entity.surface_id!=stroke.surface_id:return false
	var footprint:=Entities.footprint(project,entity)
	for polygon in stroke_polygons(stroke.stroke_points,float(stroke.radius)):
		if Entities.overlaps(footprint,packed(polygon)):return true
	return false
