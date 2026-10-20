@tool
extends RefCounted
## All project edits pass through candidate -> validation -> materialization -> one commit.
signal changed
signal history_trimmed(message: String)
const Model = preload("project_model.gd")
const Bridge = preload("legacy_bridge.gd")
const Commands = preload("project_commands.gd")
const HISTORY_LIMIT := 50
const HISTORY_BYTES := 256 * 1024 * 1024
var _project: Dictionary = Model.blank()
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var _draft: Dictionary = {}
var _saved_signature := ""
var current_path := ""
var read_only := false
var revision := 0
var view_revision: int=0
var recovered_draft: Dictionary = {}
var _replace_file := Callable() # Injectable file-system boundary for failure regression.
var asset_blobs: Dictionary = {}
var dependency_issues: Array[String] = []
var _signature_revision: int=-1
var _author_signature: String=""
var _history_sizes: Dictionary={}
var _worker: Thread
var _job_token:=0
var _worker_token: int=-1
var _job_revision: int=-1
var _job_started_ms:=0
var _job_command: Dictionary={}

func job_in_progress() -> bool:
	return _worker!=null and _worker_token==_job_token
func start_preview_job(command: Dictionary) -> Dictionary:
	if read_only or has_preview():return _error("请先取消或应用预览，且项目必须可编辑。")
	if _worker!=null:
		if _worker.is_alive():return _error("上一项计算正在收尾；可先继续编辑，稍后再预览。")
		_worker.wait_to_finish();_worker=null
	_job_token+=1;_worker_token=_job_token;_job_revision=revision;_job_started_ms=Time.get_ticks_msec();_job_command=command.duplicate(true)
	var source:=snapshot();var frozen:=command.duplicate(true)
	_worker=Thread.new()
	var err:=_worker.start(_candidate.bind(source,frozen))
	if err!=OK:_worker=null;return _error("无法启动区域预览："+error_string(err))
	return {"ok":true,"token":_job_token}
func poll_preview_job() -> Dictionary:
	if _worker==null:return {"status":"idle"}
	if _worker.is_alive():return {"status":"working","stage":"1/2 验证与构建候选","elapsed_ms":Time.get_ticks_msec()-_job_started_ms,"cancelled":_worker_token!=_job_token}
	var value: Variant=_worker.wait_to_finish();_worker=null
	if not value is Dictionary or not value.get("ok") is bool:return {"status":"failed","error":"计算没有返回合法候选；正式项目未修改。"}
	var result: Dictionary=value
	if _worker_token!=_job_token or revision!=_job_revision or has_preview() or read_only:return {"status":"discarded","message":"过期／已取消的候选已丢弃。"}
	if not result.ok:return {"status":"failed","error":result.error}
	_draft=result.project;view_revision+=1
	return {"status":"ready","stage":"2/2 候选完成，待明确应用","candidate_count":_draft.materialized_snapshot.get("stats",{}).get("candidate_count",0),"elapsed_ms":Time.get_ticks_msec()-_job_started_ms}
func cancel_preview_job() -> void:
	_job_token+=1
func shutdown_jobs() -> void:
	cancel_preview_job()
	if _worker!=null:_worker.wait_to_finish();_worker=null

func snapshot() -> Dictionary:
	return _project.duplicate(true)

func is_dirty() -> bool:
	return authority_signature() != _saved_signature
func authority_signature() -> String:
	if _signature_revision!=revision:
		_author_signature=Model.input_hash(_project);_signature_revision=revision
	return _author_signature

func has_preview() -> bool:
	return not _draft.is_empty()

func preview_snapshot() -> Dictionary:
	return _draft.duplicate(true) if not _draft.is_empty() else snapshot()

