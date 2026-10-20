@tool
extends Node
## One frozen authoring snapshot, one RenderPlan, fresh-directory atomic adoption.
const Session=preload("session_transaction.gd")
const Canvas=preload("ui/project_canvas.gd")
const Plan=preload("render_plan.gd")
const SurfaceProject=preload("surface_projection.gd")
signal progress(message: String,completed: int,total: int)
var busy:=false
var cancelled:=false
var write_hook: Callable
var _stage: String=""
var _created: Array=[]
var _viewport: SubViewport
var _canvas
var _codec: Thread
var _image_job
var _frozen
var _preflight: Thread
var last_timing: Dictionary={}
static func error(message: String) -> Dictionary:return {"ok":false,"error":message}
static func digest(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
static func straight_alpha(image: Image) -> Image:
	# Godot viewport capture is premultiplied. PNG consumers expect straight alpha.
	image.convert(Image.FORMAT_RGBA8);var bytes:=image.get_data()
	for index in range(3,bytes.size(),4):
		var alpha: int=bytes[index]
		if alpha>0 and alpha<255:
			for channel in range(index-3,index):bytes[channel]=clampi(roundi(float(bytes[channel])*255.0/alpha),0,255)
	return Image.create_from_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,bytes)
static func serial(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Rect2:return {"position":serial(value.position),"size":serial(value.size)}
	if value is Color:return value.to_html(true)
	if value is PackedVector2Array or value is PackedColorArray or value is Array:
		var out: Array=[]
		for v in value:out.append(serial(v))
		return out
	if value is Dictionary:
		var out: Dictionary={}
		for key in value:out[key]=serial(value[key])
		return out
	return value
static func equivalent(a: Variant,b: Variant) -> bool:
	if Session.Model.numeric(a) and Session.Model.numeric(b):return absf(float(a)-float(b))<=0.000001
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not equivalent(a[i],b[i]):return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(str(key)) or not equivalent(a[key],b[str(key)]):return false
		return true
	return a==b
static func default_bounds(p: Dictionary) -> Rect2:
	var extent:=Vector2(p.legacy_document.canvas_size[0],p.legacy_document.canvas_size[1]);var points:=PackedVector2Array()
	for q in [Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)]:points.append(SurfaceProject.project_point(p,q))
	var bounds:=Plan.bounds(points)
	for e in Plan.build(p):bounds=bounds.merge(e.paint_bounds)
	return Rect2(bounds.position.floor()-Vector2.ONE*8,(bounds.end.ceil()-bounds.position.floor())+Vector2.ONE*16)
func cancel() -> void:
	cancelled=true
	if _image_job!=null:_image_job.cancel()
func template_thumbnail(source,template: Dictionary) -> Image:
	var project: Dictionary=Session.Model.blank();project.legacy_document.canvas_size=[32768,32768];project.style_profile=source.snapshot().style_profile.duplicate(true)
	project.materialized_snapshot=Session.Model.materialize(project)
	var clone=Session.new();var adopted: Dictionary=clone.replace_project(project)
	if not adopted.ok:return null
	for asset in template.asset_refs.values():clone.asset_blobs[asset.texture_sha256]=source.asset_bytes(asset)
	var placed: Dictionary=clone.dispatch({"op":"instantiate_template","template":template,"ground_xy":template.origin})
	if not placed.ok:return null
	return await thumbnail(clone,[])
func thumbnail(session,selected: Array) -> Image:
	var entries:=Plan.build(session.snapshot());var bounds:=Rect2();var first:=true
	for e in entries:
		if not selected.is_empty() and e.entity_id not in selected:continue
		bounds=e.paint_bounds if first else bounds.merge(e.paint_bounds);first=false
	if first:bounds=default_bounds(session.snapshot())
	bounds=bounds.grow(8);var scale:=minf(256/maxf(bounds.size.x,1),256/maxf(bounds.size.y,1))
	_viewport=SubViewport.new();_viewport.transparent_bg=true;_viewport.disable_3d=true;add_child(_viewport)
	_canvas=Canvas.new();_canvas.session=session;_canvas.render_only=true;_canvas.render_background=false;_viewport.add_child(_canvas);await get_tree().process_frame
	var result: Image=await _image(bounds,scale,[],selected,false,false)
	_viewport.queue_free();return result
