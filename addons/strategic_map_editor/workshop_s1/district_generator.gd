@tool
extends RefCounted
## Bounded W5 lot solver. Stable world cells/road slots, full footprints, explicit access.
const Overrides=preload("override_resolver.gd")
const C=preload("compound_model.gd")
const A=preload("asset_descriptor.gd")
const T=preload("terrain_geometry.gd")
const E=preload("entity_geometry.gd")
const G=preload("plot_geometry.gd")
const Paths=preload("path_generator.gd")
const MAX_CELLS:=256
const FIELDS=["recipe_id","kind","name","layout","outer","holes","surface_id","seed","density","vacancy","future_fraction","cell_size","courtyard_size","street_width","safety_margin","main_road_ids","lot_roles","function","roof_material","locked"]
static func recipe(id: String,layout: String,outer: Array,surface: String,roads: Array) -> Dictionary:
	return {"recipe_id":id,"kind":"district","name":"街区","layout":layout,"outer":outer.duplicate(true),"holes":[],"surface_id":surface,"seed":42,"density":0.8,"vacancy":0.2,"future_fraction":0.1,"cell_size":[240,220],"courtyard_size":[180,160],"street_width":14.0,"safety_margin":8.0,"main_road_ids":roads.duplicate(),"lot_roles":{},"function":"residential","roof_material":"","locked":false}
static func validate(r: Dictionary,p: Dictionary) -> String:
	for field in FIELDS:
		if not r.has(field):return "街区缺少字段："+field
	for field in r:
		if field not in FIELDS:return "未知街区字段："+str(field)
	if not r.recipe_id is String or r.recipe_id.is_empty() or r.kind!="district" or not r.name is String or r.layout not in ["orthogonal","along_road"] or r.function not in ["residential","market","storage"] or not r.locked is bool:return "街区身份、布局或用途无效。"
	var issue:=G.validate(r.outer,r.holes)
	if not issue.is_empty():return issue
	if not r.surface_id is String or T.surface(p,r.surface_id).is_empty() or T.surface(p,r.surface_id).get("kind")=="ramp":return "街区需要明确平面，不能建在坡道。"
	for key in ["density","vacancy","future_fraction"]:
		if not A.numeric(r[key]) or float(r[key])<0 or float(r[key])>1:return "街区密度／空地比例须在0—1。"
	if float(r.vacancy)+float(r.future_fraction)>1:return "永久留白与未来扩建比例合计不能超过1。"
	if not A.numeric(r.seed) or float(r.seed)!=floorf(float(r.seed)) or absf(float(r.seed))>2147483647:return "街区种子须为有界整数。"
	for key in ["cell_size","courtyard_size"]:
		if not A.pair(r[key]) or r[key][0]<80 or r[key][1]<80 or r[key][0]>512 or r[key][1]>512:return "街区格距／院落尺寸须在80—512。"
	if r.courtyard_size[0]<120 or r.courtyard_size[1]<120:return "院落尺寸不足，不能自动缩成不合理小屋。"
	if not A.numeric(r.street_width) or r.street_width<8 or r.street_width>20 or not A.numeric(r.safety_margin) or r.safety_margin<0 or r.safety_margin>64:return "支路宽度或安全退距无效。"
	if not r.main_road_ids is Array or r.main_road_ids.is_empty() or r.main_road_ids.size()>16:return "街区须引用1—16条明确主路。"
	var used: Array=[]
	for id in r.main_road_ids:
		if not id is String or used.has(id):return "街区主路身份重复或无效。"
		used.append(id);var found:=false
		for path in p.recipes:
			if path.get("recipe_id")==id and path.get("kind")=="path" and path.get("path_type")=="road" and path.get("surface_id")==r.surface_id:found=true
		if not found:return "街区主路不存在、不是道路或支持面不同。"
	if not r.lot_roles is Dictionary or r.lot_roles.size()>MAX_CELLS:return "地块角色覆盖数量无效。"
	for id in r.lot_roles:
		if not id is String or r.lot_roles[id] not in ["buildable","future","permanent_clearance"]:return "地块角色无效。"
	if not r.roof_material is String or not r.roof_material.is_empty() and (not p.asset_refs.has(r.roof_material) or not p.asset_refs[r.roof_material].tags.has("surface_material")):return "屋顶需要固定版本的表面材质。"
	return ""
