@tool
extends RefCounted
const Asset=preload("asset_descriptor.gd")
const Geometry=preload("plot_geometry.gd")
const Entities=preload("entity_geometry.gd")
const Paths=preload("path_generator.gd")
const Spatial=preload("plot_spatial.gd")
const Terrain=preload("terrain_geometry.gd")
const VERSION: String="plot.sha256-utf8-world-grid.v1"
const MAX_GRID_CELLS: int=4096
const MAX_CANDIDATES: int=2000

static func validate(r: Dictionary, p: Dictionary) -> String:
	for field in r:
		if field not in ["recipe_id","kind","name","plot_type","shape","outer","holes","surface_id","seed","density","spacing","scale_range","asset_weights","cluster_strength","locked","stroke_points","brush_mode","radius","erase_manual"]:return "未知区域字段或本阶段未支持的显式依赖："+str(field)
	if r.has("erase_manual") and not r.erase_manual is bool:return "擦除手工对象开关必须是布尔值。"
	for field in ["recipe_id","kind","name","plot_type","shape","outer","holes","surface_id","seed","density","spacing","scale_range","asset_weights","cluster_strength","locked"]:
		if not r.has(field):return "区域／笔迹缺少字段："+field
	if not r.recipe_id is String or r.recipe_id.is_empty() or not r.name is String or r.kind not in ["plot","brush"] or r.plot_type not in ["forest","scatter","farmland","ground","clearance"] or not r.locked is bool:return "无效区域身份、类型或锁定值。"
	if not p.surfaces.any(func(s):return s.surface_id==r.surface_id):return "区域缺少明确支持面。"
	if not Asset.numeric(r.seed) or float(r.seed)!=floorf(float(r.seed)) or not Asset.numeric(r.density) or float(r.density)<0 or float(r.density)>1 or not Asset.numeric(r.cluster_strength) or float(r.cluster_strength)<0 or float(r.cluster_strength)>1:return "密度、团簇强度或种子无效。"
	if not Asset.pair(r.spacing) or r.spacing[0]<16 or r.spacing[1]<16 or r.spacing[0]>512 or r.spacing[1]>512 or not Asset.pair(r.scale_range) or r.scale_range[0]<0.1 or r.scale_range[1]<r.scale_range[0] or r.scale_range[1]>8:return "候选格或尺寸范围无效。"
	if not r.asset_weights is Array or r.asset_weights.size()>16:return "每配方最多16种加权资产。"
	var ids: Dictionary={}
	for item in r.asset_weights:
		if not item is Dictionary or not p.asset_refs.has(item.get("asset_ref")) or ids.has(item.asset_ref) or not Asset.numeric(item.get("weight")) or float(item.weight)<=0:return "资产版本或权重无效。"
		if r.plot_type in ["farmland","ground"] and p.asset_refs[item.asset_ref].category!="ground":return "农田／地表需要地面资产，不能旋转建筑充当地表。"
		ids[item.asset_ref]=true
	if r.kind=="brush":
		if r.get("brush_mode") not in ["place","erase"] or not Asset.numeric(r.get("radius")) or r.radius<8 or r.radius>512 or not r.get("stroke_points") is Array or r.stroke_points.is_empty() or r.stroke_points.size()>256:return "笔刷需要1—256点及8—512单位半径。"
		for point in r.stroke_points:
			if not Asset.pair(point) or point[0]<0 or point[1]<0 or point[0]>p.legacy_document.canvas_size[0] or point[1]>p.legacy_document.canvas_size[1]:return "笔迹超出画布。"
	else:
		if r.shape not in ["polygon","rectangle","ellipse","hexagon"]:return "未知区域形状。"
		var issue:=Geometry.validate(r.outer,r.holes)
		if not issue.is_empty():return issue
		for ring in [r.outer]+r.holes:
			for point in ring:
				if point[0]<0 or point[1]<0 or point[0]>p.legacy_document.canvas_size[0] or point[1]>p.legacy_document.canvas_size[1]:return "区域超出画布。"
	if r.asset_weights.is_empty() and r.plot_type!="clearance" and r.get("brush_mode","")!="erase":return "请选择至少一种资产。"
	return ""
static func random_unit(token: String) -> float:
	return float(token.sha256_text().substr(0,12).hex_to_int())/281474976710655.0
static func _inside(r: Dictionary, polygon: PackedVector2Array, masks: Array) -> bool:
	if r.kind=="plot":return Geometry.contains_polygon(r.outer,r.holes,polygon)
	# Each footprint is wholly supported by one swept capsule; junctions may be conservative.
	for mask in masks:
		if Geometry.contains_polygon(mask,[],polygon):return true
	return false
