@tool
extends RefCounted
const A=preload("asset_descriptor.gd")
static func point(q: Array,pivot: Vector2,angle: float,factor: float,offset: Vector2) -> Array:
	var v:=pivot+(Vector2(q[0],q[1])-pivot).rotated(deg_to_rad(angle))*factor+offset
	return [v.x,v.y]
static func options(command: Dictionary) -> String:
	if not A.pair(command.get("pivot")) or not A.pair(command.get("offset")) or not A.numeric(command.get("angle")) or not A.numeric(command.get("factor")) or command.factor<=0:return "组合变换参数无效。"
	return ""
static func recipe(r: Dictionary,pivot: Vector2,angle: float,factor: float,offset: Vector2) -> String:
	if r.get("locked",false):return "配方已锁定。"
	if r.kind=="path":
		for p in r.control_points:p.ground_xy=point(p.ground_xy,pivot,angle,factor,offset);p.width*=factor
		for role in r.roles:role.ground_xy=point(role.ground_xy,pivot,angle,factor,offset);role.orientation=fposmod(float(role.orientation)+angle,360)
	else:
		r.outer=r.outer.map(func(q):return point(q,pivot,angle,factor,offset));r.holes=r.holes.map(func(h):return h.map(func(q):return point(q,pivot,angle,factor,offset)))
		if r.kind=="plot":r.shape="polygon"
		if r.kind=="brush":r.stroke_points=r.stroke_points.map(func(q):return point(q,pivot,angle,factor,offset));r.radius*=factor
	return ""
static func surfaces(p: Dictionary,ids: Array,pivot: Vector2,angle: float,factor: float,offset: Vector2) -> String:
	for s in p.surfaces:
		if s.surface_id not in ids:continue
		if s.surface_id=="ground" or s.get("locked",false):return "组合支持面为 ground 或已锁定。"
		if s.get("kind")=="ramp":s.start=point(s.start,pivot,angle,factor,offset);s.end=point(s.end,pivot,angle,factor,offset);s.width*=factor
		else:
			s.outline=s.outline.map(func(q):return point(q,pivot,angle,factor,offset));s.height*=factor
			if s.has("edge_widths"):s.edge_widths=s.edge_widths.map(func(n):return n*factor)
	return ""
