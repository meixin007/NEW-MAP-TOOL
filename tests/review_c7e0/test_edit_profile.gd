extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const C=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_canvas.gd")
var rows: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var s=S.new()
	var loaded: Dictionary=s.load_file(args[0])
	if not loaded.ok:printerr(loaded);quit(1);return
	var c=C.new();c.session=s;root.add_child(c);c.size=Vector2(1280,720);c.zoom=0.6
	await process_frame
	var p: Dictionary=s.snapshot();var e: Dictionary=p.manual_entities[0]
	c.pan=Vector2(500,400)-C.SurfaceProject.project_point(p,Vector2(e.ground_xy[0],e.ground_xy[1]))*c.zoom
	c.queue_redraw();await process_frame;await process_frame
	var start:=Vector2(500,390)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;c._gui_input(press)
	# Drive the real canvas event handler; these are automated native input samples,
	# not human interaction or an acceptance claim.
	for i in range(20):
		var motion:=InputEventMouseMotion.new();motion.position=start+Vector2((i+1)*0.2,0)
		var began:=Time.get_ticks_usec();c._gui_input(motion)
		rows.append({"action":"drag_motion","ms":(Time.get_ticks_usec()-began)/1000.0})
		await process_frame
	var release:=press.duplicate();release.pressed=false;release.position=start+Vector2(4,0)
	var modern: bool=s.has_method("history_stats")
	var began:=Time.get_ticks_usec();c._gui_input(release);rows.append({"action":"drag_release","ms":(Time.get_ticks_usec()-began)/1000.0,"stages":s.last_timing if modern else {}})
	var frames: Array=[];var prev:=Time.get_ticks_usec()
	while modern and c.edit_pending:
		await process_frame
		var now:=Time.get_ticks_usec();frames.append((now-prev)/1000.0);prev=now
	await process_frame;await RenderingServer.frame_post_draw
	rows.append({"action":"release_validated_visible","ms":(Time.get_ticks_usec()-began)/1000.0,"stages":s.last_timing if modern else {},"plan_build_ms":c.last_plan_build_ms if modern else 0,"max_wait_frame_ms":frames.max() if not frames.is_empty() else 0})
	await process_frame
	for command in [{"op":"rename","title":"Profile edit"}]:
		began=Time.get_ticks_usec();var r: Dictionary=s.dispatch(command);rows.append({"action":command.op,"ms":(Time.get_ticks_usec()-began)/1000.0,"ok":r.ok})
	for i in range(6):
		began=Time.get_ticks_usec();s.undo();rows.append({"action":"undo","ms":(Time.get_ticks_usec()-began)/1000.0})
		began=Time.get_ticks_usec();s.redo();rows.append({"action":"redo","ms":(Time.get_ticks_usec()-began)/1000.0})
	print("REVIEW_EDIT_PROFILE ",JSON.stringify({"entities":p.materialized_snapshot.entities.size(),"recipes":p.recipes.size(),"fixture_input_hash":p.materialized_snapshot.input_hash,"drag_target":c.selected_id,"rows":rows,"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"plans":c.plan_rebuilds}))
	c.queue_free();await process_frame;s.shutdown_jobs();quit()
