extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
var failures: Array=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func finish(s) -> Dictionary:
	var start:=Time.get_ticks_msec();var result: Dictionary={"status":"working"}
	while result.status=="working" and Time.get_ticks_msec()-start<10000:
		await process_frame;result=s.poll_io_job()
	check(result.status!="working","IO timeout")
	return result
func run() -> void:
	var s=S.new()
	if not s.has_method("start_io_job"):
		check(false,"background project/recovery IO API exists");print("PR1_SAVE_JOBS ",JSON.stringify({"checks":checks,"failures":failures}));quit(1);return
	check(s.dispatch({"op":"rename","title":"saved before concurrent edit"}).ok,"fixture")
	var saved: String=s.authority_signature()
	var path: String="user://pr1_save_jobs/map.shwork.json"
	check(s.start_io_job(path).ok,"project IO begins")
	check(not s.start_io_job(path).ok,"overlapping IO refused")
	check(s.dispatch({"op":"rename","title":"newer unsaved edit"}).ok,"editing may continue")
	var result: Dictionary=await finish(s)
	check(result.status=="saved","project IO completes")
	check(s.is_dirty(),"saving older immutable state does not mark newer edits clean")
	var reopened=S.new();check(reopened.load_file(path).ok and reopened.authority_signature()==saved,"saved exact captured state")
	check(s.start_io_job(path).ok,"save newest state")
	result=await finish(s);check(result.status=="saved" and not s.is_dirty(),"latest saved receipt marks only exact authority clean")
	var before:=FileAccess.get_file_as_bytes(path)
	s._replace_file=func(_a,_b):return ERR_CANT_CREATE
	check(s.start_io_job(path).ok,"failure injection dispatched")
	result=await finish(s);check(result.status=="failed" and FileAccess.get_file_as_bytes(path)==before,"failed atomic replacement retains old file")
	s._replace_file=Callable()
	check(s.start_io_job("user://pr1_save_jobs/recovery.json","recovery",{"tool":"select","pending_edit":{}}).ok,"recovery IO begins")
	result=await finish(s);check(result.status=="saved" and reopened.load_recovery("user://pr1_save_jobs/recovery.json").ok,"recovery IO preserves existing contract")
	check(not s.start_io_job("user://pr1_save_jobs/wrong.map.json").ok,"project suffix rejected")
	s.shutdown_jobs();reopened.shutdown_jobs()
	print("PR1_SAVE_JOBS ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
