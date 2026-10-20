@tool
extends RefCounted
const Paths = preload("path_generator.gd")
const Geometry = preload("entity_geometry.gd")
const PlotGeometry=preload("plot_geometry.gd")
const EDITABLE := ["label","ground_xy","surface_id","local_height","scale","orientation","socket_binding","room_plan","hidden"]

static func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}
static func find_entity(project: Dictionary, id: String) -> Dictionary:
	for e in project.materialized_snapshot.get("entities",[]):
		if e.entity_id==id: return e
	return {}
static func find_recipe(project: Dictionary, id: String) -> Dictionary:
	for recipe in project.recipes:
		if recipe.recipe_id==id: return recipe
	return {}
static func _protected_segment(project: Dictionary, recipe_id: String, segment_ids: Array) -> bool:
	for table in [project.manual_overrides.fixed,project.manual_overrides.tombstones]:
		for e in table.values():
			if e is Dictionary and e.get("recipe_id")==recipe_id and e.get("segment_id") in segment_ids and e.get("reason")!="detached": return true
	return false

static func check_protection_delta(source: Dictionary, next: Dictionary, command: Dictionary) -> String:
	var operation: String=str(command.get("op",""))
	if operation not in ["add_manual","update_manual","update_entity","snap_entity","add_asset_version","transform_entities","transform_instance","transform_recipes","instantiate_template"]: return ""
	var candidates: Array=next.manual_entities.duplicate(true)+next.manual_overrides.fixed.values()
	var fixed: Array=next.manual_overrides.fixed.values()
	var changed_ids: Array=command.get("adopt_entity_ids",[]) if operation=="add_asset_version" else [str(command.get("entity",{}).get("entity_id","")) if operation=="add_manual" else str(command.get("entity_id",""))]
	if operation=="transform_entities":changed_ids=command.get("entity_ids",[])
	elif operation in ["transform_instance","transform_recipes"]:
		changed_ids=candidates.filter(func(e):return find_entity(source,e.entity_id)!=e).map(func(e):return e.entity_id)
	elif operation=="instantiate_template":changed_ids=candidates.map(func(e):return e.entity_id).filter(func(id):return find_entity(source,id).is_empty())
	for e in candidates:
		if e.get("kind") not in ["asset","compound"] or e.entity_id not in changed_ids: continue
		var old:=find_entity(source,e.entity_id)
		var polygon:=Geometry.footprint(next,e)
		if not old.is_empty() and old.get("kind")=="asset" and Geometry.footprint(source,old)==polygon: continue
		for r in next.recipes:
			if r.get("plot_type")=="clearance" and PlotGeometry.overlaps_region(next,e,r):return "修改后的完整占地侵入永久留白；原对象保留。"
		var obstacles: Array=candidates if command.get("op")=="add_asset_version" else fixed
		for other in obstacles:
			if other.get("kind") not in ["asset","compound"] or other.entity_id==e.entity_id or other.surface_id!=e.surface_id: continue
			var info:=Geometry.resolved(next,other)
			if other.kind!="compound" and (info.is_empty() or info.descriptor.category=="ground"): continue
			if Geometry.overlaps(polygon,Geometry.footprint(next,other)): return "修改后的完整占地侵入固定／受保护对象："+other.entity_id+"。旧对象未删除，请调整素材或位置。"
	return ""
static func _update_entity(next: Dictionary, source: Dictionary, id: String, patch: Dictionary) -> Dictionary:
	for key in patch:
		if key not in EDITABLE: return _error("不可通过拖动改变对象身份、类型或资产版本："+str(key))
	for e in next.manual_entities:
		if e.entity_id==id:
			if e.get("locked",false): return _error("对象已锁定。")
			if patch.has("room_plan") and e.kind!="compound":return _error("只有房间／院落可以修改平面计划。")
			e.merge(patch.duplicate(true),true)
			return {"ok":true}
	var e:=find_entity(source,id).duplicate(true)
	if e.is_empty() or e.kind not in ["asset","compound"] or not e.has("recipe_id"): return _error("请选择一个可编辑的资产对象。")
	if patch.has("room_plan") and e.kind!="compound":return _error("只有房间／院落可以修改平面计划。")
	if e.get("locked",false):return _error("对象已锁定。")
	if e.get("role")=="role" and patch.has("ground_xy") and Paths.digest(patch.ground_xy)!=Paths.digest(e.ground_xy): return _error("关门／角楼角色锚定控制点；请先脱离，再手工移动。")
	e.merge(patch.duplicate(true),true);e.management="fixed"
	next.manual_overrides.fixed[Paths.candidate_key(e.recipe_id,e.candidate_id)]=e
	return {"ok":true}

