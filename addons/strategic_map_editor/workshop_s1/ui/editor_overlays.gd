@tool
extends RefCounted
const P=preload("../surface_projection.gd")
static func draw(p: Dictionary,drawer: CanvasItem,zoom: float,grid: bool,legend: bool) -> void:
	var style: Dictionary=p.style_profile;var size: float=style.get("grid_size",32);var extent:=Vector2(p.legacy_document.canvas_size[0],p.legacy_document.canvas_size[1])
	if grid and style.get("grid_visible",false):
		var color:=Color(0.25,0.33,0.27,0.23)
		if style.get("grid_kind","square")=="square":
			for x in range(0,int(extent.x)+1,int(size)):drawer.draw_line(P.project_point(p,Vector2(x,0)),P.project_point(p,Vector2(x,extent.y)),color,0.7/zoom)
			for y in range(0,int(extent.y)+1,int(size)):drawer.draw_line(P.project_point(p,Vector2(0,y)),P.project_point(p,Vector2(extent.x,y)),color,0.7/zoom)
		else:
			if extent.x*extent.y/(size*size)>20000:return
			for row in range(int(extent.y/(size*1.5))+1):
				for col in range(int(extent.x/(size*sqrt(3.0)))+1):
					var center:=Vector2(sqrt(3.0)*(col+0.5*(row%2)),1.5*row)*size;var ring:=PackedVector2Array()
					for i in range(7):ring.append(P.project_point(p,center+Vector2.from_angle(deg_to_rad(60*i-30))*size))
					drawer.draw_polyline(ring,color,0.7/zoom)
	if legend:
		var anchor:=P.project_point(p,Vector2(30,30));var index:=0
		for row in style.get("legend",[]):
			var position: Vector2=anchor+Vector2(0,index*26)
			drawer.draw_rect(Rect2(position,Vector2(16,16)),Color(row.color));drawer.draw_string(ThemeDB.fallback_font,position+Vector2(23,14),row.label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("38372c"));index+=1