func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func _candidate(source: Dictionary, command: Dictionary) -> Dictionary:
	var next := source.duplicate(true)
	match command.get("op", ""):
		"add_manual": next.manual_entities.append(command.get("entity",{}).duplicate(true))
		"update_manual", "delete_manual":
			if not next.manual_entities.any(func(e): return e.entity_id==command.get("entity_id")): return _error("手工对象不存在。")
			var routed:=command.duplicate(true)
			routed.op="delete_entity" if command.op=="delete_manual" else "update_entity"
			var result:=Commands.apply(next,source,routed)
			if not result.ok: return result
		"rename": next.title = command.get("title", "")
		"update_label", "delete_label":
			var found:=false
			for feature in next.legacy_document.features:
				if feature.id!=command.get("feature_id") or feature.kind!="label":continue
				if feature.get("locked",false):return _error("标签已锁定。")
				found=true
				if command.op=="update_label":
					if not command.get("label") is String or command.label.is_empty() or not Model.pair(command.get("ground_xy")):return _error("标签文本或坐标无效。")
					feature.name=command.label;feature.points=[command.ground_xy.duplicate()]
			if not found:return _error("标签不存在。")
			if command.op=="delete_label":next.legacy_document.features=next.legacy_document.features.filter(func(f):return f.id!=command.feature_id)
		"set_reference_projection":
			next.style_profile.ground_matrix=[1.0,0.14,-0.30,0.72]
			next.style_profile.height_axis=[0.0,-1.0]
			next.style_profile.style_id="reference_oblique_w5_pending"
		"set_paper_color":
			var color: String=str(command.get("color",""))
			if not Color.html_is_valid(color):return _error("纸色不是有效颜色。")
			next.style_profile.paper_color=color
		"add_assets":
			if not command.get("assets") is Dictionary: return _error("资产批次无效。")
			for key in command.assets:
				if next.asset_refs.has(key): return _error("资产版本已存在，不会覆盖。")
				next.asset_refs[key] = command.assets[key].duplicate(true)
		"add_terrain", "update_terrain", "delete_terrain", "lock_terrain":
			var result:=Model.Terrain.command(next,command)
			if not result.ok:return result
		"add_surface_prototype":
			next.surfaces.append(command.get("surface",{}).duplicate(true))
		"add_asset_version":
			var a: Dictionary = command.get("descriptor",{}).duplicate(true)
			var issue := Model.Asset.validate(a)
			if not issue.is_empty(): return _error(issue)
			var key := Model.Asset.key(a)
			if next.asset_refs.has(key): return _error("资产版本已存在，未覆盖。")
			next.asset_refs[key]=a
			for id in command.get("adopt_entity_ids",[]):
				var found := false
				for e in next.manual_entities:
					if e.entity_id==id and e.kind=="asset": e.asset_ref=key;found=true
				if not found: return _error("所选对象不可直接更新资产；请先脱离生成器。")
		"update_surface_prototype":
			var found := false
			for surface in next.surfaces:
				if surface.surface_id == command.get("surface_id") and surface.surface_id != "ground":
					surface.merge(command.get("patch",{}).duplicate(true),true)
					found = true
			if not found: return _error("高面原型不存在或试图修改 ground。")
		"legacy_add_feature":
			var result := Bridge.apply(next,command)
			if not result.ok: return result
		"import_legacy_rivers":
			if not command.get("legacy_document") is Dictionary: return _error("旧 v4 文档无效。")
			var result:=Bridge.import_rivers(next,command.legacy_document)
			if not result.ok: return result
		_:
			var result:=Commands.apply(next,source,command)
			if not result.ok: return result
	if command.get("op") in ["rename","set_paper_color","set_editor_options"]:
		# _candidate only receives the session's already validated immutable authority.
		# These commands cannot alter geometry, asset versions, support or dependencies.
		if not next.title is String or next.title.is_empty():return _error("项目名称不能为空。")
		var style_issue: String=preload("editor_contract.gd").validate_style(next.style_profile)
		if not style_issue.is_empty():return _error(style_issue)
		next.materialized_snapshot.input_hash=Model.input_hash(next);next.materialized_snapshot.generator_version=Model.generator_version(next)
		return {"ok":true,"project":next}
	preload("editor_contract.gd").prune_groups(next)
	var issue := Model.validate(next)
	if not issue.is_empty(): return _error(issue)
	issue=Commands.check_protection_delta(source,next,command)
	if not issue.is_empty(): return _error(issue)
	next.materialized_snapshot = Model.materialize(next)
	if next.materialized_snapshot.get("ok",true)==false: return _error(str(next.materialized_snapshot.error))
	issue=Model.validate(next)
	if not issue.is_empty(): return _error(issue)
	return {"ok":true,"project":next}

func dispatch(command: Dictionary) -> Dictionary:
	if read_only: return _error("此项目处于只读状态。")
	if has_preview(): return _error("请先提交或取消画布预览。")
	var candidate := _candidate(_project,command)
	if not candidate.ok: return candidate
	return _commit(candidate.project,false,candidate.project.materialized_snapshot.input_hash)

