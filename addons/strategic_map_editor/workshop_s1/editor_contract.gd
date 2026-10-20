@tool
extends RefCounted
const A=preload("asset_descriptor.gd")
static func validate(p: Dictionary) -> String:
	if p.prefab_instances.size()>1000:return "组合实例超过1000个。"
	var groups: Dictionary={};var entities: Dictionary={};var recipes: Dictionary={};var surfaces: Dictionary={}
	for e in p.manual_entities:entities[e.entity_id]=true
	for r in p.recipes:recipes[r.recipe_id]=true
	for s in p.surfaces:surfaces[s.surface_id]=true
	for g in p.prefab_instances:
		if not g is Dictionary:return "组合记录须为字典。"
		for field in ["instance_id","template_id","template_version","label","kind","entity_ids","surface_ids","recipe_ids"]:
			if not g.has(field):return "组合记录缺少字段。"
		for field in ["instance_id","template_id","template_version","label"]:
			if not g[field] is String or g[field].is_empty():return "组合身份／版本无效。"
		if groups.has(g.instance_id) or g.kind not in ["asset_composite","map_group","recipe_preset"]:return "组合身份重复或类别无效。"
		groups[g.instance_id]=true
		for pair in [["entity_ids",entities],["surface_ids",surfaces],["recipe_ids",recipes]]:
			if not g[pair[0]] is Array:return "组合成员必须为列表。"
			var seen: Dictionary={}
			for id in g[pair[0]]:
				if not id is String or seen.has(id) or not pair[1].has(id):return "组合成员重复或依赖缺失。"
				seen[id]=true
	var style_issue:=validate_style(p.style_profile)
	if not style_issue.is_empty():return style_issue
	for e in p.manual_entities+p.manual_overrides.fixed.values():
		for field in ["hidden","locked"]:
			if e.has(field) and not e[field] is bool:return "对象隐藏／锁定值无效。"
	return ""
static func prune_groups(p: Dictionary) -> void:
	var ids: Array=p.manual_entities.map(func(e):return e.get("entity_id",""));var recipes: Array=p.recipes.map(func(r):return r.get("recipe_id",""))
	for g in p.prefab_instances:
		g.entity_ids=g.entity_ids.filter(func(id):return id in ids);g.recipe_ids=g.recipe_ids.filter(func(id):return id in recipes)
	p.prefab_instances=p.prefab_instances.filter(func(g):return not g.entity_ids.is_empty() or not g.recipe_ids.is_empty())

static func validate_style(style: Dictionary) -> String:
	if style.get("grid_kind","square") not in ["square","hex"] or not A.numeric(style.get("grid_size",32)) or float(style.get("grid_size",32))<8 or float(style.get("grid_size",32))>512:return "网格类型或尺寸无效。"
	for field in ["grid_visible","grid_snap","edge_snap"]:
		if style.has(field) and not style[field] is bool:return "网格显示／吸附开关须为布尔值。"
	if not style.get("legend",[]) is Array or style.get("legend",[]).size()>32:return "图例列表无效。"
	for row in style.get("legend",[]):
		if not row is Dictionary or not row.get("label") is String or row.label.length()>128 or not row.get("color") is String or not Color.html_is_valid(row.color):return "图例名称或颜色无效。"
	return ""
