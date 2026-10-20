@tool
extends RefCounted
## Sole authoring contract. Derived snapshots never become another editable authority.
const Doc = preload("../document.gd")
const Asset = preload("asset_descriptor.gd")
const Scheduler = preload("recipe_scheduler.gd")
const Paths = preload("path_generator.gd")
const WaterBrush = preload("../water_brush.gd")
const Canonical = preload("canonical.gd")
const Plots = preload("plot_generator.gd")
const Plan=preload("render_plan.gd")
const Terrain=preload("terrain_geometry.gd")
const Entities=preload("entity_geometry.gd")
const District=preload("district_generator.gd")
const Compound=preload("compound_model.gd")
const GENERATOR_VERSION := "workshop_s1.w2.2"
static func generator_version(p: Dictionary) -> String:
	if not p.prefab_instances.is_empty() or p.style_profile.has("grid_kind") or p.manual_entities.any(func(e):return e.has("hidden")) or p.manual_overrides.fixed.values().any(func(e):return e.has("hidden")):return "workshop_s1.w6.1"
	if p.manual_entities.any(func(e):return e.get("kind")=="compound") or p.manual_overrides.fixed.values().any(func(e):return e.get("kind")=="compound") or p.recipes.any(func(r):return r.get("kind")=="district"):return "workshop_s1.w5.1"
	if Terrain.enabled(p):return "workshop_s1.w4.1"
	return "workshop_s1.w3.2" if p.recipes.any(func(r):return r.get("kind") in ["plot","brush"]) else GENERATOR_VERSION
const FIELDS := ["document_type", "schema_version", "project_id", "title", "legacy_document", "recipes", "manual_overrides", "manual_entities", "surfaces", "prefab_instances", "asset_refs", "style_profile", "export_profiles", "provenance", "materialized_snapshot"]

static func new_id(prefix: String) -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(12).hex_encode()

static func blank() -> Dictionary:
	var p := {"document_type":"shanhe.workshop_project", "schema_version":1,
		"project_id":new_id("project"), "title":"新工坊项目", "legacy_document":Doc.blank(),
		"recipes":[], "manual_overrides":{"fixed":{},"tombstones":{},"detached":{}},
		"manual_entities":[], "surfaces":[{"surface_id":"ground","height":0.0}],
		"prefab_instances":[], "asset_refs":{},
		"style_profile":{"style_id":"fixed_oblique_pending", "ground_matrix":[1.0,0.0,0.0,1.0], "height_axis":[0.0,-1.0],"unit":"map_unit", "light_direction":"upper_left", "paper_enabled":true},
		"export_profiles":[], "provenance":{"work_line":"workshop_s1", "geography":"game_design", "visual_review":"pending"}, "materialized_snapshot":{}}
	p.materialized_snapshot = materialize(p)
	return p

static func input_hash(p: Dictionary) -> String:
	# Root-only erase before a read-only hash; avoid cloning the derived subtree.
	var source := p.duplicate(false)
	source.erase("materialized_snapshot")
	return Canonical.digest(source)

static func materialize(p: Dictionary) -> Dictionary:
	var result:=Scheduler.build(p,p.get("materialized_snapshot",{}))
	if not result.ok: return result
	if Terrain.enabled(p):
		var drawing:=p.duplicate(false);drawing.materialized_snapshot=result
		var inspected:=Plan.inspect(drawing)
		if not inspected.ok:return {"ok":false,"error":inspected.error}
	result.erase("ok")
	result.input_hash=input_hash(p)
	result.generator_version=generator_version(p)
	return result

static func safe_relative(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or path.contains("\\"): return false
	for part in path.split("/"):
		if part in ["", ".", ".."]: return false
	return true

static func numeric(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))

static func pair(v: Variant) -> bool:
	return v is Array and v.size() == 2 and numeric(v[0]) and numeric(v[1])

