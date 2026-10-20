@tool
extends RefCounted
const M=preload("project_model.gd")
const A=preload("asset_descriptor.gd")
const P=preload("path_generator.gd")
const C=preload("compound_model.gd")
const KINDS=["asset_composite","map_group","recipe_preset"]
static func error(message: String) -> Dictionary:return {"ok":false,"error":message}
static func shift(points: Array,offset: Vector2) -> Array:
	return points.map(func(q):return [float(q[0])+offset.x,float(q[1])+offset.y])
static func move_surface(s: Dictionary,offset: Vector2) -> void:
	if s.has("outline"):s.outline=shift(s.outline,offset)
	if s.get("kind")=="ramp":s.start=shift([s.start],offset)[0];s.end=shift([s.end],offset)[0]
static func move_recipe(r: Dictionary,offset: Vector2) -> void:
	if r.kind=="path":
		for point in r.control_points:point.ground_xy=shift([point.ground_xy],offset)[0]
		for role in r.roles:role.ground_xy=shift([role.ground_xy],offset)[0]
	else:
		r.outer=shift(r.outer,offset);r.holes=r.holes.map(func(h):return shift(h,offset))
		if r.kind=="brush":r.stroke_points=shift(r.stroke_points,offset)
static func clean_entity(e: Dictionary,members: Array) -> Dictionary:
	var out: Dictionary=e.duplicate(true);out.management="manual";out.locked=false
	for field in ["recipe_id","candidate_id","segment_id","lot_id","location_binding","game_binding","plot_binding"]:out.erase(field)
	if out.has("socket_binding") and out.socket_binding.get("target_entity_id","") not in members:out.erase("socket_binding")
	return out
static func capture(p: Dictionary,ids: Array,kind: String,title: String,recipe_ids: Array=[],carry_overrides: bool=false) -> Dictionary:
	if kind not in KINDS or title.strip_edges().is_empty():return error("请选择模板类别并填写名称。")
	var entities: Array=[];var recipes: Array=[];var required_surfaces: Array=[];var recipe_set: Array=recipe_ids.duplicate()
	for e in p.materialized_snapshot.entities:
		if e.entity_id not in ids:continue
		if e.kind not in ["asset","compound","marker"]:return error("路径本体请保存为配方预设；地图组合可选择墙段、院落和树。")
		if kind=="asset_composite" and e.kind!="asset":return error("素材组合只保存图像对象与内部接点；院落请用地图组合。")
		entities.append(clean_entity(e,ids))
	if kind=="recipe_preset":
		entities.clear()
		for _i in range(16):
			var count:=recipe_set.size()
			for r in p.recipes:
				if r.recipe_id in recipe_set and r.kind=="district":
					for road_id in r.main_road_ids:
						if road_id not in recipe_set:recipe_set.append(road_id)
			if count==recipe_set.size():break
		for r in p.recipes:
			if r.recipe_id in recipe_set:recipes.append(r.duplicate(true))
	if entities.is_empty() and recipes.is_empty():return error("先在对象列表多选对象，或选择一个配方。")
	var origin:=Vector2(INF,INF)
	for e in entities:origin=origin.min(Vector2(e.ground_xy[0],e.ground_xy[1]));required_surfaces.append(e.surface_id)
	for r in recipes:
		required_surfaces.append(r.surface_id)
		var points: Array=r.control_points.map(func(q):return q.ground_xy) if r.kind=="path" else r.stroke_points if r.kind=="brush" else r.outer
		for q in points:origin=origin.min(Vector2(q[0],q[1]))
	for _i in range(65):
		var count:=required_surfaces.size()
		for s in p.surfaces:
			if s.surface_id not in required_surfaces or s.surface_id=="ground":continue
			for parent in ([s.from_surface_id,s.to_surface_id] if s.get("kind")=="ramp" else [s.get("parent_surface_id","ground")]):
				if parent not in required_surfaces:required_surfaces.append(parent)
		if count==required_surfaces.size():break
	var surfaces: Array=[]
	for surface in p.surfaces:
		if surface.surface_id!="ground" and surface.surface_id in required_surfaces:
			var copy: Dictionary=surface.duplicate(true);copy.locked=false;move_surface(copy,-origin);surfaces.append(copy)
	for e in entities:e.ground_xy=shift([e.ground_xy],-origin)[0]
	for r in recipes:move_recipe(r,-origin);r.locked=false;r.source_feature_id="" if r.kind=="path" else r.get("source_feature_id","");
	for r in recipes:
		if r.kind!="path":r.erase("source_feature_id")
	var overrides: Dictionary={"fixed":{},"tombstones":{},"detached":{}}
	if carry_overrides:
		for table in ["fixed","tombstones"]:
			for key in p.manual_overrides[table]:
				var e: Dictionary=p.manual_overrides[table][key]
				if e.recipe_id not in recipe_set:continue
				overrides[table][key]=e.duplicate(true)
				if table=="tombstones" and e.reason=="detached":overrides[table][key].reason="deleted"
				if table=="fixed":overrides[table][key].ground_xy=shift([e.ground_xy],-origin)[0]
	var t: Dictionary={"document_type":"shanhe.workshop_template","schema_version":1,"template_id":M.new_id("template"),"version":"v1","label":title.strip_edges(),"kind":kind,"origin":[origin.x,origin.y],"entities":entities,"surfaces":surfaces,"recipes":recipes,"overrides":overrides,"asset_refs":p.asset_refs.duplicate(true),"preview_ref":"preview.png","source_notice":"项目内版本固定快照；外部地点与游戏绑定不携带。"}
	t.preview_ref=t.template_id+"_"+t.version+".png"
	var issue:=validate(t)
	return error(issue) if not issue.is_empty() else {"ok":true,"template":t,"summary":{"entities":entities.size(),"recipes":recipes.size(),"surfaces":surfaces.size(),"carried_fixed":overrides.fixed.size(),"carried_deletions":overrides.tombstones.size()}}