func _cleanup() -> void:
	if is_instance_valid(_canvas) and _canvas.get_parent()==null:_canvas.queue_free()
	if is_instance_valid(_viewport):_viewport.queue_free()
	var reverse: Array=_created.duplicate();reverse.reverse()
	for path in reverse:
		if path.begins_with(_stage+"/"):DirAccess.remove_absolute(path)
	if not _stage.is_empty():DirAccess.remove_absolute(_stage)
	_created.clear();busy=false
	_frozen=null;_canvas=null
func _exit_tree() -> void:
	cancel()
	if _preflight!=null:_preflight.wait_to_finish();_preflight=null
	if _codec!=null:_codec.wait_to_finish();_codec=null
	if busy:_cleanup()
func _write(relative: String,bytes: PackedByteArray) -> String:
	if cancelled:return "导出已取消，原交付保留。"
	if not Session.Model.safe_relative(relative):return "导出内部路径无效。"
	var target: String=_stage.path_join(relative)
	if write_hook.is_valid() and not bool(write_hook.call(relative,bytes)):return "注入的导出写入失败，原交付保留。"
	var file:=FileAccess.open(target,FileAccess.WRITE)
	if file==null:return "无法写入导出文件："+relative
	_created.append(target);file.store_buffer(bytes);file.flush();var result:=file.get_error();file.close()
	if result!=OK or FileAccess.get_file_as_bytes(target)!=bytes:return "导出文件写入核验失败："+relative
	return ""
func _json(relative: String,value: Dictionary) -> String:return _write(relative,JSON.stringify(value,"\t",false,true).to_utf8_buffer())
func _image(rect: Rect2,scale: float,indices: Array=[],selected: Array=[],ground_only: bool=false,paper: bool=false,overlays: bool=false,correct_alpha: bool=true) -> Image:
	_canvas.pan=-rect.position*scale;_canvas.zoom=scale;_canvas.export_indices=indices;_canvas.export_selected=selected;_canvas.export_ground_only=ground_only;_canvas.draw_paper=paper
	_canvas.export_overlay=overlays
	_viewport.size=Vector2i(roundi(rect.size.x*scale),roundi(rect.size.y*scale));_canvas.size=Vector2(_viewport.size);_canvas.queue_redraw();_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	# An occluded/minimized editor can suppress ordinary window draws. Explicitly
	# drive this UPDATE_ONCE offscreen capture instead of waiting indefinitely.
	RenderingServer.force_draw(false)
	var raw:=_viewport.get_texture().get_image()
	return straight_alpha(raw) if correct_alpha else raw

