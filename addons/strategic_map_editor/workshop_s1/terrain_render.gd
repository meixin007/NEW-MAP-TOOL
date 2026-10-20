@tool
extends RefCounted
## Editable ink meshes in the shared render/pick plan. Paint is derived, never authored.
const T=preload("terrain_geometry.gd")
const P=preload("surface_projection.gd")
static func bounds(poly: PackedVector2Array) -> Rect2:
	var r:=Rect2(poly[0],Vector2.ZERO)
	for point in poly:r=r.expand(point)
	return r
static func project(p: Dictionary,poly: PackedVector2Array,id: String) -> PackedVector2Array:
	var out:=PackedVector2Array()
	for q in poly:out.append(P.project_point(p,q,id))
	return out
static func part(poly: PackedVector2Array,color: String,style: String="top") -> Dictionary:
	return {"polygon":poly,"color":color,"style":style}
static func group(p: Dictionary,s: Dictionary) -> Dictionary:
	var parts: Array=[];var ring:=T.outline(s)
	if s.kind=="ramp":
		parts.append(part(project(p,ring,s.surface_id),"cbb78a" if s.style=="dirt" else "aea58b","ramp"))
	else:
		var cuts: Array=[]
		for r in p.surfaces:
			if r.get("kind")=="ramp" and s.surface_id in [r.from_surface_id,r.to_surface_id] and T.absolute_height(p,s.surface_id)>minf(T.absolute_height(p,r.from_surface_id),T.absolute_height(p,r.to_surface_id)):cuts.append(T.outline(r))
		var bands:=T.edge_bands(s)
		var m: Array=p.style_profile.ground_matrix;var axis:=T.vec(p.style_profile.height_axis)
		for edge_index in range(bands.size()):
			var edge: Dictionary=bands[edge_index]
			if edge.style=="none":continue
			var normal: Vector2=edge.normal
			var screen_normal:=Vector2(m[0]*normal.x+m[2]*normal.y,m[1]*normal.x+m[3]*normal.y)
			if screen_normal.dot(-axis)<=0.001:continue
			var strips: Array=[PackedVector2Array([edge.a,edge.b])]
			for cut in cuts:
				var next: Array=[]
				for strip in strips:next.append_array(Geometry2D.clip_polyline_with_polygon(strip,cut))
				strips=next
			for strip in strips:
				var spread: Vector2=edge.outer_a-edge.a
				var a: Vector2=strip[0];var b: Vector2=strip[strip.size()-1]
				var mesh:=PackedVector2Array([P.project_point(p,a,s.surface_id),P.project_point(p,b,s.surface_id),P.project_point(p,b+spread,s.parent_surface_id),P.project_point(p,a+spread,s.parent_surface_id)])
				var rendered:=part(mesh,s.edge_color,edge.style)
				if edge.style=="slope":
					var parent:=T.surface(p,s.parent_surface_id)
					var floor_color: String=str(p.style_profile.get("paper_color","e4dfcb")) if s.parent_surface_id=="ground" else str(parent.get("top_color","c5bf89"))
					if s.parent_surface_id=="ground" and not p.style_profile.paper_enabled:floor_color="b1b7a0"
					var base:=Color(s.edge_color).lerp(Color(floor_color),float(s.get("edge_gradients",s.outline.map(func(_v):return 1))[edge_index]))
					rendered.colors=PackedColorArray([Color(s.edge_color),Color(s.edge_color),base,base])
				rendered.direction=float(s.get("edge_directions",s.outline.map(func(_v):return 0))[edge_index]);parts.append(rendered)
		# Shared top vertex and bevel joins close unequal adjacent spread widths.
		for i in range(bands.size()):
			var a: Dictionary=bands[(i-1+bands.size())%bands.size()];var b: Dictionary=bands[i]
			if a.style=="none" or b.style=="none" or a.normal.y+b.normal.y<=0:continue
			var join:=PackedVector2Array([P.project_point(p,b.a,s.surface_id),P.project_point(p,a.outer_b,s.parent_surface_id),P.project_point(p,b.outer_a,s.parent_surface_id)])
			if T.area(join)>0.02:
				var mesh:=part(join,s.edge_color,"join")
				if a.style=="slope" or b.style=="slope":
					var parent:=T.surface(p,s.parent_surface_id);var floor_color:=Color(str(p.style_profile.get("paper_color","e4dfcb")) if s.parent_surface_id=="ground" else str(parent.get("top_color","c5bf89")))
					mesh.colors=PackedColorArray([Color(s.edge_color),floor_color,floor_color])
				parts.append(mesh)
		var tops: Array=[ring]
		for cut in cuts:
			var next: Array=[]
			for top in tops:next.append_array(Geometry2D.clip_polygons(top,cut))
			tops=next
		for top in tops:
			# Polygon clipping can return hole rings. Ramp validation requires one open notch.
			parts.append(part(project(p,top,s.surface_id),s.top_color))
	var all:=PackedVector2Array();var max_depth: float=-INF
	for mesh in parts:all.append_array(mesh.polygon)
	for q in ring:max_depth=maxf(max_depth,P.project_point(p,q).y)
	return {"entity":{"kind":"terrain","surface_id":s.surface_id},"entity_id":"surface:"+s.surface_id,"position":Vector2.ZERO,"depth":max_depth,"paint_bounds":bounds(all) if not all.is_empty() else Rect2(),"parts":parts,"surface":s}
