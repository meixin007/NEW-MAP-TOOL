extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const C=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_canvas.gd")
const A=preload("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd")
var failures: Array=[]
var rows: Array=[]
var frames: Array=[]
var active:=false
var last_frame:=0
var s
var canvas
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _process(_delta: float) -> bool:
	var now:=Time.get_ticks_usec()
	if active:frames.append((now-last_frame)/1000.0)
	last_frame=now
	return false
func _initialize() -> void:call_deferred("run")
func recorded(command: Dictionary) -> void:
	var began:=Time.get_ticks_usec();var result: Dictionary=s.start_preview_job(command)
	var input_ms: float=(Time.get_ticks_usec()-began)/1000.0
	check(result.ok,str(result))
	if not result.ok:return
	result={"status":"working"}
	while result.status=="working":await process_frame;result=s.poll_preview_job()
	check(result.status=="ready",str(result))
	var adopted: Dictionary=s.commit_preview() if result.status=="ready" else {"ok":false}
	rows.append({"action":command.op,"input_ms":input_ms,"ms":(Time.get_ticks_usec()-began)/1000.0,"ok":adopted.ok,"stages":s.last_timing.duplicate()});check(adopted.ok,str(adopted))
	canvas.queue_redraw();await process_frame;await process_frame
func drag_path() -> void:
	canvas.mode="path_edit";canvas.selected_recipe_id="review.profile.path";canvas.pan=Vector2(400,300)-C.SurfaceProject.project_point(s.view(),Vector2(100,7700))*canvas.zoom
	canvas.queue_redraw();await process_frame;await process_frame
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=Vector2(400,300);event.pressed=true;canvas._gui_input(event)
	check(canvas._point_dragging,"native canvas path point begins")
	var rev: int=s.revision
	for i in range(20):
		var move:=InputEventMouseMotion.new();move.position=Vector2(400+i*0.1,300)
		var began:=Time.get_ticks_usec();canvas._gui_input(move);rows.append({"action":"path_motion","ms":(Time.get_ticks_usec()-began)/1000.0});await process_frame
	check(s.revision==rev,"path motion does not mutate authority")
	event.pressed=false;var began:=Time.get_ticks_usec();canvas._gui_input(event);rows.append({"action":"path_release_input","ms":(Time.get_ticks_usec()-began)/1000.0})
	while canvas.edit_pending:await process_frame
	rows.append({"action":"path_release_complete","ms":(Time.get_ticks_usec()-began)/1000.0,"stages":s.last_timing.duplicate()})
	check(s.revision==rev+1,"path release adopts one transaction")
