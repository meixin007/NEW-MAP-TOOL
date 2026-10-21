@tool
extends RefCounted
## Durable authoring intent only. Threads, tokens and Callables are never saved.
const Model=preload("project_model.gd")
const OPS=["update_entity","update_path_point","update_recipe","add_recipe","apply_brush","add_terrain","update_terrain","add_path_role","add_manual"]
static func create(project: Dictionary,command: Dictionary,stage: String,signature: String="") -> Dictionary:
	return {"schema_version":1,"project_id":project.project_id,"base_input_hash":signature if not signature.is_empty() else Model.input_hash(project),"generator_version":Model.generator_version(project),"asset_versions_hash":Model.Canonical.digest(project.asset_refs),"command":command.duplicate(true),"stage":stage}
static func data_only(value: Variant,depth: int=0) -> bool:
	if depth>24:return false
	if value==null or value is bool:return true
	if value is String or value is StringName:return str(value).length()<=65536
	if value is int or value is float:return Model.numeric(value)
	if value is Array:
		if value.size()>4096:return false
		for item in value:
			if not data_only(item,depth+1):return false
		return true
	if value is Dictionary:
		if value.size()>4096:return false
		for key in value:
			if (not key is String and not key is StringName) or not data_only(value[key],depth+1):return false
		return true
	return false
static func validate(value: Variant,project: Dictionary) -> String:
	if not value is Dictionary:return "恢复修改意图必须为字典。"
	if value.is_empty():return ""
	if not data_only(value):return "恢复修改意图包含不支持的值。"
	if value.get("schema_version")!=1 or value.get("stage") not in ["dragging","validating","ready"]:return "恢复修改意图版本或阶段无效。"
	if value.get("project_id")!=project.project_id or value.get("base_input_hash")!=Model.input_hash(project):return "恢复修改的基准项目已改变，未采用。"
	if value.get("generator_version")!=Model.generator_version(project) or value.get("asset_versions_hash")!=Model.Canonical.digest(project.asset_refs):return "恢复修改的生成器或资产版本已改变，未采用。"
	var command: Variant=value.get("command")
	if not command is Dictionary or command.get("op") not in OPS:return "恢复修改命令不受支持。"
	if JSON.stringify(command).length()>2*1024*1024:return "恢复修改命令超过限制。"
	var fields: Dictionary={"update_entity":{"entity_id":TYPE_STRING,"patch":TYPE_DICTIONARY},"update_path_point":{"recipe_id":TYPE_STRING,"point_id":TYPE_STRING,"patch":TYPE_DICTIONARY},"update_recipe":{"recipe_id":TYPE_STRING,"patch":TYPE_DICTIONARY},"add_recipe":{"recipe":TYPE_DICTIONARY},"apply_brush":{"recipe":TYPE_DICTIONARY},"add_terrain":{"surface":TYPE_DICTIONARY},"update_terrain":{"surface_id":TYPE_STRING,"patch":TYPE_DICTIONARY},"add_path_role":{"recipe_id":TYPE_STRING,"role":TYPE_DICTIONARY},"add_manual":{"entity":TYPE_DICTIONARY}}
	for key in fields[command.op]:
		if not command.has(key) or typeof(command[key])!=fields[command.op][key]:return "恢复修改命令字段无效："+key
	# Full shape, geometry, lock and protection checks run again in _candidate.
	for key in ["entity_id","recipe_id","point_id","surface_id"]:
		if command.has(key) and (not command[key] is String or command[key].is_empty() or command[key].length()>256):return "恢复修改目标身份无效。"
	return ""