static func validate(t: Dictionary) -> String:
	var fields: Array=["document_type","schema_version","template_id","version","label","kind","origin","entities","surfaces","recipes","overrides","asset_refs","preview_ref","source_notice"]
	for key in fields:
		if not t.has(key):return "模板缺少字段："+key
	for key in t:
		if key not in fields:return "未知模板字段："+str(key)
	if t.document_type!="shanhe.workshop_template" or t.schema_version!=1 or t.kind not in KINDS or not M.pair(t.origin):return "模板协议或坐标无效。"
	for key in ["template_id","version","label","source_notice"]:
		if not t[key] is String or t[key].is_empty() or t[key].length()>4096:return "模板名称／版本无效。"
	if not t.preview_ref is String or not M.safe_relative(t.preview_ref):return "模板预览路径无效。"
	for key in ["entities","surfaces","recipes"]:
		if not t[key] is Array or t[key].size()>(2000 if key=="entities" else 64):return "模板内容超出安全规模。"
	if not t.asset_refs is Dictionary or not t.overrides is Dictionary:return "模板依赖无效。"
	for key in t.asset_refs:
		if not t.asset_refs[key] is Dictionary or not A.validate(t.asset_refs[key]).is_empty() or key!=A.key(t.asset_refs[key]):return "模板资产版本无效。"
	var ids: Dictionary={}
	for e in t.entities:
		if not e is Dictionary or not e.get("entity_id") is String or ids.has(e.entity_id) or e.get("kind") not in ["asset","compound","marker"] or not M.pair(e.get("ground_xy")) or not e.get("surface_id") is String or not M.numeric(e.get("local_height")):return "模板对象身份或坐标无效。"
		ids[e.entity_id]=true
		if e.kind=="asset" and (not t.asset_refs.has(e.get("asset_ref")) or not M.numeric(e.get("scale")) or not M.numeric(e.get("orientation"))):return "模板对象资产／方向缺失。"
		if e.kind=="compound" and (not e.get("room_plan") is Dictionary or not C.validate_plan(e.room_plan,t.asset_refs).is_empty()):return "模板院落平面无效。"
	for key in ["fixed","tombstones","detached"]:
		if not t.overrides.get(key) is Dictionary:return "模板覆盖记录无效。"
	for s in t.surfaces:
		if not s is Dictionary or not s.get("surface_id") is String or s.surface_id=="ground" or not M.numeric(s.get("height")):return "模板支持面无效。"
	for r in t.recipes:
		if not r is Dictionary or not r.get("recipe_id") is String or r.get("kind") not in ["path","plot","brush","district"]:return "模板配方无效。"
	if t.entities.is_empty() and t.recipes.is_empty():return "模板内容为空。"
	if t.kind=="recipe_preset" and not t.entities.is_empty() or t.kind!="recipe_preset" and not t.recipes.is_empty():return "模板类别与快照／配方内容不一致。"
	if t.kind=="asset_composite" and t.entities.any(func(e):return e.kind!="asset"):return "素材组合不能包含原生院落。"
	var dummy:=M.blank();dummy.asset_refs=t.asset_refs.duplicate(true);dummy.legacy_document.canvas_size=[32768,32768];dummy.surfaces.append_array(t.surfaces.duplicate(true));dummy.recipes=t.recipes.duplicate(true)
	var padding:=Vector2(8192,8192)
	for s in dummy.surfaces:
		if s.surface_id=="ground":continue
		if s.get("kind")=="ramp":
			if not M.pair(s.get("start")) or not M.pair(s.get("end")):return "模板坡道坐标无效。"
		else:
			if not s.get("outline") is Array or not s.outline.all(func(q):return M.pair(q)):return "模板支持面轮廓无效。"
		move_surface(s,padding)
	var terrain_issue: String=M.Terrain.validate(dummy)
	if not terrain_issue.is_empty():return terrain_issue
	var recipe_ids: Dictionary={}
	for r in dummy.recipes:
		if recipe_ids.has(r.recipe_id):return "模板配方身份重复。"
		recipe_ids[r.recipe_id]=true
		var issue: String=M.District.validate(r,dummy) if r.kind=="district" else M.Paths.validate(r,dummy) if r.kind=="path" else M.Plots.validate(r,dummy)
		if not issue.is_empty():return issue
	for e in t.entities:
		if not dummy.surfaces.any(func(s):return s.surface_id==e.surface_id):return "模板对象支持面缺失。"
		if e.has("socket_binding") and not e.socket_binding is Dictionary:return "模板内部接点记录无效。"
	for table in ["fixed","tombstones"]:
		for e in t.overrides[table].values():
			if not e is Dictionary or not e.get("recipe_id") is String or not recipe_ids.has(e.recipe_id) or not e.get("candidate_id") is String or not e.get("entity_id") is String or not e.get("segment_id") is String:return "模板覆盖身份无效。"
			if table=="fixed" and (not M.pair(e.get("ground_xy")) or not e.get("surface_id") is String):return "模板固定对象坐标无效。"
	return ""
