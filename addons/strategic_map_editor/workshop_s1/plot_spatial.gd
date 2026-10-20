@tool
extends RefCounted
const Geometry=preload("plot_geometry.gd")
const CELL: float=128.0
var buckets: Dictionary={}
var large: Array=[]
var records: Array=[]
func insert(record: Dictionary, polygon: PackedVector2Array) -> void:
	if polygon.size()<3:return
	var item:=record.duplicate(false);item.polygon=polygon;item.bounds=Geometry.bounds(polygon);item.index=records.size();records.append(item)
	var lo:=Vector2i(floori(item.bounds.position.x/CELL),floori(item.bounds.position.y/CELL));var hi:=Vector2i(floori(item.bounds.end.x/CELL),floori(item.bounds.end.y/CELL))
	if (hi.x-lo.x+1)*(hi.y-lo.y+1)>512:large.append(item);return
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var key:=Vector2i(x,y)
			if not buckets.has(key):buckets[key]=[]
			buckets[key].append(item)
func query(polygon: PackedVector2Array) -> Array:
	var bounds:=Geometry.bounds(polygon);var result: Array=[];var seen: Dictionary={}
	var lo:=Vector2i(floori(bounds.position.x/CELL),floori(bounds.position.y/CELL));var hi:=Vector2i(floori(bounds.end.x/CELL),floori(bounds.end.y/CELL))
	var possible: Array=large.duplicate()
	if (hi.x-lo.x+1)*(hi.y-lo.y+1)>512:possible=records
	else:
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):possible.append_array(buckets.get(Vector2i(x,y),[]))
	for item in possible:
		if seen.has(item.index):continue
		seen[item.index]=true
		if bounds.intersects(item.bounds):result.append(item)
	return result
