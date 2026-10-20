@tool
extends RefCounted
const District=preload("district_generator.gd")
const Terrain=preload("terrain_geometry.gd")
const Entities=preload("entity_geometry.gd")
const Asset=preload("asset_descriptor.gd")
const Paths = preload("path_generator.gd")
const Overrides = preload("override_resolver.gd")
const Plots = preload("plot_generator.gd")

static func build(project: Dictionary, previous: Dictionary) -> Dictionary:
	var candidates: Array=[]
	var plot_candidates: Array=[]
	var diagnostics: Array=[]
	var cache: Dictionary={}
	var stats: Dictionary={"rebuilt_segments":0,"reused_segments":0,"candidate_count":0}
	var old_cache: Dictionary=previous.get("recipe_cache",{})
	for recipe in project.recipes:
		if recipe.kind=="district":continue
		var result: Dictionary=Paths.build(recipe,project,old_cache.get(recipe.recipe_id,{})) if recipe.kind=="path" else Plots.build(recipe,project,old_cache.get(recipe.recipe_id,{}))
		if not result.ok: return result
		if recipe.kind=="path":candidates.append_array(result.entities)
		else:plot_candidates.append_array(result.entities)
		diagnostics.append_array(result.diagnostics)
		cache[recipe.recipe_id]=result.cache
		stats.rebuilt_segments+=result.rebuilt
		stats.reused_segments+=result.reused
		if candidates.size()+plot_candidates.size()>20000: return {"ok":false,"error":"项目候选超过 20000，未采用部分结果。"}
	var resolved:=Overrides.resolve(project,candidates)
	if not resolved.ok: return resolved
	diagnostics.append_array(resolved.diagnostics)
	var district_lots: Array=[];var district_entities: Array=resolved.entities
	for recipe in project.recipes:
		if recipe.kind!="district":continue
		var result:=District.build(recipe,project,district_entities,old_cache.get(recipe.recipe_id,{}),district_lots)
		if not result.ok:return result
		district_entities.append_array(result.entities);district_lots.append_array(result.lots);diagnostics.append_array(result.diagnostics);cache[recipe.recipe_id]=result.cache
		stats.rebuilt_segments+=result.rebuilt;stats.reused_segments+=result.reused;stats.district_attempts=int(stats.get("district_attempts",0))+result.attempts
		if district_entities.size()>20000 or district_lots.size()>1000:return {"ok":false,"error":"街区超过当前20000对象／1000地块项目预算，整笔未采用。"}
	var plots: Dictionary=Plots.resolve(project,district_entities,plot_candidates,district_lots) if project.recipes.any(func(r):return r.kind in ["plot","brush"]) else {"entities":district_entities,"diagnostics":[]}
	diagnostics.append_array(plots.diagnostics)
	if Terrain.enabled(project):
		var supported: Array=[]
		for e in plots.entities:
			var valid:=true
			if e.kind in ["asset","compound"]:valid=Terrain.contains(project,e.surface_id,Entities.footprint(project,e))
			elif e.kind=="ribbon":
				for polygon in e.polygons:
					if not Terrain.contains(project,e.surface_id,Asset.packed(polygon),true):valid=false;break
			if valid:supported.append(e);continue
			if e.get("role") in ["plot","roadside","district"] and e.management=="generated":
				diagnostics.append({"code":"unsupported_surface","entity_id":e.entity_id,"recipe_id":e.recipe_id,"message":"完整占地未受单一支持面支撑，未放置。"});continue
			return {"ok":false,"error":"对象／道路完整占地未受支持，禁止穿崖："+str(e.entity_id)+"；请分段选面并建立坡道。"}
		plots.entities=supported
	stats.candidate_count=candidates.size()+plot_candidates.size()+district_lots.size()
	var final: Dictionary={"ok":true,"entities":plots.entities,"diagnostics":diagnostics,"recipe_cache":cache,"stats":stats}
	if project.recipes.any(func(r):return r.kind=="district"):final.lots=district_lots
	return final