static func instantiate(next: Dictionary,t: Dictionary,at: Array) -> Dictionary:
	var issue:=validate(t)
	if not issue.is_empty():return error(issue)
	if not M.pair(at):return error("模板放置坐标无效。")
	var offset:=Vector2(at[0],at[1]);var surface_map: Dictionary={"ground":"ground"};var recipe_map: Dictionary={};var entity_map: Dictionary={}
	for key in t.asset_refs:
		if next.asset_refs.has(key) and P.digest(next.asset_refs[key])!=P.digest(t.asset_refs[key]):return error("同名资产版本不同，未覆盖："+key)
		next.asset_refs[key]=t.asset_refs[key].duplicate(true)
	for surface in t.surfaces:surface_map[surface.surface_id]=M.new_id("surface")
	for surface in t.surfaces:
		var s: Dictionary=surface.duplicate(true);s.surface_id=surface_map[s.surface_id];move_surface(s,offset)
		for key in ["parent_surface_id","from_surface_id","to_surface_id"]:
			if s.has(key):
				if not surface_map.has(s[key]):return error("模板支持面依赖缺失。")
				s[key]=surface_map[s[key]]
		next.surfaces.append(s)
	for r in t.recipes:recipe_map[r.recipe_id]=M.new_id("recipe")
	for recipe in t.recipes:
		var r: Dictionary=recipe.duplicate(true);r.recipe_id=recipe_map[r.recipe_id]
		if not surface_map.has(r.get("surface_id")):return error("模板配方支持面缺失。")
		r.surface_id=surface_map[r.surface_id];move_recipe(r,offset)
		if r.kind=="district":r.main_road_ids=r.main_road_ids.map(func(id):return recipe_map.get(id,"missing"))
		next.recipes.append(r)
	for e in t.entities:entity_map[e.entity_id]=M.new_id("manual")
	for entity in t.entities:
		var e:=clean_entity(entity,entity_map.keys());e.entity_id=entity_map[entity.entity_id];e.ground_xy=shift([e.ground_xy],offset)[0]
		if not surface_map.has(e.surface_id):return error("模板对象支持面缺失。")
		e.surface_id=surface_map[e.surface_id]
		if e.has("socket_binding"):e.socket_binding.target_entity_id=entity_map[e.socket_binding.target_entity_id]
		next.manual_entities.append(e)
	for table in ["fixed","tombstones"]:
		for item in t.overrides[table].values():
			if not item is Dictionary or not recipe_map.has(item.get("recipe_id")):return error("模板固定／删除记录依赖缺失。")
			var e: Dictionary=item.duplicate(true);e.recipe_id=recipe_map[e.recipe_id];e.entity_id=P.identity(e.recipe_id,e.candidate_id)
			if table=="fixed":e.ground_xy=shift([e.ground_xy],offset)[0];e.surface_id=surface_map.get(e.surface_id,"missing");e.erase("socket_binding")
			next.manual_overrides[table][P.candidate_key(e.recipe_id,e.candidate_id)]=e
	var group: Dictionary={"instance_id":M.new_id("group"),"template_id":t.template_id,"template_version":t.version,"label":t.label,"kind":t.kind,"entity_ids":entity_map.values(),"surface_ids":surface_map.values().filter(func(id):return id!="ground"),"recipe_ids":recipe_map.values()}
	next.prefab_instances.append(group)
	return {"ok":true,"instance_id":group.instance_id,"entity_ids":group.entity_ids}