func run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[0];var duration:=float(args[2]) if args.size()>2 else 60.0
	DirAccess.make_dir_recursive_absolute(out)
	s=S.new();var loaded: Dictionary=s.load_file(args[1]);check(loaded.ok,"core load")
	if not loaded.ok:quit(1);return
	var original: Dictionary=s.snapshot();var p:=original.duplicate(true)
	# Fixed editing variant: retain 120 recipes and exactly 5000 initial entities;
	# use a zero-density forest, a path in the empty margin, and an empty terrace.
	p.recipes[0]={"recipe_id":"review.profile.forest","kind":"plot","name":"profile forest","plot_type":"forest","shape":"rectangle","outer":[[100,7100],[450,7100],[450,7350],[100,7350]],"holes":[],"surface_id":"ground","seed":42,"density":0,"spacing":[64,64],"scale_range":[0.8,1],"asset_weights":[{"asset_ref":"tree_unit_a_v3@v3","weight":1}],"cluster_strength":0.2,"locked":false}
	p.recipes[1]={"recipe_id":"review.profile.path","kind":"path","path_type":"road","name":"profile path","control_points":[{"point_id":"a","ground_xy":[100,7700],"width":24},{"point_id":"b","ground_xy":[500,7700],"width":24}],"segments":[{"segment_id":"ab","from":"a","to":"b"}],"surface_id":"ground","seed":42,"style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
	p.manual_entities.pop_back()
	p.surfaces.append({"surface_id":"profile.top","kind":"terrace","parent_surface_id":"ground","height":20,"outline":[[11000,7000],[11800,7000],[11800,7800],[11000,7800]],"edge_styles":["cliff","cliff","cliff","cliff"],"edge_widths":[0,0,0,0],"top_color":"c5bf89","edge_color":"b69d70","locked":false})
	p.materialized_snapshot=S.Model.materialize(p);check(s.replace_project(p).ok,"editing variant valid")
	check(p.recipes.size()==120 and p.materialized_snapshot.entities.size()==5000,"editing variant frozen 5000/120")
	check(s.save_file(out.path_join("fixture.shwork.json")).ok,"frozen editing fixture saved")
	canvas=C.new();canvas.session=s;canvas.zoom=0.5;canvas.show_envelopes=false;root.add_child(canvas);canvas.size=Vector2(1280,720);await process_frame;await process_frame
	var initial_memory:=int(Performance.get_monitor(Performance.MEMORY_STATIC));var began:=Time.get_ticks_usec();last_frame=began;active=true;var cycles:=0;var memory: Array=[]
	await drag_path()
	while (Time.get_ticks_usec()-began)/1000000.0<duration:
		await recorded({"op":"update_recipe","recipe_id":"review.profile.forest","patch":{"density":0.5 if cycles%2==0 else 0.6}})
		await recorded({"op":"update_terrain","surface_id":"profile.top","patch":{"height":21 if cycles%2==0 else 20}})
		var stamp:=Time.get_ticks_usec();check(s.undo(),"soak undo");rows.append({"action":"undo","ms":(Time.get_ticks_usec()-stamp)/1000.0})
		stamp=Time.get_ticks_usec();check(s.redo(),"soak redo");rows.append({"action":"redo","ms":(Time.get_ticks_usec()-stamp)/1000.0})
		if cycles%5==0:
			stamp=Time.get_ticks_usec();check(s.save_file(out.path_join("save.shwork.json")).ok,"soak save");rows.append({"action":"save","ms":(Time.get_ticks_usec()-stamp)/1000.0})
		cycles+=1;memory.append({"cycle":cycles,"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"history":s.history_stats(),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
		var until:=Time.get_ticks_msec()+2500
		while Time.get_ticks_msec()<until:await process_frame
	active=false
	var before_clear:=int(Performance.get_monitor(Performance.MEMORY_STATIC));s.clear_history();await process_frame
	var after_clear:=int(Performance.get_monitor(Performance.MEMORY_STATIC));var switches: Array=[]
	for i in range(3):check(s.replace_project(original).ok,"switch to original");check(s.replace_project(p).ok,"switch to editing variant");canvas.queue_redraw();await process_frame;switches.append(Performance.get_monitor(Performance.MEMORY_STATIC))
	# Persist completed sampling before exercising a separate asynchronous export.
	var sample:=FileAccess.open(out.path_join("SAMPLING.json"),FileAccess.WRITE)
	sample.store_string(JSON.stringify({"duration_seconds":duration,"cycles":cycles,"frames":frames,"rows":rows,"memory":memory,"initial_static_bytes":initial_memory,"before_clear_bytes":before_clear,"after_clear_bytes":after_clear,"switch_static_bytes":switches,"failures":failures},"\t"));sample.close()
	var adapter=A.new();root.add_child(adapter);var stamp:=Time.get_ticks_usec()
	var exported: Dictionary=await adapter.export_project(s,out.path_join("export"),{"bounds":[0,0,512,512],"scale":1,"layers":false,"transparent_ground":false,"tile_size":256})
	rows.append({"action":"export_512","ms":(Time.get_ticks_usec()-stamp)/1000.0,"ok":exported.ok});check(exported.ok,str(exported))
	var sorted:=frames.duplicate();sorted.sort()
	var result: Dictionary={"scope":"automated native canvas events plus transaction-level density/terrain/history/save/export; not human acceptance","renderer":RenderingServer.get_video_adapter_name(),"duration_seconds":duration,"cycles":cycles,"fixture_input_hash":p.materialized_snapshot.input_hash,"original_input_hash":original.materialized_snapshot.input_hash,"frames":frames,"p95_ms":sorted[ceili(sorted.size()*0.95)-1],"p99_ms":sorted[ceili(sorted.size()*0.99)-1],"max_frame_ms":frames.max(),"rows":rows,"memory":memory,"initial_static_bytes":initial_memory,"before_clear_bytes":before_clear,"after_clear_bytes":after_clear,"switch_static_bytes":switches,"failures":failures}
	var file:=FileAccess.open(out.path_join("PROFILE.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close();result.erase("frames");result.erase("rows");result.erase("memory");print("REVIEW_EDIT_SOAK ",JSON.stringify(result))
	s.shutdown_jobs();adapter.queue_free();canvas.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
