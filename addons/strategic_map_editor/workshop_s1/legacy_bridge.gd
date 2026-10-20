@tool
extends RefCounted
const Doc = preload("../document.gd")
const WaterBrush = preload("../water_brush.gd")

static func import_rivers(project: Dictionary, value: Dictionary) -> Dictionary:
	if not project.legacy_document.features.is_empty(): return {"ok":false,"error":"此项目已有旧文档桥接内容，请在空项目导入，避免替换已有逻辑。"}
	var validator:=Doc.new()
	var issue: String=validator.validate(value)
	if not issue.is_empty(): return {"ok":false,"error":issue}
	if not value.presentation.instances.is_empty(): return {"ok":false,"error":"旧图含其他美术；本批仅适配河流和注记，请在原模式继续其他表现。"}
	var recipes: Array=[]
	for feature in value.features:
		if feature.kind=="label": continue
		if not WaterBrush.is_river(feature): return {"ok":false,"error":"旧图包含未适配表现类型："+str(feature.kind)+"；没有丢弃或覆盖该地图，请用原模式打开。"}
		var ribbon: Dictionary=WaterBrush.ribbon(feature)
		var points: Array=[]
		var segments: Array=[]
		for i in range(ribbon.points.size()):
			var id: String="legacy_point_"+(str(feature.id)+":"+str(i)).sha256_text().substr(0,20)
			points.append({"point_id":id,"ground_xy":ribbon.points[i].duplicate(),"width":float(ribbon.widths[i])})
			if i>0: segments.append({"segment_id":"legacy_segment_"+(str(feature.id)+":"+str(i-1)).sha256_text().substr(0,20),"from":points[i-1].point_id,"to":id})
		recipes.append({"recipe_id":"legacy_river_"+str(feature.id).sha256_text().substr(0,20),"kind":"path","path_type":"river","name":str(feature.name),"control_points":points,"segments":segments,"seed":0,"surface_id":"ground","style":"water","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":feature.id,"legacy_source_hash":Doc.canonical_digest(feature)})
	project.legacy_document=value.duplicate(true)
	project.recipes.append_array(recipes)
	return {"ok":true}

static func apply(project: Dictionary, command: Dictionary) -> Dictionary:
	# Temporary validator/projection, never retained as a second history owner.
	var validator := Doc.new()
	var issue: String = validator.load_text(JSON.stringify(project.legacy_document))
	if not issue.is_empty(): return {"ok":false,"error":issue}
	var id: String = validator.add_feature(str(command.get("kind","label")), command.get("points",[]),str(command.get("label","注记")))
	if id.is_empty(): return {"ok":false,"error":"旧文档桥接命令不合法。"}
	project.legacy_document = validator.snapshot()
	validator.undo_stack.clear()
	validator.redo_stack.clear()
	return {"ok":true,"entity_id":id}