static func build(r: Dictionary, p: Dictionary, previous: Dictionary) -> Dictionary:
	var assets: Dictionary={}
	for item in r.asset_weights:assets[item.asset_ref]=p.asset_refs[item.asset_ref]
	var support: Dictionary={}
	for s in p.surfaces:
		if s.surface_id==r.surface_id:support=s
	var signature:=Paths.digest([VERSION,r,assets,p.surfaces if Terrain.enabled(p) else support])
	if previous.get("hash")==signature:return {"ok":true,"entities":previous.entities.duplicate(true),"diagnostics":previous.diagnostics.duplicate(true),"cache":previous.duplicate(true),"rebuilt":0,"reused":1}
	var entities: Array=[];var diagnostics: Array=[];var rejected: Dictionary={}
	if r.plot_type=="clearance" or r.get("brush_mode","")=="erase":return {"ok":true,"entities":[],"diagnostics":[],"cache":{"hash":signature,"entities":[],"diagnostics":[]},"rebuilt":1,"reused":0}
	var masks: Array=Geometry.stroke_polygons(r.stroke_points,float(r.radius)) if r.kind=="brush" else []
	var boundary:=Geometry.bounds(Geometry.packed(r.outer)) if r.kind=="plot" else Geometry.bounds(Asset.packed(r.stroke_points)).grow(float(r.radius))
	var min_x: int=floori(boundary.position.x/float(r.spacing[0]));var max_x: int=floori(boundary.end.x/float(r.spacing[0]))
	var min_y: int=floori(boundary.position.y/float(r.spacing[1]));var max_y: int=floori(boundary.end.y/float(r.spacing[1]))
	if (max_x-min_x+1)*(max_y-min_y+1)>MAX_GRID_CELLS:return {"ok":false,"error":"区域候选格超过4096格预算；请增大格距或缩小范围，正式项目未修改。"}
	var weight_sum:=0.0
	for item in r.asset_weights:weight_sum+=float(item.weight)
	for y in range(min_y,max_y+1):
		for x in range(min_x,max_x+1):
			var id: String="grid/"+Paths.digest(r.spacing).substr(0,8)+"/"+str(x)+"/"+str(y)
			var token: String=VERSION+":"+r.recipe_id+":"+id+":"+str(int(r.seed))
			var cluster: float=lerpf(1.0,random_unit(str(int(r.seed))+":cluster:"+str(floori(x/3.0))+":"+str(floori(y/3.0))),float(r.cluster_strength))
			if random_unit(token+":density")>float(r.density)*cluster:continue
			var target: float=random_unit(token+":asset")*weight_sum;var ref: String=r.asset_weights[-1].asset_ref
			for item in r.asset_weights:
				target-=float(item.weight)
				if target<=0:ref=item.asset_ref;break
			var a: Dictionary=p.asset_refs[ref]
			var e: Dictionary={"entity_id":Paths.identity(r.recipe_id,id),"kind":"asset","ground_xy":[0.0,0.0],"surface_id":r.surface_id,"local_height":0.0,"label":r.name,"management":"generated","recipe_id":r.recipe_id,"candidate_id":id,"segment_id":"","role":"plot","plot_type":r.plot_type,"asset_ref":ref,"orientation":float(a.get("default_orientation",0.0)),"scale":snappedf(lerpf(float(r.scale_range[0]),float(r.scale_range[1]),random_unit(token+":scale")),1.0/1024),"locked":r.locked}
			var footprint:=Entities.footprint(p,e);var box:=Geometry.bounds(footprint)
			if box.size.x>float(r.spacing[0])*0.8 or box.size.y>float(r.spacing[1])*0.8:rejected.cell_fit=int(rejected.get("cell_fit",0))+1;continue
			var center:=Vector2((x+0.5)*float(r.spacing[0]),(y+0.5)*float(r.spacing[1]))
			# Jitter uses all available cell room, while full ground bounds remain
			# within disjoint cells. Density cannot displace earlier candidates.
			var room: Vector2=(Vector2(r.spacing[0],r.spacing[1])-box.size)*0.85
			center+=Vector2(random_unit(token+":x")-0.5,random_unit(token+":y")-0.5)*room
			var anchor:=center-box.get_center();e.ground_xy=[snappedf(anchor.x,1.0/1024),snappedf(anchor.y,1.0/1024)]
			if not _inside(r,Entities.footprint(p,e),masks):rejected.boundary_or_hole=int(rejected.get("boundary_or_hole",0))+1;continue
			if (Terrain.enabled(p) and not Terrain.contains(p,r.surface_id,Entities.footprint(p,e))) or (not Terrain.enabled(p) and r.surface_id!="ground" and not Geometry.contains_polygon(support.outline,[],Entities.footprint(p,e))):rejected.unsupported_surface=int(rejected.get("unsupported_surface",0))+1;continue
			entities.append(e)
			if entities.size()>MAX_CANDIDATES:return {"ok":false,"error":"单区域超过2000对象预算；请降低密度或分区，正式项目未修改。"}
	for code in rejected:diagnostics.append({"recipe_id":r.recipe_id,"segment_id":"","code":code,"count":rejected[code],"message":"区域 "+r.name+"："+str(rejected[code])+" 个候选未放置（"+code+"）。"})
	if entities.is_empty():diagnostics.append({"recipe_id":r.recipe_id,"segment_id":"","code":"no_legal_candidate","message":"区域没有合法候选；检查密度、格距、完整占地及洞。"})
	return {"ok":true,"entities":entities,"diagnostics":diagnostics,"cache":{"hash":signature,"entities":entities.duplicate(true),"diagnostics":diagnostics.duplicate(true)},"rebuilt":1,"reused":0}