func _prepare_snapshot(project: Dictionary,source_path: String,blobs: Dictionary,options: Dictionary,requested: Rect2,scale: float) -> Dictionary:
	var frozen=Session.new()
	var adopted: Dictionary=frozen.replace_project(project)
	if not adopted.ok or frozen.read_only:return error("项目快照不可编辑或派生结果不一致。")
	frozen.current_path=source_path;frozen.asset_blobs=blobs
	var images: Dictionary={}
	for asset in project.asset_refs.values():
		var bytes: PackedByteArray=frozen.asset_bytes(asset)
		if bytes.is_empty() or digest(bytes)!=asset.texture_sha256:return error("导出缺少正确素材："+asset.label)
		frozen.asset_blobs[asset.texture_sha256]=bytes
		if not images.has(asset.texture_sha256):
			var image:=Image.new()
			if image.load_png_from_buffer(bytes)!=OK:return error("导出素材不能解码："+asset.label)
			images[asset.texture_sha256]=image
	var entries:=Plan.build(frozen.view());Session.freeze(entries)
	var stack: Array=[]
	for i in range(entries.size()):stack.append({"index":i,"entity_id":entries[i].entity_id,"kind":entries[i].entity.kind,"part_order":entries[i].get("part_order",0),"entry":serial(entries[i])})
	Session.freeze(stack)
	frozen._prepared_plan=entries;frozen._prepared_signature=Session._plan_key(frozen.view())
	var bounds:=requested if options.has("bounds") else default_bounds(project)
	var pixels:=Vector2i(ceili(bounds.size.x*scale),ceili(bounds.size.y*scale));bounds.size=Vector2(pixels)/scale
	if pixels.x>8192 or pixels.y>8192:return error("单图限8192像素，分页限64—2048像素。")
	var estimate:=estimate_output(pixels,entries.size(),options)
	if not estimate.ok:return error(estimate.error)
	return {"ok":true,"frozen":frozen,"images":images,"entries":entries,"stack":stack,"bounds":bounds,"pixels":pixels,"estimate":estimate}

func _json_on_worker(value: Dictionary) -> PackedByteArray:
	return JSON.stringify(value,"\t",false,true).to_utf8_buffer()
func _json_async(relative: String,value: Dictionary) -> String:
	_preflight=Thread.new()
	var started:=_preflight.start(_json_on_worker.bind(value))
	if started!=OK:_preflight=null;return "不能启动清单编码。"
	while _preflight.is_alive():await get_tree().process_frame
	var bytes: PackedByteArray=_preflight.wait_to_finish();_preflight=null
	return _write(relative,bytes)