static func validate(p: Dictionary) -> String:
	if p.get("document_type") != "shanhe.workshop_project" or p.get("schema_version") != 1: return "未知工坊项目协议。"
	for key in FIELDS:
		if not p.has(key): return "缺少项目字段：" + key
	for key in p:
		if key not in FIELDS: return "未知项目字段：" + str(key)
	for key in ["project_id","title"]:
		if not p[key] is String or p[key].is_empty(): return "无效项目名称或身份。"
	for key in ["recipes","manual_entities","surfaces","prefab_instances","export_profiles"]:
		if not p[key] is Array: return "无效列表：" + key
	for key in ["legacy_document","manual_overrides","asset_refs","style_profile","provenance","materialized_snapshot"]:
		if not p[key] is Dictionary: return "无效字典：" + key
	var legacy := Doc.new()
	var issue: String = legacy.validate(p.legacy_document)
	if not issue.is_empty(): return "旧 v4 校验失败：" + issue
	for feature in p.legacy_document.features:
		if feature.kind != "label" and not WaterBrush.is_river(feature): return "本构建的新模式只支持 v4 注记与河流桥接；其他旧地图请在原模式打开，不会丢弃其表现。"
	if not p.legacy_document.presentation.instances.is_empty(): return "此旧地图包含尚未适配的新模式表现，请在原地图模式打开。"
	if p.manual_entities.size() > 20000 or p.recipes.size() > 1000: return "项目超出当前安全规模。"
	for key in ["fixed","tombstones","detached"]:
		if not p.manual_overrides.get(key) is Dictionary: return "缺少手工保护记录：" + key
	var style: Dictionary = p.style_profile
	if style.has("paper_color") and (not style.paper_color is String or not Color.html_is_valid(style.paper_color)):return "项目纸色无效。"
	if not pair(style.get("height_axis")) or not style.get("ground_matrix") is Array or style.ground_matrix.size() != 4: return "无效表现场景坐标。"
	for v in style.ground_matrix:
		if not numeric(v): return "投影矩阵必须为有限数。"
	if is_zero_approx(float(style.ground_matrix[0])*float(style.ground_matrix[3])-float(style.ground_matrix[1])*float(style.ground_matrix[2])): return "投影矩阵不可逆。"
	var terrain_issue:=Terrain.validate(p)
	if not terrain_issue.is_empty():return terrain_issue
	var surfaces: Dictionary={}
	for s in p.surfaces:surfaces[s.surface_id]=s
	for id in p.asset_refs:
		var a: Variant=p.asset_refs[id]
		if not a is Dictionary: return "资产描述必须为字典。"
		var asset_issue:=Asset.validate(a)
		if not asset_issue.is_empty(): return asset_issue
		if id!=Asset.key(a): return "资产版本键与身份不一致。"
	var ids := {}
	for e in p.manual_entities:
		if not e is Dictionary or not e.get("entity_id") is String or e.entity_id.is_empty() or ids.has(e.entity_id): return "重复或无效对象身份。"
		ids[e.entity_id] = true
		if not pair(e.get("ground_xy")) or not numeric(e.get("local_height")) or not surfaces.has(e.get("surface_id")): return "对象坐标或支持面无效。"
		if absf(float(e.local_height)) > 10000: return "对象局部高度超出安全范围。"
		var xy: Array = e.ground_xy
		var extent: Array = p.legacy_document.canvas_size
		if xy[0] < 0 or xy[1] < 0 or xy[0] > extent[0] or xy[1] > extent[1]: return "对象超出画布。"
		if e.get("kind") not in ["marker","asset","compound"]: return "未知对象类型。"
		if e.kind == "asset":
			var ref: String = str(e.get("asset_ref",""))
			if not p.asset_refs.has(ref) or not p.asset_refs[ref] is Dictionary: return "对象缺少固定资产引用。"
			if not numeric(e.get("scale")) or float(e.scale)<0.1 or float(e.scale)>8 or not numeric(e.get("orientation")): return "对象比例或方向无效。"
			var a: Dictionary = p.asset_refs[ref]
			var orientation := Asset.orientation(a,float(e.orientation))
			if not orientation.ok: return orientation.error
			var oriented_ref: String = orientation.asset_id if orientation.asset_id.contains("@") else orientation.asset_id+"@"+a.asset_version
			if not p.asset_refs.has(oriented_ref): return "缺少已固定的方向变体资产。"
			a=p.asset_refs[oriented_ref]
			if Terrain.enabled(p):
				if not Terrain.contains(p,e.surface_id,Entities.footprint(p,e)):return "手工对象完整占地未受选定面支撑；请先移动对象或调整轮廓。"
			elif e.surface_id!="ground" and not Terrain.enclosed(Entities.footprint(p,e),Terrain.outline(surfaces[e.surface_id])):return "建筑完整占地未受选中高面支撑。"
		elif e.kind=="compound":
			var compound_issue:=Compound.validate_entity(p,e)
			if not compound_issue.is_empty():return compound_issue
		elif Terrain.enabled(p):
			var q:=Vector2(xy[0],xy[1])
			if not Terrain.contains(p,e.surface_id,Terrain.capsule(q-Vector2(0.1,0),q+Vector2(0.1,0),1)):return "手工标记未受所选面支撑。"
	for key in p.manual_overrides.fixed:
		var e: Variant=p.manual_overrides.fixed[key]
		if not e is Dictionary or not e.get("entity_id") is String or e.get("kind") not in ["asset","compound"] or not pair(e.get("ground_xy")) or not numeric(e.get("local_height")) or not surfaces.has(e.get("surface_id")) or not numeric(e.get("scale")) or not numeric(e.get("orientation")) or e.get("management")!="fixed" or not e.get("recipe_id") is String or not e.get("candidate_id") is String or not e.get("segment_id") is String:return "固定记录无效。"
		if key!=Paths.candidate_key(e.recipe_id,e.candidate_id) or e.entity_id!=Paths.identity(e.recipe_id,e.candidate_id) or p.manual_overrides.tombstones.has(key):return "固定记录身份冲突。"
		if e.kind=="compound":
			var issue_compound:=Compound.validate_entity(p,e)
			if not issue_compound.is_empty():return issue_compound
		elif not p.asset_refs.has(e.get("asset_ref")) or float(e.scale)<0.1 or float(e.scale)>8 or e.ground_xy[0]<0 or e.ground_xy[1]<0 or e.ground_xy[0]>p.legacy_document.canvas_size[0] or e.ground_xy[1]>p.legacy_document.canvas_size[1] or not Asset.orientation(p.asset_refs[e.asset_ref],float(e.orientation)).ok:return "固定对象位置、比例或方向无效。"
		if Terrain.enabled(p) and not Terrain.contains(p,e.surface_id,Entities.footprint(p,e)):return "固定对象完整占地未受所选面支撑；正式输入保留。"
	for key in p.manual_overrides.tombstones:
		var e: Variant=p.manual_overrides.tombstones[key]
		if not e is Dictionary or not e.get("recipe_id") is String or not e.get("candidate_id") is String or not e.get("entity_id") is String or not e.get("segment_id") is String or e.get("reason") not in ["deleted","detached"]: return "删除意图记录无效。"
		if key!=Paths.candidate_key(e.recipe_id,e.candidate_id) or e.entity_id!=Paths.identity(e.recipe_id,e.candidate_id): return "删除意图身份不匹配。"
	for key in p.manual_overrides.detached:
		if not p.manual_overrides.detached[key] is String or not ids.has(p.manual_overrides.detached[key]) or not p.manual_overrides.tombstones.has(key): return "脱离记录未关联唯一手工身份。"
	var recipe_ids: Dictionary={}
	for recipe in p.recipes:
		if not recipe is Dictionary: return "配方必须为字典。"
		var recipe_issue: String=District.validate(recipe,p) if recipe.get("kind")=="district" else (Paths.validate(recipe,p) if recipe.get("kind")=="path" else Plots.validate(recipe,p))
		if not recipe_issue.is_empty(): return recipe_issue
		if recipe_ids.has(recipe.recipe_id): return "配方身份重复。"
		recipe_ids[recipe.recipe_id]=true
	for feature in p.legacy_document.features:
		if WaterBrush.is_river(feature) and p.recipes.filter(func(r):return r.get("source_feature_id","")==feature.id).size()!=1: return "旧河流需要且只能有一份新模式表现投影。"
	var editor_issue: String=preload("editor_contract.gd").validate(p)
	if not editor_issue.is_empty():return editor_issue
	var cache: Dictionary = p.materialized_snapshot
	if not cache.get("entities") is Array or not cache.get("diagnostics") is Array or not cache.get("input_hash") is String or not cache.get("generator_version") is String: return "派生快照结构无效。"
	var cache_ids: Dictionary={}
	for e in cache.entities:
		if not e is Dictionary or not e.get("entity_id") is String or not pair(e.get("ground_xy")) or not numeric(e.get("local_height")) or not surfaces.has(e.get("surface_id")) or e.get("kind") not in ["marker","asset","ribbon","compound"]: return "派生快照对象无效。"
		if e.kind == "asset" and (not p.asset_refs.has(e.get("asset_ref")) or not numeric(e.get("scale")) or not numeric(e.get("orientation"))): return "派生快照缺少有效资产。"
		if e.kind=="compound":
			var compound_issue:=Compound.validate_entity(p,e,false)
			if not compound_issue.is_empty():return compound_issue
		if cache_ids.has(e.entity_id): return "派生快照出现重复实体身份。"
		cache_ids[e.entity_id]=true
		if e.kind=="ribbon":
			if not e.get("polygons") is Array: return "路径地带几何无效。"
			for polygon in e.polygons:
				if not Asset.polygon_ok(polygon): return "路径地带轮廓无效。"
	if cache.has("lots"):
		if not cache.lots is Array or cache.lots.size()>1000:return "派生地块列表无效。"
		var lot_ids: Dictionary={}
		for lot in cache.lots:
			if not lot is Dictionary or not lot.get("lot_id") is String or lot_ids.has(lot.lot_id) or not lot.get("candidate_id") is String or not lot.get("entity_id") is String or not lot.get("recipe_id") is String or not surfaces.has(lot.get("surface_id")) or lot.get("lot_role") not in ["buildable","future","permanent_clearance"] or not Asset.polygon_ok(lot.get("polygon")) or not pair(lot.get("ground_xy")) or not numeric(lot.get("orientation")) or not lot.get("entrance") is Dictionary or not pair(lot.entrance.get("ground_xy")) or not numeric(lot.entrance.get("direction_deg")) or not numeric(lot.entrance.get("width")):return "派生地块身份、角色、入口或完整占地无效。"
			lot_ids[lot.lot_id]=true
	return ""