static func resolve(p: Dictionary, base: Array, candidates: Array, lots: Array=[]) -> Dictionary:
	var result: Array=base.duplicate(true);var diagnostics: Array=[];var counts: Dictionary={}
	var ids: Dictionary={}
	for e in result:ids[e.entity_id]=true
	var occupied:=Spatial.new()
	var manual_ground: Array=[]
	for other in result:
		if other.kind=="asset" and p.asset_refs[other.asset_ref].category=="ground" and other.get("plot_type")!="farmland" and other.get("management") in ["manual","fixed"]:
			var polygon:=Entities.footprint(p,other)
			manual_ground.append({"entity":other,"bounds":Geometry.bounds(polygon)})
		if other.kind=="ribbon":
			for polygon in other.polygons:occupied.insert({"type":"road_or_water","surface_id":other.surface_id},Geometry.packed(polygon))
		elif other.kind=="compound":occupied.insert({"type":"protected_or_occupied","surface_id":other.surface_id},Entities.footprint(p,other))
		elif other.kind=="asset" and (p.asset_refs[other.asset_ref].category!="ground" or other.get("plot_type")=="farmland"):occupied.insert({"type":"protected_or_occupied","surface_id":other.surface_id,"entity":other},Entities.footprint(p,other))
	for lot in lots:occupied.insert({"type":"district_lot","surface_id":lot.surface_id},Geometry.packed(lot.polygon))
	for r in p.recipes:
		if r.get("plot_type")=="clearance":
			occupied.insert({"type":"permanent_clearance","surface_id":r.surface_id,"region":r},Geometry.packed(r.outer))
			var protected_count:=0
			# Query conservative spatial bounds first, then run the same exact polygon
			# predicate. Avoid all manual objects x all clearance regions per edit.
			for item in occupied.query(Geometry.packed(r.outer)):
				if not item.has("entity"):continue
				var e: Dictionary=item.entity
				if e.get("management") in ["manual","fixed"] and Geometry.overlaps_region(p,e,r):protected_count+=1
			# Nonblocking ground sprites were also counted by the old diagnostic;
			# preserve that behavior without making them collision obstacles.
			var region_bounds:=Geometry.bounds(Geometry.packed(r.outer))
			for item in manual_ground:
				if region_bounds.intersects(item.bounds) and Geometry.overlaps_region(p,item.entity,r):protected_count+=1
			if protected_count>0:diagnostics.append({"recipe_id":r.recipe_id,"segment_id":"","code":"protected_in_clearance","count":protected_count,"message":"留白内已有 "+str(protected_count)+" 个手工／固定对象，已保留；请明确移动或删除后清空。"})
		elif r.get("brush_mode")=="erase":
			for mask in Geometry.stroke_polygons(r.stroke_points,float(r.radius)):occupied.insert({"type":"erase_intent","surface_id":r.surface_id},Geometry.packed(mask))
	var ordered:=candidates.duplicate()
	ordered.sort_custom(func(a,b):
		if (a.plot_type=="farmland")!=(b.plot_type=="farmland"):return a.plot_type=="farmland"
		return a.entity_id<b.entity_id)
	for e in ordered:
		var key:=Paths.candidate_key(e.recipe_id,e.candidate_id)
		if ids.has(e.entity_id) or p.manual_overrides.tombstones.has(key) or p.manual_overrides.detached.has(key):continue
		var reason: String="";var footprint:=Entities.footprint(p,e)
		for other in occupied.query(footprint):
			if other.surface_id!=e.surface_id:continue
			var hits: bool=Geometry.overlaps_region(p,e,other.region) if other.type=="permanent_clearance" else Entities.overlaps(footprint,other.polygon)
			if hits:reason=other.type;break
		if reason.is_empty():
			result.append(e);ids[e.entity_id]=true
			if p.asset_refs[e.asset_ref].category!="ground" or e.plot_type=="farmland":occupied.insert({"type":"protected_or_occupied","surface_id":e.surface_id},footprint)
		else:
			var count_key: String=e.recipe_id+":"+reason
			counts[count_key]=int(counts.get(count_key,0))+1
	for key in counts:
		var split: PackedStringArray=str(key).split(":")
		diagnostics.append({"recipe_id":split[0],"segment_id":"","code":split[1],"count":counts[key],"message":str(counts[key])+" 个区域候选避让："+split[1]+"。"})
	return {"ok":true,"entities":result,"diagnostics":diagnostics}