static func unit(token: String) -> float:
	return float(("district.w5:"+token).sha256_text().substr(0,7).hex_to_int())/268435455.0
static func polygon_region(poly: PackedVector2Array,region: Dictionary) -> bool:
	for part in Geometry2D.intersect_polygons(poly,A.packed(region.outer)):
		if T.area(part)<0.02:continue
		if not region.get("holes",[]).any(func(hole):return T.enclosed(part,A.packed(hole))):return true
	return false
static func why(p: Dictionary,r: Dictionary,poly: PackedVector2Array,base: Array,own: String,roads_allowed: bool=false) -> String:
	if not G.contains_polygon(r.outer,r.holes,poly):return "outside_boundary"
	if not T.contains(p,r.surface_id,poly,roads_allowed):return "unsupported_or_cliff"
	for region in p.recipes:
		if region.get("plot_type")=="clearance" and region.surface_id==r.surface_id and polygon_region(poly,region):return "permanent_clearance"
	for e in base:
		if e.surface_id!=r.surface_id or e.entity_id==own:continue
		if e.kind=="ribbon":
			if roads_allowed and e.get("role") in ["road","district_street"]:continue
			for part in e.polygons:
				if T.overlaps(poly,A.packed(part)):return "road_or_water"
		elif e.kind=="compound" or e.kind=="asset" and (p.asset_refs[e.asset_ref].category!="ground" or e.get("plot_type")=="farmland"):
			if T.overlaps(poly,E.footprint(p,e)):return "protected_or_occupied"
	return ""
static func road_segments(r: Dictionary,p: Dictionary) -> Array:
	var out: Array=[]
	for id in r.main_road_ids:
		for path in p.recipes:
			if path.recipe_id!=id:continue
			for i in range(path.segments.size()):out.append({"road_id":id,"segment_id":path.segments[i].segment_id,"a":T.vec(path.control_points[i].ground_xy),"b":T.vec(path.control_points[i+1].ground_xy),"width":maxf(path.control_points[i].width,path.control_points[i+1].width)})
	return out
static func nearest(point: Vector2,roads: Array) -> Dictionary:
	var best: Dictionary={};var distance: float=INF
	for road in roads:
		var q:=Geometry2D.get_closest_point_to_segment(point,road.a,road.b)
		if q.distance_squared_to(point)<distance:distance=q.distance_squared_to(point);best=road.duplicate(false);best.point=q
	return best
static func raw_slots(r: Dictionary,roads: Array) -> Dictionary:
	var out: Array=[];var size:=G.bounds(A.packed(r.outer));var w: float=r.courtyard_size[0];var d: float=r.courtyard_size[1]
	if r.layout=="orthogonal":
		var lo:=Vector2i(floori(size.position.x/r.cell_size[0]),floori(size.position.y/r.cell_size[1]));var hi:=Vector2i(ceili(size.end.x/r.cell_size[0]),ceili(size.end.y/r.cell_size[1]))
		if (hi.x-lo.x)*(hi.y-lo.y)>MAX_CELLS:return {"ok":false,"error":"街区候选网格超过256格，请减小区域或增大格距。"}
		for j in range(lo.y,hi.y):
			for i in range(lo.x,hi.x):
				var center:=Vector2((i+0.5)*r.cell_size[0],(j+0.5)*r.cell_size[1]);var road:=nearest(center,roads);var delta: Vector2=road.point-center
				var angle: float=(0 if delta.y>=0 else 180) if absf(delta.y)>=absf(delta.x) else (270 if delta.x>=0 else 90)
				out.append({"slot":"grid/"+str(i)+"/"+str(j),"root":center+Vector2.DOWN.rotated(deg_to_rad(angle))*d*0.5,"angle":angle,"road_point":road.point})
	else:
		for road in roads:
			var length: float=road.a.distance_to(road.b);var direction: Vector2=(road.b-road.a).normalized();var normal:=Vector2(-direction.y,direction.x)
			var count:=int(floor(length/r.cell_size[0]))
			if out.size()+count*2>MAX_CELLS:return {"ok":false,"error":"沿路候选超过256格，请减少主路或增大间距。"}
			for side in [-1,1]:
				for i in range(count):
					var q: Vector2=road.a+direction*(i+0.5)*float(r.cell_size[0]);var outward: Vector2=-normal*side;var angle:=rad_to_deg(outward.angle())-90
					var center: Vector2=q+normal*side*(float(road.width)*0.5+float(r.safety_margin)+d*0.5+float(r.street_width))
					out.append({"slot":"road/"+road.road_id+"/"+road.segment_id+"/"+str(side)+"/"+str(i),"root":center+outward*d*0.5,"angle":angle,"road_point":q})
	return {"ok":true,"slots":out}
