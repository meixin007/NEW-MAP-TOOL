@tool
extends RefCounted
## Freeze geometry, never event counts. Collinear oversampling changes no stroke.
static func normalize(points: Array) -> Array:
	var result: Array=[]
	for p in points:
		var v: Array=[snappedf(float(p[0]),1.0/1024),snappedf(float(p[1]),1.0/1024)]
		if not result.is_empty() and result[-1]==v:continue
		while result.size()>=2:
			var a:=Vector2(result[-2][0],result[-2][1]);var b:=Vector2(result[-1][0],result[-1][1]);var c:=Vector2(v[0],v[1])
			if absf((b-a).cross(c-b))>0.001 or (b-a).dot(c-b)<0:break
			result.pop_back()
		result.append(v)
	return result
static func recipe(id: String, mode: String, points: Array, radius: float, ref: String, surface: String) -> Dictionary:
	return {"recipe_id":id,"kind":"brush","name":"擦除笔迹" if mode=="erase" else "放置笔迹","plot_type":"scatter","shape":"stroke","outer":[],"holes":[],"stroke_points":normalize(points),"brush_mode":mode,"radius":radius,"surface_id":surface,"seed":42,"density":0.8,"spacing":[64.0,48.0],"scale_range":[0.75,1.0],"asset_weights":[] if ref.is_empty() else [{"asset_ref":ref,"weight":1.0}],"cluster_strength":0.0,"locked":false}
