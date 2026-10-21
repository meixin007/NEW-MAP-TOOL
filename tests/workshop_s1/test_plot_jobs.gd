extends SceneTree
var failures: Array=[]
func check(ok: bool, message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var script=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
	var s=script.new()
	if not s.has_method("start_preview_job"):check(false,"cancellable async candidate boundary must exist");quit(1);return
	check(s.start_preview_job({"op":"rename","title":"async"}).ok,"start job")
	var state: Dictionary={}
	for i in range(600):
		state=s.poll_preview_job()
		if state.status not in ["working","idle"]:break
		await process_frame
	check(state.status=="ready" and s.snapshot().title!="async" and s.preview_snapshot().title=="async","worker adopts preview only, no early history")
	check(s.commit_preview().ok and s.snapshot().title=="async" and s.undo_stack.size()==1,"one complete async transaction")
	check(s.start_preview_job({"op":"rename","title":"cancelled"}).ok,"second job")
	s.cancel_preview_job();s.cancel_preview()
	for i in range(600):
		state=s.poll_preview_job()
		if state.status!="working":break
		await process_frame
	check(not s.has_preview() and s.snapshot().title=="async","cancelled old job cannot publish")
	check(s.start_preview_job({"op":"rename","title":"stale"}).ok,"stale job")
	check(s.dispatch({"op":"rename","title":"newer"}).ok,"newer input remains authoritative")
	for i in range(600):
		state=s.poll_preview_job()
		if state.status!="working":break
		await process_frame
	check(not s.has_preview() and s.snapshot().title=="newer","revision mismatch discards old worker result")
	s.shutdown_jobs()
	print("WORKSHOP_PLOT_JOBS ",JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
