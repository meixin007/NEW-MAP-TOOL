extends SceneTree
var failures: Array=[]
func check(ok: bool, message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var wb=load("res://addons/strategic_map_editor/workbench.gd").new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb)
	await process_frame;wb._open_workshop_s1()
	for i in range(20):await process_frame
	var editor=wb.workshop_s1_panel;var panel=editor.plot_panel
	if not panel.has_method("add_weight_row"):
		check(false,"normal region panel must support more than two weighted assets");root.remove_child(wb);wb.queue_free();await process_frame;quit(1);return
	check(editor.Samples.install(editor.session,"user://workshop_s1_tests/mix_"+str(OS.get_process_id())).ok,"fixtures")
	panel.refresh();var refs: Array=editor.session.snapshot().asset_refs.keys();panel.primary.select(0);panel.secondary.select(2)
	for i in range(2,6):panel.add_weight_row(refs[i],0.2+i*0.1)
	var expected: Array=panel.parameters().asset_weights
	check(expected.size()==6,"six individually weighted fixed versions")
	panel.refresh();check(panel.parameters().asset_weights==expected,"refresh preserves all six weights")
	var r: Dictionary=panel.parameters();r.merge({"recipe_id":"mixed","kind":"plot","name":"mixed","shape":"rectangle","outer":[[100,100],[1000,100],[1000,700],[100,700]],"holes":[],"locked":false});r.density=0.0
	check(editor.session.dispatch({"op":"add_recipe","recipe":r}).ok,"six-asset recipe uses existing contract")
	panel.select_recipe("mixed");check(panel.parameters().asset_weights==expected,"select/reopen does not truncate six refs to two")
	panel.extra_rows[0].weight.get_line_edit().text="0."
	var draft: Dictionary=panel.capture_draft();panel.clear_extra_weights();panel.restore_draft(draft)
	check(panel.parameters().asset_weights==expected and panel.extra_rows[0].weight.get_line_edit().text=="0.","unfinished extra weight text and refs restored")
	check(editor.save_recovery().ok,"validated full recovery with extra weights")
	panel.clear_extra_weights();editor.restore_recovery()
	check(panel.parameters().asset_weights==expected,"six weights survive full project recovery")
	var bad: Dictionary=draft.duplicate(true);bad.extra_rows[0].asset_ref="missing@v1"
	check(not editor.session._validate_recovery_draft({"plot_fields":bad},editor.session.snapshot()).is_empty(),"recovery refuses unknown extra asset")
	bad=draft.duplicate(true);bad.extra_rows[0].weight="false"
	check(not editor.session._validate_recovery_draft({"plot_fields":bad},editor.session.snapshot()).is_empty(),"recovery refuses nonnumeric extra weight")
	for i in range(20):panel.add_weight_row(refs[6],0.5)
	check(panel.extra_rows.size()==14,"normal UI caps total at sixteen weighted slots")
	print("WORKSHOP_PLOT_WEIGHTS ",JSON.stringify({"failures":failures}));root.remove_child(wb);wb.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