static func build(r: Dictionary,p: Dictionary,base: Array,previous: Dictionary,other_lots: Array) -> Dictionary:
	var signature:=Paths.digest([r,p.surfaces,p.manual_overrides,base,other_lots,p.recipes.filter(func(q):return q.get("plot_type")=="clearance" or q.recipe_id in r.main_road_ids)])
	if previous.get("signature")==signature:return {"ok":true,"entities":previous.entities.duplicate(true),"lots":previous.lots.duplicate(true),"diagnostics":previous.diagnostics.duplicate(true),"cache":previous.duplicate(true),"attempts":0,"rebuilt":0,"reused":1}
	var roads:=road_segments(r,p);var raw:=raw_slots(r,roads)
	if not raw.ok:return raw
	var lots: Array=[];var entities: Array=[];var diagnostics: Array=[];var reasons: Dictionary={};var attempts:=0
	var layout:=C.plan("courtyard",r.courtyard_size[0],r.courtyard_size[1],r.function);layout.roof_material=r.roof_material
	for slot in raw.slots:
		var candidate: String="lot/"+slot.slot;var id:=Paths.identity(r.recipe_id,candidate);var e:=C.entity(id,r.surface_id,slot.root,layout);e.orientation=slot.angle
		var fp:=E.footprint(p,e);var expanded:=Geometry2D.offset_polygon(fp,float(r.safety_margin));var safety: PackedVector2Array=expanded[0] if not expanded.is_empty() else fp
		var reason:=why(p,r,safety,base,id)
		if reason.is_empty():
			for old in other_lots+lots:
				if old.surface_id==r.surface_id and T.overlaps(fp,A.packed(old.polygon)):reason="overlapping_lots";break
		if not reason.is_empty():reasons[reason]=int(reasons.get(reason,0))+1;continue
		var role: String=str(r.lot_roles.get(candidate,""));var token: String=str(int(r.seed))+":"+candidate
		if role.is_empty():
			var value:=unit(token+":role");role="permanent_clearance" if value<float(r.vacancy) else ("future" if value<float(r.vacancy)+float(r.future_fraction) else "buildable")
		var lot: Dictionary={"lot_id":r.recipe_id+"/"+candidate,"candidate_id":candidate,"entity_id":id,"recipe_id":r.recipe_id,"surface_id":r.surface_id,"ground_xy":e.ground_xy,"orientation":e.orientation,"polygon":Array(fp).map(func(q):return [q.x,q.y]),"lot_role":role,"entrance":C.entrance(e),"status":"reserved" if role!="buildable" else "empty"}
		lots.append(lot)
	# Main paths and lots exist before any optional buildings or decoration. Two access attempts max.
	for lot in lots:
		var key:=Paths.candidate_key(r.recipe_id,lot.candidate_id)
		var held: Dictionary={}
		for existing in base:
			if existing.entity_id==lot.entity_id:held=existing;break
		if p.manual_overrides.detached.has(key):lot.status="detached"
		elif p.manual_overrides.tombstones.has(key):lot.status="deleted";continue
		elif not held.is_empty():lot.status="fixed"
		if held.is_empty() and (lot.status=="detached" or lot.lot_role!="buildable" or unit(str(int(r.seed))+":"+lot.candidate_id+":density")>float(r.density)):continue
		var e:=held.duplicate(true) if not held.is_empty() else C.entity(lot.entity_id,r.surface_id,T.vec(lot.ground_xy),layout)
		if held.is_empty():e.orientation=lot.orientation;e.management="generated";e.recipe_id=r.recipe_id;e.candidate_id=lot.candidate_id;e.segment_id="";e.role="district";e.lot_id=lot.lot_id;e.label=r.name+" · "+r.function
		var reason:=why(p,r,E.footprint(p,e),base+entities,e.entity_id)
		if not reason.is_empty():lot.status="occupied";reasons[reason]=int(reasons.get(reason,0))+1;continue
		var actual_entrance:=C.entrance(e)
		if actual_entrance.is_empty():reasons["closed_entrance"]=int(reasons.get("closed_entrance",0))+1;continue
		lot.entrance=actual_entrance
		var start:=T.vec(lot.entrance.ground_xy);var target: Vector2=nearest(start,roads).point;var routes: Array=[[start,Vector2(start.x,target.y),target],[start,Vector2(target.x,start.y),target]] if r.layout=="orthogonal" else [[start,target]]
		var accepted: Array=[];var success:=false
		for route in routes:
			attempts+=1;var polygons: Array=[];reason=""
			for i in range(route.size()-1):
				if route[i].distance_to(route[i+1])<0.1:continue
				var poly: Array=Paths.strip(route[i],route[i+1],r.street_width,r.street_width);reason=why(p,r,A.packed(poly),base+entities,e.entity_id,true)
				if not reason.is_empty():break
				if T.overlaps(A.packed(poly),E.footprint(p,e)) and not Overrides._gate_opening(p,{"kind":"ribbon","role":"district_street","polygons":[poly]},e):reason="entrance_direction";break
				for reserved in other_lots+lots:
					if reserved.lot_id==lot.lot_id or reserved.surface_id!=r.surface_id or reserved.lot_role=="buildable":continue
					if T.overlaps(A.packed(poly),A.packed(reserved.polygon)):reason="reserved_access";break
				if not reason.is_empty():break
				polygons.append(poly)
			if reason.is_empty() and not polygons.is_empty():accepted=polygons;success=true;break
		if not success:lot.status="inaccessible";reasons["entrance_blocked"]=int(reasons.get("entrance_blocked",0))+1;continue
		var street_id: String="access/"+lot.candidate_id
		entities.append({"entity_id":Paths.identity(r.recipe_id,street_id),"candidate_id":street_id,"recipe_id":r.recipe_id,"segment_id":"","kind":"ribbon","role":"district_street","style":"dirt","management":"generated","ground_xy":lot.ground_xy.duplicate(),"surface_id":r.surface_id,"local_height":0.0,"polygons":accepted,"label":r.name+" · 支路"})
		if held.is_empty():entities.append(e);lot.status="built"
	var labels: Dictionary={"outside_boundary":"完整占地超出街区边界","unsupported_or_cliff":"占地缺少支撑或越过崖边","permanent_clearance":"侵入永久留白","road_or_water":"侵入道路或水面","protected_or_occupied":"占地已有建筑或受保护对象","overlapping_lots":"地块交叠","reserved_access":"支路穿过保留地","entrance_direction":"入口朝向不通","entrance_blocked":"两种支路方案均无法连接入口"}
	for reason in reasons:diagnostics.append({"recipe_id":r.recipe_id,"segment_id":"","code":reason,"count":reasons[reason],"message":str(reasons[reason])+" 处未生成："+str(labels.get(reason,reason))+"；可调整边界、退距或手工放置。"})
	if lots.is_empty():diagnostics.append({"recipe_id":r.recipe_id,"segment_id":"","code":"no_legal_lots","message":"没有完整合法地块；请扩大区域、调整院落尺寸或减少排除范围，不自动缩小建筑。"})
	var cache: Dictionary={"signature":signature,"entities":entities.duplicate(true),"lots":lots.duplicate(true),"diagnostics":diagnostics.duplicate(true)}
	return {"ok":true,"entities":entities,"lots":lots,"diagnostics":diagnostics,"cache":cache,"attempts":attempts,"rebuilt":1,"reused":0}