func export_project(session,destination: String,options: Dictionary) -> Dictionary:
	for key in options:
		if key not in ["bounds","scale","tile_size","selected_ids","transparent_ground","layers","include_grid","include_legend"]:return error("未知导出选项。")
	for key in ["transparent_ground","layers","include_grid","include_legend"]:
		if options.has(key) and not options[key] is bool:return error("导出开关必须为布尔值。")
	if busy:return error("已有导出进行中。")
	if session.has_preview():return error("先应用或取消预览，再冻结导出。")
	var target: String=ProjectSettings.globalize_path(destination).replace("\\","/").trim_suffix("/")
	if not Session._safe_target(target) or DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target):return error("导出须使用新的目录；已有交付不会覆盖。")
	var project: Dictionary=session.view();var scale: Variant=options.get("scale",1.0);var bounds:=Rect2()
	if options.has("bounds"):
		var b: Variant=options.bounds
		if not b is Array or b.size()!=4 or not b.all(func(n):return Session.Model.numeric(n)):return error("固定导出范围无效。")
		bounds=Rect2(b[0],b[1],b[2],b[3])
	if not Session.Model.numeric(scale) or scale<=0 or scale>4 or (options.has("bounds") and (bounds.size.x<=0 or bounds.size.y<=0)):return error("导出比例／范围无效。")
	var tile: Variant=options.get("tile_size",2048)
	if not Session.Model.numeric(tile) or float(tile)!=floorf(float(tile)) or tile<64 or tile>2048:return error("单图限8192像素，分页限64—2048像素。")
	var selected: Variant=options.get("selected_ids",[])
	if not selected is Array or not selected.all(func(id):return id is String):return error("导出选择列表无效。")
	busy=true;cancelled=false;_created=[];_stage="";last_timing={}
	progress.emit("正在验证冻结项目…",0,1)
	var began:=Time.get_ticks_usec()
	_preflight=Thread.new()
	var started:=_preflight.start(_prepare_snapshot.bind(project,session.current_path,session.asset_blobs.duplicate(false),options.duplicate(true),bounds,float(scale)))
	if started!=OK:_preflight=null;busy=false;return error("不能启动导出校验。")
	while _preflight.is_alive():await get_tree().process_frame
	var prepared: Dictionary=_preflight.wait_to_finish();_preflight=null
	last_timing.preflight_ms=(Time.get_ticks_usec()-began)/1000.0
	if cancelled:_cleanup();return error("导出已取消，原交付保留。")
	if not prepared.ok:_cleanup();return prepared
	var entries: Array=prepared.entries;var estimate: Dictionary=prepared.estimate;var pixels: Vector2i=prepared.pixels
	bounds=prepared.bounds
	var frozen=prepared.frozen
	progress.emit("预计 %d 张 PNG，工作像素 %.1f百万，原始输出上界 %.1fMiB，图像峰值估算 %.1fMiB"%[estimate.images,estimate.work_pixels/1000000.0,estimate.raw_output_bytes/1048576.0,estimate.estimated_image_peak_bytes/1048576.0],0,estimate.images)
	_stage=target+".tmp_"+Session.Model.new_id("export")
	if DirAccess.make_dir_recursive_absolute(_stage)!=OK:busy=false;return error("不能建立临时导出目录。")
	if DirAccess.make_dir_absolute(_stage.path_join("assets"))!=OK:_cleanup();return error("不能建立资产目录。")
	_created.append(_stage.path_join("assets"));_frozen=frozen
	began=Time.get_ticks_usec()
	var frozen_saved: Dictionary=frozen.start_io_job(_stage.path_join("project.shwork.json"))
	if frozen_saved.ok:
		while frozen.io_in_progress():
			await get_tree().process_frame
			var saved: Dictionary=frozen.poll_io_job()
			if saved.status=="failed":frozen_saved=error(saved.error)
	# save_file wrote content-addressed assets; inventory only this fresh stage for exact cleanup.
	var dir:=DirAccess.open(_stage.path_join("assets"))
	if dir!=null:
		for file in dir.get_files():_created.append(_stage.path_join("assets").path_join(file))
	_created.append(_stage.path_join("project.shwork.json"))
	if not frozen_saved.ok:_cleanup();return frozen_saved
	last_timing.frozen_save_ms=(Time.get_ticks_usec()-began)/1000.0
	if cancelled:_cleanup();return error("导出已取消，原交付保留。")
	_viewport=SubViewport.new();_viewport.transparent_bg=true;_viewport.disable_3d=true;add_child(_viewport)
	_canvas=Canvas.new();_canvas.session=frozen;_canvas.render_only=true;_canvas.render_background=false;_canvas.show_envelopes=false;_canvas.show_plot_boundaries=false;_canvas.show_district_lots=false;_canvas.export_include_grid=bool(options.get("include_grid",false));_canvas.export_include_legend=bool(options.get("include_legend",false))
	# Decode in preflight; spread GPU uploads across frames before drawing.
	for hash in prepared.images:
		if cancelled:_cleanup();return error("导出已取消，原交付保留。")
		_canvas._textures[hash]=ImageTexture.create_from_image(prepared.images[hash])
		await get_tree().process_frame
	_viewport.add_child(_canvas)
	await get_tree().process_frame
	var jobs: Array=[{"path":"composite.png","bounds":bounds,"paper":true,"indices":[],"selected":[],"ground":false,"overlays":true}]
	if options.get("transparent_ground",true):jobs.append({"path":"ground.png","bounds":bounds,"paper":false,"indices":[],"selected":[],"ground":true})
	if not selected.is_empty():jobs.append({"path":"selection.png","bounds":bounds,"paper":false,"indices":[],"selected":selected,"ground":false})
	var stack: Array=prepared.stack;var layers: Array=[];var tiles: Array=[]
	if options.get("layers",true):
		layers.append({"path":"background.png","indices":[],"kind":"background","origin":[bounds.position.x,bounds.position.y],"size":[pixels.x,pixels.y]});jobs.append({"path":"background.png","bounds":bounds,"paper":true,"indices":[-1],"selected":[],"ground":false})
		for start in range(0,entries.size(),64):
			var name: String="layer_%04d.png"%layers.size();var indices: Array=Array(range(start,mini(start+64,entries.size())))
			layers.append({"path":name,"indices":indices,"origin":[bounds.position.x,bounds.position.y],"size":[pixels.x,pixels.y]});jobs.append({"path":name,"bounds":bounds,"paper":false,"indices":indices,"selected":[],"ground":false})
		if options.get("include_grid",false) or options.get("include_legend",false):
			layers.append({"path":"overlays.png","indices":[],"kind":"overlays","origin":[bounds.position.x,bounds.position.y],"size":[pixels.x,pixels.y]});jobs.append({"path":"overlays.png","bounds":bounds,"paper":false,"indices":[-1],"selected":[],"ground":false,"overlays":true})
	# Core-only pages cropped from one full image; no stored gutter or mip claim.
	var gutter:=0
	for y in range(0,pixels.y,int(tile)):
		for x in range(0,pixels.x,int(tile)):
			var size:=Vector2i(mini(int(tile),pixels.x-x),mini(int(tile),pixels.y-y));var tile_rect:=Rect2(bounds.position+Vector2(x-gutter,y-gutter)/float(scale),Vector2(size+Vector2i.ONE*gutter*2)/float(scale));var name: String="tile_%04d.png"%tiles.size()
			tiles.append({"path":name,"pixel_origin":[x,y],"pixel_size":[size.x,size.y],"gutter":gutter,"stored_size":[size.x,size.y],"core_rect":[0,0,size.x,size.y],"sampling":"crop of same frozen full image within S1 8192 limit"});jobs.append({"path":name,"bounds":tile_rect,"paper":true,"indices":[],"selected":[],"ground":false,"crop":Rect2i(Vector2i(gutter,gutter),size),"overlays":true})
	var files: Dictionary={}
	var composite: Image
	for i in range(jobs.size()):
		if cancelled:_cleanup();return error("导出已取消，原交付保留。")
		var job: Dictionary=jobs[i];progress.emit("导出 "+job.path,i,jobs.size());var image: Image
		if job.has("crop"):
			var page: Dictionary=tiles.filter(func(t):return t.path==job.path)[0]
			image=composite.get_region(Rect2i(Vector2i(page.pixel_origin[0],page.pixel_origin[1]),Vector2i(page.pixel_size[0],page.pixel_size[1])))
		else:image=await _image(job.bounds,float(scale),job.indices,job.selected,job.ground,job.paper,job.get("overlays",false),false)
		var encoded: Dictionary=await _encode(image,not job.has("crop"),i,jobs.size())
		if not encoded.ok:_cleanup();return error("导出已取消或图像编码失败；原交付保留。")
		if job.path=="composite.png":composite=encoded.image
		var issue:=_write(job.path,encoded.png)
		if not issue.is_empty():_cleanup();return error(issue)
		files[job.path]=FileAccess.get_sha256(_stage.path_join(job.path))
	files["project.shwork.json"]=FileAccess.get_sha256(_stage.path_join("project.shwork.json"))
	for a in project.asset_refs.values():files[a.texture_ref]=a.texture_sha256
	var manifest: Dictionary={"document_type":"shanhe.workshop_export","schema_version":1,"project_ref":"project.shwork.json","frozen_input_hash":project.materialized_snapshot.input_hash,"generator_version":project.materialized_snapshot.generator_version,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"scale":scale,"pixel_size":[pixels.x,pixels.y],"environment":"static S1; no weather or game time binding","render_stack":stack,"layers":layers,"tiles":tiles,"files":files,"options":serial(options),"estimate":estimate,"logical_bindings":"presentation only; no navigation or GameState changes"}
	began=Time.get_ticks_usec()
	var issue: String=await _json_async("manifest.json",manifest)
	last_timing.manifest_ms=(Time.get_ticks_usec()-began)/1000.0
	if cancelled or not issue.is_empty():_cleanup();return error("导出取消或清单写入失败；原交付保留。")
	if DirAccess.dir_exists_absolute(target) or DirAccess.rename_absolute(_stage,target)!=OK:_cleanup();return error("不能原子采用新目录；原交付保留。")
	_created.clear();_stage="";busy=false;_viewport.queue_free();progress.emit("导出完成",jobs.size(),jobs.size())
	_frozen=null;_canvas=null
	return {"ok":true,"path":target,"manifest":manifest}
