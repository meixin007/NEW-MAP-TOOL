@tool
extends RefCounted
const A=preload("asset_descriptor.gd")
const D=preload("district_generator.gd")
const ROOM_NUMBERS=["room_x","room_y","room_w","room_d","wall_height","roof_rise","door_edge","door_width","outer_height","opening_at","opening_width","opening_height","floor_x","floor_y"]
const DISTRICT_NUMBERS=["density","vacancy","future","seed","cell_x","cell_y","plot_w","plot_d","street_width","safety","point_x","point_y"]
static func numbers(d: Dictionary,keys: Array) -> String:
	if not d.get("values",{}) is Dictionary or not d.get("raw_numbers",{}) is Dictionary:return "恢复 W5 数字字典无效。"
	for key in d.get("values",{}):
		if key not in keys or not A.numeric(d.values[key]) or absf(float(d.values[key]))>1000000000:return "恢复 W5 数字字段无效。"
	for key in d.get("raw_numbers",{}):
		if key not in keys or not d.raw_numbers[key] is String or d.raw_numbers[key].length()>256:return "恢复 W5 数字草稿无效。"
	return ""
static func selectors(d: Dictionary,items: Array) -> String:
	for item in items:
		if d.has(item[0]) and (not A.numeric(d[item[0]]) or float(d[item[0]])!=floorf(float(d[item[0]])) or float(d[item[0]])<item[1] or float(d[item[0]])>item[2]):return "恢复 W5 选择越界。"
	return ""
static func closed(d: Dictionary,keys: Array) -> String:
	for key in d:
		if key not in keys:return "未知 W5 恢复字段："+str(key)
	return ""
static func validate(draft: Dictionary,p: Dictionary) -> String:
	for group in ["room_fields","district_fields","w5_canvas"]:
		if draft.has(group) and not draft[group] is Dictionary:return "恢复 W5 草稿类型无效。"
	var r: Dictionary=draft.get("room_fields",{});var d: Dictionary=draft.get("district_fields",{});var c: Dictionary=draft.get("w5_canvas",{})
	for issue in [closed(r,["selected_id","pending_id","dirty","wall_dirty","values","raw_numbers","kind","function","material","roof","room_roof","roof_style","wall_style","room_index","wall_index"]),closed(d,["recipe_id","pending_id","lot_id","dirty","values","raw_numbers","parameters","job_command","lot_role","point_index"]),closed(c,["compound_points","district_points","compound_target_id","show_lots","preview_owner"]),numbers(r,ROOM_NUMBERS),numbers(d,DISTRICT_NUMBERS),selectors(r,[["kind",0,1],["function",0,2],["roof_style",0,2],["wall_style",0,2],["room_index",0,15],["wall_index",0,31]]),selectors(d,[["lot_role",0,2],["point_index",-1,127]])]:
		if not issue.is_empty():return issue
	for group in [r,d,c]:
		for key in group:
			if key in ["selected_id","pending_id","recipe_id","lot_id","material","compound_target_id","preview_owner"] and (not group[key] is String or group[key].length()>512):return "恢复 W5 身份无效。"
			if key in ["dirty","wall_dirty","roof","room_roof","show_lots"] and not group[key] is bool:return "恢复 W5 开关无效。"
	if not r.get("material","").is_empty() and not p.asset_refs.has(r.material):return "恢复院落材质缺失。"
	if c.get("preview_owner","plot") not in ["plot","district"]:return "恢复计算归属无效。"
	for key in ["compound_points","district_points"]:
		if not c.get(key,[]) is Array or c.get(key,[]).size()>(2 if key=="compound_points" else 128):return "恢复 W5 轮廓过长。"
		for point in c.get(key,[]):
			if not A.pair(point):return "恢复 W5 坐标无效。"
	var params: Variant=d.get("parameters",{});var command: Variant=d.get("job_command",{})
	if not params is Dictionary or not command is Dictionary:return "恢复街区参数无效。"
	if not params.is_empty():
		var issue:=closed(params,["layout","function","density","vacancy","future_fraction","seed","cell_size","courtyard_size","street_width","safety_margin","main_road_ids","roof_material"])
		if not issue.is_empty():return issue
		if params.get("layout") not in ["orthogonal","along_road"] or params.get("function") not in ["residential","market","storage"]:return "恢复街区类型无效。"
		for key in ["density","vacancy","future_fraction","seed","street_width","safety_margin"]:
			if not A.numeric(params.get(key)):return "恢复街区数字参数无效。"
		for key in ["cell_size","courtyard_size"]:
			if not A.pair(params.get(key)):return "恢复街区尺寸无效。"
		if not params.get("main_road_ids") is Array or params.main_road_ids.size()>16 or not params.get("roof_material") is String:return "恢复街区引用无效。"
		for id in params.main_road_ids:
			if not id is String:return "恢复街区道路身份无效。"
	if not command.is_empty():
		if command.get("op")=="add_recipe" and command.get("recipe") is Dictionary:
			return D.validate(command.recipe,p)
		if command.get("op")!="update_recipe" or not command.get("recipe_id") is String or not command.get("patch") is Dictionary:return "恢复街区计算意图无效。"
		for recipe in p.recipes:
			if recipe.recipe_id==command.recipe_id and recipe.kind=="district":
				var next: Dictionary=recipe.duplicate(true);next.merge(command.patch,true);return D.validate(next,p)
		return "恢复街区计算所指配方缺失。"
	return ""