func _commit(next: Dictionary, force_cache: bool=false,verified_signature: String="") -> Dictionary:
	var next_signature: String=verified_signature if not verified_signature.is_empty() else Model.input_hash(next)
	if not force_cache and next_signature == authority_signature(): return {"ok":true,"changed":false}
	cancel_preview_job()
	undo_stack.append(snapshot())
	redo_stack.clear()
	var total := 0
	for old in undo_stack:
		var key: String=old.materialized_snapshot.input_hash
		if not _history_sizes.has(key):_history_sizes[key]=JSON.stringify(old).to_utf8_buffer().size()
		total+=int(_history_sizes[key])
	var trimmed := false
	while undo_stack.size() > HISTORY_LIMIT or (total > HISTORY_BYTES and undo_stack.size() > 1):
		var removed: Dictionary=undo_stack.pop_front()
		total-=int(_history_sizes.get(removed.materialized_snapshot.input_hash,0))
		trimmed = true
	if trimmed: history_trimmed.emit("撤销历史超过 50 次或 256MiB，已裁剪最早记录；项目保存不受影响。")
	_project = next.duplicate(true)
	revision += 1
	_author_signature=next_signature;_signature_revision=revision
	changed.emit()
	return {"ok":true,"changed":true}

func begin_preview() -> void:
	view_revision+=1
	if not read_only: _draft = snapshot()

func preview(command: Dictionary) -> Dictionary:
	view_revision+=1
	if read_only or _draft.is_empty(): return _error("未开始预览。")
	var candidate := _candidate(_project,command)
	if candidate.ok: _draft = candidate.project
	return candidate

func cancel_preview() -> void:
	view_revision+=1
	cancel_preview_job()
	_draft.clear()

func commit_preview() -> Dictionary:
	view_revision+=1
	if read_only or _draft.is_empty(): return _error("没有可提交预览。")
	var next := _draft
	_draft = {}
	return _commit(next)

func restore_preview(candidate: Dictionary) -> Dictionary:
	view_revision+=1
	var issue:=Model.validate(candidate)
	if not issue.is_empty():return _error(issue)
	if candidate.project_id!=_project.project_id or Model.Paths.digest(candidate.asset_refs)!=Model.Paths.digest(_project.asset_refs):return _error("恢复预览与当前项目或固定资产不匹配。")
	if candidate.materialized_snapshot.generator_version!=Model.generator_version(candidate) or candidate.materialized_snapshot.input_hash!=Model.input_hash(candidate):return _error("恢复预览已经过期，请重新计算。")
	var fresh:=candidate.duplicate(true);fresh.materialized_snapshot={}
	var expected:=Model.materialize(fresh)
	if expected.get("ok",true)==false or Model.Paths.digest(expected.entities)!=Model.Paths.digest(candidate.materialized_snapshot.entities):return _error("恢复预览派生输出不一致，未采用。")
	if Model.Paths.digest(expected.get("lots",[]))!=Model.Paths.digest(candidate.materialized_snapshot.get("lots",[])):return _error("恢复预览地块与权威输入不一致。")
	_draft=candidate.duplicate(true)
	return {"ok":true}

func undo() -> bool:
	if has_preview() or undo_stack.is_empty(): return false
	redo_stack.append(snapshot())
	_project = undo_stack.pop_back()
	_sync_read_only()
	revision += 1
	changed.emit()
	return true

func redo() -> bool:
	if has_preview() or redo_stack.is_empty(): return false
	undo_stack.append(snapshot())
	_project = redo_stack.pop_back()
	_sync_read_only()
	revision += 1
	changed.emit()
	return true