static func apply(next: Dictionary, source: Dictionary, command: Dictionary) -> Dictionary:
	var op: String=str(command.get("op",""))
	match op:
		"transform_recipes", "transform_instance":
			var helper=preload("group_transform.gd");var issue: String=helper.options(command)
			if not issue.is_empty():return _error(issue)
			var recipe_ids: Array=command.get("recipe_ids",[]);var entity_ids: Array=[];var surface_ids: Array=[]
			if op=="transform_instance":
				var found:=false
				for group in next.prefab_instances:
					if group.instance_id==command.get("instance_id"):entity_ids=group.entity_ids;recipe_ids=group.recipe_ids;surface_ids=group.surface_ids;found=true;break
				if not found:return _error("组合不存在。")
			if recipe_ids.size()>64:return _error("一次最多变换64个配方。")
			var pivot:=Vector2(command.pivot[0],command.pivot[1]);var offset:=Vector2(command.offset[0],command.offset[1])
			issue=helper.surfaces(next,surface_ids,pivot,command.angle,command.factor,offset)
			if not issue.is_empty():return _error(issue)
			for id in recipe_ids:
				var r:=find_recipe(next,str(id))
				if r.is_empty():return _error("配方不存在。")
				issue=helper.recipe(r,pivot,command.angle,command.factor,offset)
				if not issue.is_empty():return _error(issue)
			for e in next.manual_overrides.fixed.values():
				if e.recipe_id not in recipe_ids:continue
				if e.get("locked",false):return _error("组合内有锁定生成对象。")
				e.ground_xy=helper.point(e.ground_xy,pivot,command.angle,command.factor,offset);e.orientation=fposmod(float(e.orientation)+float(command.angle),360);e.scale*=command.factor;e.local_height*=command.factor
			if not entity_ids.is_empty():
				var routed:=command.duplicate(true);routed.op="transform_entities";routed.entity_ids=entity_ids;var result:=apply(next,source,routed)
				if not result.ok:return result
		"set_entities_hidden":
			if not command.get("entity_ids") is Array or command.entity_ids.is_empty() or not command.get("hidden") is bool:return _error("先选择对象并指定隐藏开关。")
			for id in command.entity_ids:
				var result:=_update_entity(next,source,str(id),{"hidden":command.hidden})
				if not result.ok:return result
		"instantiate_template":
			if not command.get("template") is Dictionary or not command.get("ground_xy") is Array:return _error("模板／放置坐标无效。")
			return preload("template_library.gd").instantiate(next,command.template,command.ground_xy)
		"ungroup_instance":
			var id: String=str(command.get("instance_id",""));var size: int=next.prefab_instances.size()
			next.prefab_instances=next.prefab_instances.filter(func(g):return g.instance_id!=id)
			if size==next.prefab_instances.size():return _error("组合不存在。")
		"transform_entities":
			if not command.get("entity_ids") is Array or command.entity_ids.is_empty() or command.entity_ids.size()>2000 or not preload("asset_descriptor.gd").pair(command.get("pivot")) or not preload("asset_descriptor.gd").pair(command.get("offset")) or not preload("asset_descriptor.gd").numeric(command.get("angle")) or not preload("asset_descriptor.gd").numeric(command.get("factor")) or command.factor<=0:return _error("组合变换参数无效。")
			var used: Array=[];var pivot:=Vector2(command.pivot[0],command.pivot[1]);var offset:=Vector2(command.offset[0],command.offset[1])
			for id in command.entity_ids:
				if not id is String or id in used:return _error("组合选择重复或无效。")
				used.append(id);var e:=find_entity(source,id)
				if e.is_empty() or e.kind not in ["asset","compound","marker"]:return _error("组合只能变换可编辑对象，路径用配方编辑。")
				var point:=pivot+(Vector2(e.ground_xy[0],e.ground_xy[1])-pivot).rotated(deg_to_rad(command.angle))*float(command.factor)+offset
				var result:=_update_entity(next,source,id,{"ground_xy":[point.x,point.y],"scale":float(e.get("scale",1))*float(command.factor),"orientation":fposmod(float(e.get("orientation",0))+float(command.angle),360),"local_height":float(e.get("local_height",0))*float(command.factor)})
				if not result.ok:return result
		"set_editor_options":
			if not command.get("patch") is Dictionary:return _error("网格／图例参数无效。")
			for key in command.patch:
				if key not in ["grid_kind","grid_size","grid_visible","grid_snap","edge_snap","legend"]:return _error("未知网格／图例字段。")
			next.style_profile.merge(command.patch.duplicate(true),true)
		"add_recipe": next.recipes.append(command.get("recipe",{}).duplicate(true))
		"apply_brush":
			var recipe: Dictionary=command.get("recipe",{}).duplicate(true)
			if recipe.get("kind")!="brush":return _error("无效笔迹配方。")
			if recipe.get("brush_mode")=="erase" and recipe.get("erase_manual",false):
				var issue: String=preload("plot_generator.gd").validate(recipe,next)
				if not issue.is_empty():return _error(issue)
				next.manual_entities=next.manual_entities.filter(func(e):return e.kind!="asset" or e.get("locked",false) or not PlotGeometry.stroke_hits(source,e,recipe))
			next.recipes.append(recipe)
		"set_entity_locked":
			var id: String=str(command.get("entity_id",""))
			var locked: bool=bool(command.get("locked",true))
			var found:=false
			for e in next.manual_entities:
				if e.entity_id==id:e.locked=locked;found=true
			if not found:
				var e:=find_entity(source,id).duplicate(true)
				if e.is_empty() or e.kind not in ["asset","compound"] or not e.has("recipe_id"):return _error("请选择资产对象。")
				e.locked=locked;e.management="fixed"
				next.manual_overrides.fixed[Paths.candidate_key(e.recipe_id,e.candidate_id)]=e
		"set_recipe_locked":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty() or recipe.kind=="path":return _error("请选择区域或笔迹。")
			var locked: bool=bool(command.get("locked",true))
			if recipe.locked==locked:return {"ok":true}
			recipe.locked=locked
			if not locked:
				for key in next.manual_overrides.fixed.keys():
					var saved: Dictionary=next.manual_overrides.fixed[key]
					if saved.get("region_lock")!=recipe.recipe_id:continue
					if saved.get("prior_fixed",{}).is_empty():next.manual_overrides.fixed.erase(key)
					else:next.manual_overrides.fixed[key]=saved.prior_fixed.duplicate(true)
				return {"ok":true}
			for e in source.materialized_snapshot.entities:
				if e.get("recipe_id")==recipe.recipe_id and e.kind in ["asset","compound"]:
					var key:=Paths.candidate_key(e.recipe_id,e.candidate_id)
					var fixed: Dictionary=e.duplicate(true);fixed.management="fixed";fixed.locked=true;fixed.region_lock=recipe.recipe_id;fixed.prior_fixed=next.manual_overrides.fixed.get(key,{}).duplicate(true)
					next.manual_overrides.fixed[key]=fixed
		"update_recipe":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty(): return _error("配方不存在。")
			if recipe.get("locked",false):return _error("区域已锁定；请先明确解锁。")
			for key in command.get("patch",{}):
				if key in ["recipe_id","kind","control_points","segments","roles","locked"]: return _error("请用专门控制点／角色／锁定命令修改结构。")
			recipe.merge(command.get("patch",{}).duplicate(true),true)
		"update_path_point":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty(): return _error("配方不存在。")
			var point:=Paths.point_by_id(recipe,str(command.get("point_id","")))
			if point.is_empty(): return _error("控制点不存在。")
			for key in command.get("patch",{}):
				if key not in ["ground_xy","width"]: return _error("控制点身份不可改变。")
			point.merge(command.get("patch",{}).duplicate(true),true)
		"add_path_role":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty(): return _error("配方不存在。")
			var role: Dictionary=command.get("role",{}).duplicate(true)
			if recipe.roles.any(func(r):return r.get("point_id")==role.get("point_id")): return _error("此控制点已有角色；请先脱离原角色。")
			recipe.roles.append(role)
		"split_path_segment":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty(): return _error("配方不存在。")
			var segment_id: String=str(command.get("segment_id",""))
			if _protected_segment(next,recipe.recipe_id,[segment_id]): return _error("拆段涉及固定或删除意图，身份映射不明确；请先脱离固定对象或保留当前拓扑。")
			var found:=false
			for i in range(recipe.segments.size()):
				if recipe.segments[i].segment_id!=segment_id: continue
				var point_id: String=str(command.get("point_id","point_"+Crypto.new().generate_random_bytes(8).hex_encode()))
				var new_id: String="segment_"+Crypto.new().generate_random_bytes(8).hex_encode()
				var old_to: String=recipe.segments[i]["to"]
				recipe.segments[i]["to"]=point_id
				recipe.segments.insert(i+1,{"segment_id":new_id,"from":point_id,"to":old_to})
				recipe.control_points.insert(i+1,{"point_id":point_id,"ground_xy":command.get("ground_xy",[]).duplicate(),"width":(float(recipe.control_points[i].width)+float(recipe.control_points[i+1].width))*0.5})
				recipe.topology_mapping={segment_id:[segment_id,new_id]};found=true;break
			if not found: return _error("待拆路径段不存在。")
		"remove_path_point":
			var recipe:=find_recipe(next,str(command.get("recipe_id","")))
			if recipe.is_empty(): return _error("配方不存在。")
			var point_id: String=str(command.get("point_id",""))
			var index: int=recipe.control_points.find(Paths.point_by_id(recipe,point_id))
			if index<=0 or index>=recipe.control_points.size()-1: return _error("只可合并内部控制点；端点请直接移动。")
			if recipe.roles.any(func(r):return r.point_id==point_id): return _error("控制点包含固定角色；请先脱离角色。")
			var affected: Array=[recipe.segments[index-1].segment_id,recipe.segments[index].segment_id]
			if _protected_segment(next,recipe.recipe_id,affected): return _error("合段涉及固定或删除意图，不能无歧义映射。")
			recipe.segments[index-1]["to"]=recipe.segments[index]["to"]
			recipe.segments.remove_at(index);recipe.control_points.remove_at(index)
			recipe.topology_mapping={str(affected[0]):[affected[0]],str(affected[1]):[affected[0]]}
		"fix_entity":
			var e:=find_entity(source,str(command.get("entity_id",""))).duplicate(true)
			if e.is_empty() or e.kind not in ["asset","compound"] or not e.has("recipe_id") or e.management=="manual": return _error("请选择生成的资产子对象。")
			e.management="fixed"
			next.manual_overrides.fixed[Paths.candidate_key(e.recipe_id,e.candidate_id)]=e
		"delete_entity", "detach_entity":
			var id: String=str(command.get("entity_id",""))
			for i in range(next.manual_entities.size()):
				if next.manual_entities[i].entity_id==id:
					if op=="detach_entity": return _error("对象已经是手工对象。")
					if next.manual_entities[i].get("locked",false): return _error("对象已锁定。")
					next.manual_entities.remove_at(i);return {"ok":true}
			var e:=find_entity(source,id).duplicate(true)
			if e.is_empty() or e.kind not in ["asset","compound"] or not e.has("recipe_id"): return _error("请选择生成的资产对象；路径请在路径页编辑。")
			if e.get("locked",false):return _error("对象已锁定。")
			var key:=Paths.candidate_key(e.recipe_id,e.candidate_id)
			next.manual_overrides.fixed.erase(key)
			next.manual_overrides.tombstones[key]={"recipe_id":e.recipe_id,"candidate_id":e.candidate_id,"entity_id":e.entity_id,"segment_id":e.segment_id,"reason":"detached" if op=="detach_entity" else "deleted"}
			if op=="detach_entity":
				e.management="manual"
				next.manual_entities.append(e)
				next.manual_overrides.detached[key]=id
				if e.get("role")=="role":
					var recipe:=find_recipe(next,e.recipe_id)
					recipe.roles=recipe.roles.filter(func(r):return "role/"+r.role_id!=e.candidate_id)
		"update_entity": return _update_entity(next,source,str(command.get("entity_id","")),command.get("patch",{}))
		"snap_entity":
			var a:=find_entity(source,str(command.get("entity_id","")))
			var b:=find_entity(source,str(command.get("target_entity_id","")))
			if a.is_empty() or b.is_empty() or a.entity_id==b.entity_id: return _error("请选择两个不同的资产对象。")
			var result:=Geometry.snap(source,a,str(command.get("source_socket","")),b,str(command.get("target_socket","")))
			if not result.ok: return result
			return _update_entity(next,source,a.entity_id,{"ground_xy":result.ground_xy,"socket_binding":{"mode":"snap_once","target_entity_id":b.entity_id,"source_socket":command.source_socket,"target_socket":command.target_socket}})
		"remove_recipe":
			var id: String=str(command.get("recipe_id",""))
			if find_recipe(next,id).get("locked",false):return _error("区域已锁定；请先明确解锁。")
			if next.manual_overrides.fixed.values().any(func(e):return e.recipe_id==id): return _error("配方包含固定对象，请先脱离再删除配方。")
			if not command.get("confirmed",false): return _error("删除配方需要明确确认；可一次撤销。")
			next.recipes=next.recipes.filter(func(r):return r.recipe_id!=id)
		_: return _error("未知工坊命令。")
	return {"ok":true}
