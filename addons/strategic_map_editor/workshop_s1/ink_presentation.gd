@tool
extends RefCounted
## Derived pen marks in scene coordinates, shared by editor, export and preview.
## Never changes authored geometry, support, depth, picking or random state.
static func noise(point: Vector2,salt: float=0.0) -> float:
	return fposmod(sin(point.dot(Vector2(12.9898,78.233))+salt)*43758.5453,1.0)
static func clipped(drawer: CanvasItem,line: PackedVector2Array,polygon: PackedVector2Array,color: Color,width: float) -> void:
	for piece in Geometry2D.intersect_polyline_with_polygon(line,polygon):
		if piece.size()>1:drawer.draw_polyline(piece,color,width,true)
static func contour(drawer: CanvasItem,a: Vector2,b: Vector2,polygon: PackedVector2Array,color: Color) -> void:
	var count:=maxi(1,ceili(a.distance_to(b)/17.0))
	for i in range(count):
		var q:=a.lerp(b,(i+0.5)/count);var n:=noise(q)
		if n<0.2:continue
		var start: float=(i+0.03+n*0.12)/count;var end: float=minf(1.0,(i+0.6+n*0.35)/count)
		clipped(drawer,PackedVector2Array([a.lerp(b,start),a.lerp(b,end)]),polygon,color,0.7)
static func terrain(entry: Dictionary,drawer: CanvasItem) -> void:
	for mesh in entry.parts:
		var poly: PackedVector2Array=mesh.polygon
		if poly.size()<3 or Geometry2D.triangulate_polygon(poly).is_empty():continue
		if mesh.has("colors"):drawer.draw_polygon(poly,mesh.colors)
		else:drawer.draw_colored_polygon(poly,Color(mesh.color))
		var ink:=Color("89754f");ink.a=0.72
		if mesh.style in ["cliff","slope","bank"] and poly.size()==4:
			contour(drawer,poly[0],poly[1],poly,ink)
			var count:=maxi(1,int(poly[0].distance_to(poly[1])/10.0))
			var tangent: Vector2=(poly[1]-poly[0]).normalized()
			for i in range(count):
				var t: float=(i+0.15+noise(poly[0],i)*0.7)/count
				var a:=poly[0].lerp(poly[1],t);var b:=poly[3].lerp(poly[2],t);var n:=noise(a,7)
				if n<0.28:continue
				var length:=a.distance_to(b)
				var swing: float=tan(deg_to_rad(float(mesh.get("direction",0))))*length*0.4+(n-0.5)*6.0
				var start:=a.lerp(b,0.04+n*0.22)
				var mid:=a.lerp(b,0.25+n*0.25)+tangent*swing
				var end:=a.lerp(b,0.42+n*0.44)+tangent*(swing+noise(b,9)*3.0)
				clipped(drawer,PackedVector2Array([start,mid,end]),poly,ink,0.65)
				if mesh.style=="cliff" and n>0.65:clipped(drawer,PackedVector2Array([mid-tangent*2,mid+tangent*2+Vector2(0,1)]),poly,ink,0.65)
		elif mesh.style=="top":
			for i in range(poly.size()):contour(drawer,poly[i],poly[(i+1)%poly.size()],poly,ink)
			var box:=Rect2(poly[0],Vector2.ZERO)
			for q in poly:box=box.expand(q)
			for y in range(floori(box.position.y/47.0)*47,ceili(box.end.y),47):
				for x in range(floori(box.position.x/53.0)*53,ceili(box.end.x),53):
					var q:=Vector2(x,y);var n:=noise(q)
					if n<0.45:continue
					q+=Vector2(n*21,noise(q,2)*18)
					clipped(drawer,PackedVector2Array([q,q+Vector2(2+n*3,-0.8),q+Vector2(4+n*4,0.7)]),poly,Color("a89c6e"),0.65)
static func road(entry: Dictionary,drawer: CanvasItem) -> void:
	for poly in entry.polygons:
		drawer.draw_colored_polygon(poly,Color("ddc99d"))
		# Road strips retain their exact envelope. Inset broken tracks avoid seams
		# between rounded joins and never paint across protected footprints.
		if poly.size()!=18:continue
		var a: Vector2=(poly[0]+poly[10])*0.5;var b: Vector2=(poly[1]+poly[9])*0.5
		var d:=b-a;var normal:=Vector2(-d.y,d.x).normalized();var count:=maxi(1,int(d.length()/18.0))
		for i in range(count):
			var t: float=(i+0.2)/count;var q:=a.lerp(b,t);var n:=noise(q,13)
			if n<0.25:continue
			var half: float=poly[0].lerp(poly[1],t).distance_to(q)
			q+=normal*(n-0.5)*half
			clipped(drawer,PackedVector2Array([q,q+d.normalized()*(3+n*7)+normal*(n-0.5)]),poly,Color("c2ad83"),0.65)
