extends SceneTree
var failures: Array=[]
func check(ok: bool, message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var wb=load("res://addons/strategic_map_editor/workbench.gd").new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb)
	await process_frame;wb._open_workshop_s1();await process_frame
	var editor=wb.workshop_s1_panel
	check(editor.Samples.install(editor.session,"user://workshop_s1_tests/w3_recovery_"+str(OS.get_process_id())).ok,"fixtures")
	editor.plot_panel.primary.select(6);editor.plot_panel.density.value=0.65
	editor.canvas.plot_points=[[100,100],[500,100]];editor.canvas.plot_shape="polygon";editor.canvas.mode="plot_draw"
	check(editor.save_recovery().ok,"unfinished polygon and parameters saved")
	editor.canvas.cancel();editor.plot_panel.density.value=0.2;editor.restore_recovery()
	check(editor.canvas.plot_points.size()==2 and is_equal_approx(editor.plot_panel.density.value,0.65) and editor.plot_panel.primary.get_selected_metadata()==editor.session.snapshot().asset_refs.keys()[6],"UI restores unfinished region and weighted asset selection")
	editor.canvas.cancel()
	editor.plot_panel.drawn([[100,100],[1400,100],[1400,800],[100,800]],"rectangle",false)
	check(editor.session.job_in_progress() and editor.save_recovery().ok,"pending pure-data job intent saved")
	editor.session.shutdown_jobs();editor.canvas.cancel();editor.restore_recovery()
	check(not editor.plot_panel._recovered_command.is_empty() and not editor.session.has_preview(),"recovery retains intent without silently applying")
	editor.plot_panel.start_job(editor.plot_panel._recovered_command)
	for i in range(600):
		if not editor.session.job_in_progress():break
		await process_frame
	check(editor.session.has_preview(),"resumed candidate remains explicit preview")
	var candidate: Dictionary=editor.session.preview_snapshot()
	editor.canvas.cancel()
	var forged: Dictionary=candidate.duplicate(true)
	if not forged.materialized_snapshot.entities.is_empty():forged.materialized_snapshot.entities[0].ground_xy=[1,1]
	check(not editor.session.restore_preview(forged).ok,"forged recovery preview output rejected")
	check(editor.session.restore_preview(candidate).ok,"valid recovery preview accepted")
	editor.canvas.cancel()
	var before: String=editor.Model.input_hash(editor.session.snapshot())
	editor.plot_panel.drawn([[100,100],[1400,100],[1400,800],[100,800]],"rectangle",false)
	editor.plot_panel.density.value=0.9
	for i in range(600):
		if editor.session._worker==null:break
		await process_frame
	check(not editor.session.has_preview() and editor.Model.input_hash(editor.session.snapshot())==before,"new unapplied parameter input cancels older job result")
	root.remove_child(wb);wb.queue_free();await process_frame
	print("WORKSHOP_PLOT_RECOVERY ",JSON.stringify({"failures":failures}));quit(0 if failures.is_empty() else 1)