func replace_project(next: Dictionary) -> Dictionary:
	cancel_preview_job()
	var issue := Model.validate(next)
	if not issue.is_empty(): return _error(issue)
	if next.materialized_snapshot.get("input_hash","")==Model.input_hash(next) and next.materialized_snapshot.get("generator_version","")==Model.generator_version(next):
		var fresh:=next.duplicate(true)
		fresh.materialized_snapshot={}
		var expected:=Model.materialize(fresh)
		if expected.get("ok",true)==false: return _error(str(expected.error))
		if Model.Paths.digest(expected.entities)!=Model.Paths.digest(next.materialized_snapshot.entities): return _error("派生快照与同版本权威输入不一致，未采用。")
		if Model.Paths.digest(expected.get("lots",[]))!=Model.Paths.digest(next.materialized_snapshot.get("lots",[])):return _error("派生地块与同版本权威输入不一致，未采用。")
		next=next.duplicate(true)
		next.materialized_snapshot.recipe_cache=expected.recipe_cache
	_project = next.duplicate(true)
	undo_stack.clear();_history_sizes.clear()
	redo_stack.clear()
	_draft.clear()
	dependency_issues.clear()
	_sync_read_only()
	revision += 1
	changed.emit()
	return {"ok":true,"read_only":read_only}

func _sync_read_only() -> void:
	read_only=not dependency_issues.is_empty() or _project.materialized_snapshot.get("input_hash","")!=Model.input_hash(_project) or _project.materialized_snapshot.get("generator_version","")!=Model.generator_version(_project)

func rebuild_derived() -> Dictionary:
	if has_preview(): return _error("请先取消或应用预览。")
	if not current_path.is_empty():
		dependency_issues=check_dependencies(current_path.get_base_dir())
		if not dependency_issues.is_empty(): return _error("依赖仍缺失／错 hash，不能重建。")
	var next:=snapshot()
	next.materialized_snapshot={}
	var issue:=Model.validate(_project)
	if not issue.is_empty(): return _error(issue)
	next.materialized_snapshot=Model.materialize(next)
	if next.materialized_snapshot.get("ok",true)==false: return _error(str(next.materialized_snapshot.error))
	issue=Model.validate(next)
	if not issue.is_empty(): return _error(issue)
	read_only=false
	var result:=_commit(next,true)
	if result.ok: _saved_signature=""
	return result

func load_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary: return _error("项目 JSON 无法读取。")
	var result := replace_project(json.data)
	if result.ok: _saved_signature = Model.input_hash(_project)
	return result

func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return _error("项目文件不存在。")
	var result := load_text(FileAccess.get_file_as_string(path))
	if result.ok:
		current_path = path
		asset_blobs.clear()
		dependency_issues = check_dependencies(path.get_base_dir())
		if not dependency_issues.is_empty(): read_only=true
		result.read_only = read_only
		result.dependency_issues = dependency_issues.duplicate()
	return result

func check_dependencies(base_dir: String) -> Array[String]:
	var issues: Array[String] = []
	for a in _project.asset_refs.values():
		var file: String = base_dir.path_join(a.texture_ref)
		if not FileAccess.file_exists(file): issues.append("缺少资产："+a.texture_ref)
		elif FileAccess.get_sha256(file) != a.texture_sha256: issues.append("资产 hash 不符："+a.texture_ref)
	return issues

func asset_bytes(a: Dictionary) -> PackedByteArray:
	if asset_blobs.has(a.texture_sha256): return asset_blobs[a.texture_sha256]
	if not current_path.is_empty():
		var source: String = current_path.get_base_dir().path_join(a.texture_ref)
		if FileAccess.file_exists(source) and FileAccess.get_sha256(source)==a.texture_sha256: return FileAccess.get_file_as_bytes(source)
	return PackedByteArray()

func save_template(path: String,template: Dictionary,preview: PackedByteArray) -> Dictionary:
	if not path.ends_with(".shtemplate.json") or FileAccess.file_exists(path):return _error("模板须另存为新的 .shtemplate.json；旧版本不覆盖。")
	var value:=template.duplicate(true);var issue: String=preload("template_library.gd").validate(value)
	if not issue.is_empty():return _error(issue)
	var assets:=_save_assets(path,value.asset_refs)
	if not assets.ok:return assets
	var preview_path: String=path.get_base_dir().path_join(value.preview_ref)
	if preview.is_empty() or FileAccess.file_exists(preview_path):return _error("模板预览缺失或与已有文件重名，请另存目录／版本。")
	var f:=FileAccess.open(preview_path,FileAccess.WRITE)
	if f==null:return _error("模板预览不能写入。")
	f.store_buffer(preview);f.flush();var result:=f.get_error();f.close()
	if result!=OK:DirAccess.remove_absolute(preview_path);return _error("模板预览写入不完整。")
	var saved:=_atomic_write(path,value)
	if not saved.ok:DirAccess.remove_absolute(preview_path)
	return saved