static func front_y(p: Dictionary,s: Dictionary,x: float) -> float:
	var ring:=project(p,T.outline(s),"ground");var front: float=-INF
	for i in range(ring.size()):
		var a:=ring[i];var b:=ring[(i+1)%ring.size()]
		if x<minf(a.x,b.x) or x>maxf(a.x,b.x):continue
		if is_equal_approx(a.x,b.x):front=maxf(front,maxf(a.y,b.y))
		else:front=maxf(front,lerpf(a.y,b.y,(x-a.x)/(b.x-a.x)))
	return front
static func arrange(p: Dictionary,objects: Array) -> Dictionary:
	var nodes: Array=[];var groups: Array=[]
	for s in p.surfaces:
		if s.has("kind"):groups.append(nodes.size());nodes.append(group(p,s))
	var first:=nodes.size();nodes.append_array(objects)
	var edges: Array=[];var degree: Array=[]
	for i in range(nodes.size()):edges.append({});degree.append(0)
	var connect:=func(a: int,b: int):
		if a!=b and not edges[a].has(b):edges[a][b]=true;degree[b]+=1
	for g in groups:
		var s: Dictionary=nodes[g].surface
		for h in groups:
			if g==h:continue
			var other: Dictionary=nodes[h].surface
			if other.get("parent_surface_id")==s.surface_id or (other.kind=="ramp" and s.surface_id in [other.from_surface_id,other.to_surface_id]):connect.call(g,h)
			elif s.kind=="terrace" and other.kind=="terrace" and s.parent_surface_id==other.parent_surface_id and nodes[g].paint_bounds.intersects(nodes[h].paint_bounds):
				if nodes[g].depth<nodes[h].depth or (nodes[g].depth==nodes[h].depth and s.surface_id<other.surface_id):connect.call(g,h)
		for o in range(first,nodes.size()):
			var e: Dictionary=nodes[o].entity
			if not e.has("surface_id"):continue
			var chain:=T.lineage(p,e.surface_id)
			if e.surface_id==s.surface_id or chain.has(s.surface_id):connect.call(g,o);continue
			if s.kind=="ramp":
				var upper: String=s.from_surface_id if T.absolute_height(p,s.from_surface_id)>T.absolute_height(p,s.to_surface_id) else s.to_surface_id
				# Valid upper-surface objects stand above the ramp; their crowns may
				# overlap its paint without putting the ramp over those objects.
				if upper in chain:connect.call(g,o);continue
			if not nodes[g].paint_bounds.intersects(nodes[o].paint_bounds):continue
			var q:=P.project_point(p,T.vec(e.ground_xy))
			if q.y<=front_y(p,s,q.x):connect.call(o,g)
			else:connect.call(g,o)
	# Preserve painter order within each support. Cross-surface constraints come from terrain.
	var last: Dictionary={}
	for o in range(first,nodes.size()):
		var e: Dictionary=nodes[o].entity;var key: String=str(e.get("surface_id","labels"))+":"+str(nodes[o].get("render_layer",2))
		if last.has(key):connect.call(last[key],o)
		last[key]=o
	var ready: Array=[];var result: Array=[]
	for i in range(nodes.size()):
		if degree[i]==0:ready.append(i)
	while not ready.is_empty():
		ready.sort_custom(func(a,b):
			var da: float=nodes[a].depth+float(nodes[a].get("render_layer",1))*float(p.legacy_document.canvas_size[1])*2
			var db: float=nodes[b].depth+float(nodes[b].get("render_layer",1))*float(p.legacy_document.canvas_size[1])*2
			return da<db if da!=db else nodes[a].entity_id<nodes[b].entity_id)
		var chosen: int=ready.pop_front();result.append(nodes[chosen])
		for target in edges[chosen]:
			degree[target]-=1
			if degree[target]==0:ready.append(target)
	if result.size()!=nodes.size():return {"ok":false,"error":"地形遮挡顺序形成循环，请分开重叠画面或调整轮廓。","entries":[]}
	return {"ok":true,"entries":result}