static func validate_bundle(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return error("导出清单不存在。")
	if FileAccess.get_file_as_bytes(path).size()>67108864:return error("导出清单超过64MiB。")
	var json:=JSON.new()
	if json.parse(FileAccess.get_file_as_string(path))!=OK or not json.data is Dictionary:return error("导出清单 JSON 无效。")
	var m: Dictionary=json.data
	if m.get("document_type")!="shanhe.workshop_export" or m.get("schema_version")!=1 or not m.get("files") is Dictionary or not m.get("render_stack") is Array or not m.get("tiles") is Array or not m.get("project_ref") is String:return error("未知导出协议。")
	if not m.get("bounds") is Array or m.bounds.size()!=4 or not m.bounds.all(func(n):return Session.Model.numeric(n)) or m.bounds[2]<=0 or m.bounds[3]<=0 or not Session.Model.numeric(m.get("scale")) or m.scale<=0 or m.scale>4 or not m.get("pixel_size") is Array or m.pixel_size.size()!=2 or not m.pixel_size.all(func(n):return Session.Model.numeric(n) and n>0 and n<=8192 and n==floorf(n)) or not m.get("layers") is Array:return error("导出几何范围无效。")
	# Rect2/Vector2 use float32; fractional scales can round by ~1e-4 pixels.
	if absf(m.bounds[2]*m.scale-m.pixel_size[0])>0.01 or absf(m.bounds[3]*m.scale-m.pixel_size[1])>0.01:return error("导出像素范围不一致。")
	for layer in m.layers:
		if not layer is Dictionary or not layer.get("path") is String or not m.files.has(layer.path):return error("导出层引用无效。")
	for page in m.tiles:
		if not page is Dictionary or not page.get("path") is String or not m.files.has(page.path) or not page.get("pixel_origin") is Array or page.pixel_origin.size()!=2 or not page.get("pixel_size") is Array or page.pixel_size.size()!=2:return error("分页引用无效。")
	if not Session.Model.safe_relative(m.project_ref) or not m.files.has(m.project_ref):return error("导出项目路径无效。")
	for relative in m.files:
		if not relative is String or not Session.Model.safe_relative(relative) or not m.files[relative] is String or not FileAccess.file_exists(path.get_base_dir().path_join(relative)) or FileAccess.get_sha256(path.get_base_dir().path_join(relative))!=m.files[relative]:return error("导出文件缺失、路径非法或 hash 不符："+str(relative))
	var page_rects: Array[Rect2i]=[];var page_area:=0
	for page in m.tiles:
		if not valid_page(page,Vector2i(m.pixel_size[0],m.pixel_size[1])):return error("分页核心尺寸、边框或范围不一致。")
		var rect:=Rect2i(page.pixel_origin[0],page.pixel_origin[1],page.pixel_size[0],page.pixel_size[1])
		for previous in page_rects:
			if rect.intersects(previous):return error("分页核心范围重叠。")
		page_rects.append(rect);page_area+=rect.size.x*rect.size.y
		var image:=Image.load_from_file(path.get_base_dir().path_join(page.path))
		if image==null or image.get_size()!=Vector2i(page.pixel_size[0],page.pixel_size[1]):return error("分页PNG实际尺寸与清单不一致。")
	if page_area!=int(m.pixel_size[0])*int(m.pixel_size[1]):return error("分页未覆盖完整合成范围。")
	var session=Session.new();var opened: Dictionary=session.load_file(path.get_base_dir().path_join(m.project_ref))
	if not opened.ok or session.read_only or Session.Model.input_hash(session.snapshot())!=m.get("frozen_input_hash"):return error("导出项目依赖或输入版本不一致。")
	var expected: Array=Plan.build(session.snapshot())
	if expected.size()!=m.render_stack.size():return error("导出层序数量不符。")
	for i in range(expected.size()):
		if not m.render_stack[i] is Dictionary or m.render_stack[i].get("index")!=i or m.render_stack[i].get("entity_id")!=expected[i].entity_id:return error("导出层序或实体身份不符。")
		if not equivalent(serial(expected[i]),m.render_stack[i].get("entry",{})):return error("导出绘制片与冻结项目不一致。")
	return {"ok":true,"manifest":m,"session":session}

static func valid_page(page: Dictionary,pixels: Vector2i) -> bool:
	if page.get("gutter",-1)!=0:return false
	for field in ["pixel_origin","pixel_size","stored_size"]:
		if not page.get(field) is Array or page[field].size()!=2 or not page[field].all(func(n):return Session.Model.numeric(n) and n==floorf(n)):return false
	if page.pixel_origin[0]<0 or page.pixel_origin[1]<0 or page.pixel_size[0]<1 or page.pixel_size[1]<1 or page.pixel_origin[0]+page.pixel_size[0]>pixels.x or page.pixel_origin[1]+page.pixel_size[1]>pixels.y:return false
	return equivalent(page.stored_size,page.pixel_size) and equivalent(page.get("core_rect"),[0,0,page.pixel_size[0],page.pixel_size[1]])

## Conservative preflight before any destination/temp directory is created.
## Raw PNG workload and image buffers are estimates, not a process RSS guarantee.
static func estimate_output(pixels: Vector2i,entry_count: int,options: Dictionary) -> Dictionary:
	var full:=1+int(options.get("transparent_ground",true))+int(not options.get("selected_ids",[]).is_empty())
	if options.get("layers",true):full+=1+ceili(entry_count/64.0)+int(options.get("include_grid",false) or options.get("include_legend",false))
	var tile: int=int(options.get("tile_size",2048))
	if tile<64 or tile>2048 or pixels.x<1 or pixels.y<1 or pixels.x>8192 or pixels.y>8192:return error("导出尺寸或分页超出安全范围。")
	var area: int=pixels.x*pixels.y
	var pages: int=ceili(pixels.x/float(tile))*ceili(pixels.y/float(tile))
	var work: int=area*(full+1)
	var peak: int=area*4*8
	var result: Dictionary={"ok":true,"images":full+pages,"full_frame_images":full,"tiles":pages,"work_pixels":work,"raw_output_bytes":work*4,"estimated_image_peak_bytes":peak,"work_pixel_limit":268435456,"image_peak_estimate_limit":536870912,"storage_contract":"full composite plus core-only crops; estimates exclude assets, engine and GPU overhead"}
	if work>result.work_pixel_limit or peak>result.image_peak_estimate_limit:return error("导出估算超出安全预算（工作像素256Mi / 图像缓冲估算512MiB）；请缩小范围／比例，或关闭连续层序片。")
	return result
func _encode(image: Image,unpremultiply: bool,current: int,total: int) -> Dictionary:
	_image_job=preload("export_image_job.gd").new();_codec=Thread.new()
	if _codec.start(_image_job.encode.bind(image,unpremultiply))!=OK:_codec=null;_image_job=null;return {"ok":false}
	var last_rows: int=-1
	while _codec.is_alive():
		if cancelled:_image_job.cancel()
		var state: Dictionary=_image_job.state()
		if state.rows_done!=last_rows:
			last_rows=state.rows_done;progress.emit("图像处理 %d/%d 行"%[last_rows,image.get_height()],current,total)
		await get_tree().process_frame
	var result: Dictionary=_codec.wait_to_finish();_codec=null;_image_job=null
	return result