func read_template(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return _error("模板文件不存在。")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _error("模板文件不能读取。")
	if file.get_length()>16*1024*1024:file.close();return _error("模板超过16MiB限制。")
	var json:=JSON.new();var text:=file.get_as_text();file.close()
	if json.parse(text)!=OK or not json.data is Dictionary:return _error("模板 JSON 无效。")
	var template: Dictionary=json.data;var issue: String=preload("template_library.gd").validate(template)
	if not issue.is_empty():return _error(issue)
	var blobs: Dictionary={}
	for a in template.asset_refs.values():
		var dependency: String=path.get_base_dir().path_join(a.texture_ref)
		if not FileAccess.file_exists(dependency) or FileAccess.get_sha256(dependency)!=a.texture_sha256:return _error("模板素材缺失或版本不同："+a.label)
		blobs[a.texture_sha256]=FileAccess.get_file_as_bytes(dependency)
	if not FileAccess.file_exists(path.get_base_dir().path_join(template.preview_ref)):return _error("模板预览文件缺失。")
	asset_blobs.merge(blobs,true)
	return {"ok":true,"template":template}

func _save_assets(path: String,extra: Dictionary={}) -> Dictionary:
	var resources: Array=_project.asset_refs.values()+extra.values()
	for a in resources:
		var target := ProjectSettings.globalize_path(path.get_base_dir().path_join(a.texture_ref))
		if FileAccess.file_exists(target):
			if FileAccess.get_sha256(target)!=a.texture_sha256: return _error("已有内容寻址文件损坏；未覆盖："+target)
			continue
		var bytes := asset_bytes(a)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if bytes.is_empty() or hash.finish().hex_encode()!=a.texture_sha256: return _error("缺少正确版本的素材，项目清单未写入："+a.label)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK: return _error("无法建立项目资产目录。")
		var temp := target+"."+Model.new_id("blob")+".tmp"
		var file := FileAccess.open(temp,FileAccess.WRITE)
		if file == null: return _error("无法写入项目资产。")
		file.store_buffer(bytes)
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error!=OK or FileAccess.get_sha256(temp)!=a.texture_sha256:
			DirAccess.remove_absolute(temp)
			return _error("项目资产写入核验失败。")
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(temp)
			if FileAccess.get_sha256(target)!=a.texture_sha256: return _error("项目资产写入存在版本冲突。")
		elif DirAccess.rename_absolute(temp,target)!=OK:
			DirAccess.remove_absolute(temp)
			return _error("项目资产无法原子采用。")
	return {"ok":true}

static func _safe_target(path: String) -> bool:
	return not path.replace("\\","/").split("/").has("..") and not path.get_file().is_empty()

static func _atomic_write(path: String, value: Dictionary, replace_file: Callable = Callable()) -> Dictionary:
	if not _safe_target(path): return {"ok":false,"error":"保存路径含有非法相对跳转。"}
	var dir := ProjectSettings.globalize_path(path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK: return {"ok":false,"error":"无法创建项目目录："+error_string(err)}
	var target := ProjectSettings.globalize_path(path)
	var temp := target + "." + Model.new_id("write") + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return {"ok":false,"error":"无法写入项目："+error_string(FileAccess.get_open_error())}
	var content := JSON.stringify(value,"\t",false,true)
	file.store_string(content)
	file.flush()
	err = file.get_error()
	file.close()
	if err != OK or FileAccess.get_file_as_string(temp) != content:
		DirAccess.remove_absolute(temp)
		return {"ok":false,"error":"写入不完整，原项目保留。"}
	err = int(replace_file.call(temp,target)) if replace_file.is_valid() else DirAccess.rename_absolute(temp,target)
	if err != OK:
		DirAccess.remove_absolute(temp)
		return {"ok":false,"error":"原子替换失败，原项目保留："+error_string(err)}
	return {"ok":true,"path":path}

func save_file(path: String) -> Dictionary:
	if not path.ends_with(".shwork.json"): return _error("工坊项目须另存为 .shwork.json，不能覆盖旧 v4 .map.json。")
	if has_preview(): return _error("请先提交或取消预览；未覆盖保存文件。")
	if not _safe_target(path): return _error("保存路径含有非法相对跳转。")
	var issue := Model.validate(_project)
	if not issue.is_empty(): return _error(issue)
	var assets := _save_assets(path)
	if not assets.ok: return assets
	var result := _atomic_write(path,_project,_replace_file)
	if result.ok:
		current_path = path
		_saved_signature = Model.input_hash(_project)
		changed.emit()
	return result

func save_recovery(path: String, draft: Dictionary) -> Dictionary:
	var issue:=_validate_recovery_draft(draft,_project)
	if not issue.is_empty():return _error(issue)
	var assets := _save_assets(path,preload("editor_draft.gd").resources(draft))
	if not assets.ok: return assets
	return _atomic_write(path,{"document_type":"shanhe.workshop_recovery","schema_version":1,"project":snapshot(),"draft":draft.duplicate(true),"saved_path":current_path})

func load_recovery(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary: return _error("恢复文件无法读取。")
	var value: Dictionary = json.data
	if value.get("document_type") != "shanhe.workshop_recovery" or value.get("schema_version") != 1 or not value.get("project") is Dictionary or not value.get("draft") is Dictionary: return _error("未知恢复协议。")
	var draft_issue:=_validate_recovery_draft(value.draft,value.project)
	if not draft_issue.is_empty(): return _error(draft_issue)
	var result := replace_project(value.project)
	if result.ok:
		recovered_draft = value.draft.duplicate(true)
		current_path = str(value.get("saved_path",""))
		_saved_signature = ""
		# Recovery keeps its own adjacent immutable assets, independent of saved_path.
		var dependencies: Array=_project.asset_refs.values()+preload("editor_draft.gd").resources(value.draft).values()
		for a in dependencies:
			var resource_path: String = path.get_base_dir().path_join(a.texture_ref)
			if FileAccess.file_exists(resource_path) and FileAccess.get_sha256(resource_path)==a.texture_sha256: asset_blobs[a.texture_sha256]=FileAccess.get_file_as_bytes(resource_path)
			else: read_only=true;dependency_issues.append("恢复副本缺少正确素材："+a.texture_ref)
	return result

static func _validate_recovery_draft(draft: Dictionary, project: Dictionary) -> String:
	var editor_issue: String=preload("editor_draft.gd").validate(draft)
	if not editor_issue.is_empty():return editor_issue
	var w5_issue: String=preload("w5_draft.gd").validate(draft,project)
	if not w5_issue.is_empty():return w5_issue
	if draft.has("pan") and not Model.pair(draft.pan): return "恢复视角无效。"
	if draft.has("zoom") and (not Model.numeric(draft.zoom) or float(draft.zoom)<=0 or float(draft.zoom)>6): return "恢复倍率无效。"
	for group in ["fields","path_fields"]:
		if not draft.has(group): continue
		if not draft[group] is Dictionary: return "恢复属性字典无效。"
		for field in ["x","y","width","scale","orientation","seed","style"]:
			if draft[group].has(field) and not Model.numeric(draft[group][field]): return "恢复属性数字无效："+field
	for name in ["path_draft","preview","asset_editor","plot_draft","plot_fields"]:
		if draft.has(name) and not draft[name] is Dictionary: return "恢复草稿类型无效："+name
	for name in ["terrain_draft","terrain_fields"]:
		if draft.has(name) and not draft[name] is Dictionary:return "恢复地形草稿必须为字典。"
	if draft.has("terrain_draft"):
		var d: Dictionary=draft.terrain_draft
		if not d.get("points",[]) is Array or d.get("points",[]).size()>128:return "恢复台地轮廓过长。"
		for point in d.get("points",[]):
			if not Model.pair(point):return "恢复台地坐标无效。"
		for key in ["parent","from","to","selected_id"]:
			if d.has(key) and not d[key] is String:return "恢复地形面身份无效。"
		if d.has("automatic_surface") and not d.automatic_surface is bool:return "恢复自动选面值无效。"
	if draft.has("terrain_fields"):
		var d: Dictionary=draft.terrain_fields
		if not d.get("values",{}) is Dictionary or not d.get("raw_numbers",{}) is Dictionary:return "恢复地形属性无效。"
		for key in d.get("values",{}):
			if key not in ["height","spread","direction","gradient","vertex_x","vertex_y","ramp_width","start_x","start_y","end_x","end_y"] or not Model.numeric(d.values[key]):return "恢复地形数字字段无效。"
		for key in d.get("raw_numbers",{}):
			if key not in d.get("values",{}) or not d.raw_numbers[key] is String or d.raw_numbers[key].length()>256:return "恢复地形数字草稿文本无效。"
		for key in ["selected_id","pending_id","parent","from","to","top_color","edge_color"]:
			if d.has(key) and (not d[key] is String or d[key].length()>256):return "恢复地形文本字段无效。"
		for key in ["dirty","point_dirty"]:
			if d.has(key) and not d[key] is bool:return "恢复地形编辑状态无效。"
		for item in [["edge",0,3],["style",0,1],["vertex",-1,127]]:
			if d.has(item[0]) and (not Model.numeric(d[item[0]]) or float(d[item[0]])!=floorf(float(d[item[0]])) or d[item[0]]<item[1] or d[item[0]]>item[2]):return "恢复地形选择越界。"
	if draft.has("plot_draft"):
		for field in ["points","brush_points"]:
			var list: Variant=draft.plot_draft.get(field,[])
			if not list is Array or list.size()>256:return "恢复区域／笔迹草稿过长。"
			for point in list:
				if not Model.pair(point):return "恢复区域／笔迹草稿坐标无效。"
		if not draft.plot_draft.get("brush_template",{}) is Dictionary:return "恢复笔刷草稿类型无效。"
	if draft.has("plot_fields"):
		var fields: Dictionary=draft.plot_fields
		if fields.has("vertex_xy") and not Model.pair(fields.vertex_xy):return "恢复顶点坐标无效。"
		if not fields.get("raw_numbers",{}) is Dictionary:return "恢复数字草稿无效。"
		for raw in fields.get("raw_numbers",{}).values():
			if not raw is String or raw.length()>256:return "恢复数字草稿过长或无效。"
		if not fields.get("parameters",{}) is Dictionary or not fields.get("job_command",{}) is Dictionary:return "恢复区域参数无效。"
		var values: Dictionary=fields.get("parameters",{})
		if not values.is_empty():
			for key in ["seed","density","cluster_strength"]:
				if not Model.numeric(values.get(key)):return "恢复区域数字参数无效。"
			for key in ["spacing","scale_range"]:
				if not Model.pair(values.get(key)):return "恢复区域尺寸参数无效。"
			var weights: Variant=values.get("asset_weights",[])
			if not weights is Array or weights.size()>16:return "恢复加权素材数量无效。"
			for item in weights:
				if not item is Dictionary or not project.asset_refs.has(item.get("asset_ref")) or not Model.numeric(item.get("weight")) or float(item.weight)<=0:return "恢复加权素材版本或权重无效。"
		var extras: Variant=fields.get("extra_rows",[])
		if not extras is Array or extras.size()>14:return "恢复混用素材行数量无效。"
		for row in extras:
			if not row is Dictionary or not row.get("asset_ref") is String or (not row.asset_ref.is_empty() and not project.asset_refs.has(row.asset_ref)) or not Model.numeric(row.get("weight")) or float(row.weight)<=0:return "恢复混用素材版本或权重无效。"
			if not row.get("raw","") is String or str(row.get("raw","")).length()>256:return "恢复混用权重文本无效。"
	if draft.has("path_draft"):
		var path: Dictionary=draft.path_draft
		if not path.get("points",[]) is Array or path.get("points",[]).size()>256: return "恢复控制点草稿无效。"
		for point in path.get("points",[]):
			if not Model.pair(point): return "恢复控制点位置无效。"
	if draft.has("asset_editor") and not draft.asset_editor.is_empty():
		var metadata: Dictionary=draft.asset_editor
		if not metadata.get("asset_ref") is String or not project.get("asset_refs",{}).has(metadata.asset_ref) or not metadata.get("descriptor") is Dictionary: return "恢复资产描述缺少固定来源。"
		var issue:=Model.Asset.validate_draft(metadata.descriptor)
		if not issue.is_empty(): return issue
		for key in ["label","tags","source","raw"]:
			if not metadata.get(key) is String or metadata[key].length()>1048576: return "恢复资产属性文本无效。"
		for key in ["category","shadow","width"]:
			if not Model.numeric(metadata.get(key)): return "恢复资产属性数字无效。"
		if not metadata.get("crop") is Array or metadata.crop.size()!=4: return "恢复裁切草稿无效。"
		for v in metadata.crop:
			if not Model.numeric(v): return "恢复裁切草稿数字无效。"
	return ""
