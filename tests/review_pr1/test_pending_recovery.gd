extends SceneTree
const Editor=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_editor.gd")
const Pending=preload("res://addons/strategic_map_editor/workshop_s1/pending_edit.gd")
const Delayed=preload("delayed_session.gd")
var failures: Array=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func xy(value: Array,x: float,y: float) -> bool:
	return is_equal_approx(float(value[0]),x) and is_equal_approx(float(value[1]),y)
func _initialize() -> void:call_deferred("run")
func wait_idle(s) -> void:
	var start:=Time.get_ticks_msec()
	while s._worker!=null and Time.get_ticks_msec()-start<5000:await process_frame
	check(s._worker==null,"worker drained within timeout")
func run() -> void:
	var editor=Editor.new();editor.session=Delayed.new();root.add_child(editor);await process_frame;await process_frame
	var s=editor.session;var c=editor.canvas
	check(s.dispatch({"op":"add_manual","entity":{"entity_id":"recovery.marker","kind":"marker","ground_xy":[200,200],"surface_id":"ground","local_height":0,"label":"recovery"}}).ok,"fixture")
	if s.view().manual_entities.is_empty():editor.queue_free();await process_frame;quit(1);return
	editor.select_entity("recovery.marker");c._drag_entity=s.view().manual_entities[0];c._dragging=true
	c._preview_drag({"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[220,210]}})
	var first: Dictionary=editor.capture_draft()
	editor._recovery_revision=s.revision;editor._recovery_draft=first
	check(not editor.has_unsaved_editor_session(),"receipt covers unchanged target")
	c._preview_drag({"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[260,240]}})
	check(first!=editor.capture_draft(),"two drag targets produce distinct recovery drafts")
	check(editor.has_unsaved_editor_session(),"new target after receipt becomes dirty again")
	check(editor.save_recovery().ok,"drag target saved through actual recovery writer")
	check(JSON.parse_string(FileAccess.get_file_as_string(editor.RECOVERY)).schema_version==2,"pending intent uses v2 envelope, older readers must reject it")
	var envelope: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(editor.RECOVERY))
	var malformed_path: String="user://malformed-recovery.json"
	for mode in ["bad_pending_type","unknown_schema","v1_pending","bad_project"]:
		var malformed:=envelope.duplicate(true)
		if mode=="bad_pending_type":malformed.draft.pending_edit=7
		elif mode=="unknown_schema":malformed.schema_version=99
		elif mode=="v1_pending":malformed.schema_version=1
		else:malformed.project={}
		var file:=FileAccess.open(malformed_path,FileAccess.WRITE);file.store_string(JSON.stringify(malformed));file.close()
		var reader=Delayed.new();check(not reader.load_recovery(malformed_path).ok,"reject malformed envelope "+mode)
	c.cancel();editor.restore_recovery()
	check(s.has_pending_intent() and xy(s.pending_edit().command.patch.ground_xy,260,240),"reopen restores drag target")
	check(not s.dispatch({"op":"rename","title":"unrelated"}).ok,"restored intent guards unrelated commits")
	check(not s.start_preview_job({"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[400,400]}}).ok,"restored intent guards replacement by another preview")
	check(xy(s.view().manual_entities[0].ground_xy,200,200) and not s.has_preview(),"restored target never auto-applied")
	c.cancel();check(not s.has_pending_intent() and c._transient_command.is_empty(),"cancel clears intent and ghost")
	# Release, save while the full transaction is deliberately delayed.
	c._drag_entity=s.view().manual_entities[0]
	c._preview_drag({"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[280,250]}})
	check(c._commit_drag().ok,"release starts validation")
	check(editor.capture_draft().pending_edit.stage=="validating","validating stage captured")
	check(editor.save_recovery().ok,"validating recovery saved")
	var rev: int=s.revision;editor.restore_recovery();await wait_idle(s)
	check(xy(s.view().manual_entities[0].ground_xy,200,200) and s.has_pending_intent(),"late old worker cannot adopt after recovery")
	editor.resume_pending_edit();await wait_idle(s)
	check(s.has_preview() and xy(s.view().manual_entities[0].ground_xy,200,200),"revalidation remains explicit preview")
	check(xy(s.preview_view().manual_entities[0].ground_xy,280,250),"revalidated target preserved")
	var ready_save: Dictionary=editor.save_recovery();check(ready_save.ok,"ready stage recovery saved "+str(ready_save))
	c.cancel();editor.restore_recovery()
	check(s.pending_edit().stage=="ready" and not s.has_preview(),"ready intent restored for revalidation")
	editor.resume_pending_edit();await wait_idle(s)
	check(s.commit_preview().ok and xy(s.view().manual_entities[0].ground_xy,280,250),"explicit apply adopts exactly once")
	check(s.undo_stack.size()==1 and not s.commit_preview().ok,"repeat apply refused")
	check(s.undo() and xy(s.view().manual_entities[0].ground_xy,200,200),"undo restored edit")
	check(s.redo() and xy(s.view().manual_entities[0].ground_xy,280,250),"redo restored edit")
	# Property panel uses the same envelope even after its dirty flag is cleared.
	editor.select_entity("recovery.marker");editor.x_field.value=310;editor.y_field.value=265
	check(editor.queue_candidate({"op":"update_entity","entity_id":"recovery.marker","patch":editor.object_patch()},"object",true).ok,"property entry queued")
	editor._property_dirty=false
	var property_save: Dictionary=editor.save_recovery();check(property_save.ok,"property validation intent saved "+str(property_save))
	editor.restore_recovery();await wait_idle(s)
	check(s.has_pending_intent() and xy(s.pending_edit().command.patch.ground_xy,310,265),"property target recovered")
	c.cancel()
	# Path point motion and property input share the same identity/target contract.
	var path={"recipe_id":"recovery.path","kind":"path","path_type":"road","name":"path","control_points":[{"point_id":"a","ground_xy":[100,500],"width":24},{"point_id":"b","ground_xy":[600,500],"width":24}],"segments":[{"segment_id":"ab","from":"a","to":"b"}],"seed":42,"surface_id":"ground","style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
	check(s.dispatch({"op":"add_recipe","recipe":path}).ok,"path fixture")
	c.mode="path_edit";c.selected_recipe_id="recovery.path";c.selected_point_id="a";c._point_dragging=true
	c._preview_drag({"op":"update_path_point","recipe_id":"recovery.path","point_id":"a","patch":{"ground_xy":[120,520]}})
	check(editor.save_recovery().ok,"path drag intent saved")
	c.cancel();editor.restore_recovery()
	check(s.pending_edit().command.point_id=="a" and xy(s.pending_edit().command.patch.ground_xy,120,520),"path point identity and target restored")
	editor.resume_pending_edit();await wait_idle(s)
	check(s.has_preview() and s.commit_preview().ok,"path restored through full transaction")
	# Invalid baseline/version/non-data values are rejected before resumption.
	var intent:=Pending.create(s.view(),{"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[320,270]}},"dragging")
	for key in ["project_id","base_input_hash","generator_version","asset_versions_hash"]:
		var bad:=intent.duplicate(true);bad[key]="wrong";check(not Pending.validate(bad,s.view()).is_empty(),"reject changed "+key)
	var bad:=intent.duplicate(true);bad.command.patch.ground_xy=[INF,0];check(not Pending.validate(bad,s.view()).is_empty(),"reject nonfinite target")
	bad=intent.duplicate(true);bad.command.callback=func():return true;check(not Pending.validate(bad,s.view()).is_empty(),"reject Callable")
	bad.clear()
	for owner in ["terrain","room","direct_edit","recovery"]:
		var draft: Dictionary=editor.capture_draft();draft.w5_canvas.preview_owner=owner
		check(s._validate_recovery_draft(draft,s.view()).is_empty(),"recovery supports owner "+owner)
	check(s.dispatch({"op":"set_entity_locked","entity_id":"recovery.marker","locked":true}).ok,"lock fixture")
	intent=Pending.create(s.view(),{"op":"update_entity","entity_id":"recovery.marker","patch":{"ground_xy":[340,280]}},"validating")
	check(s.restore_pending_edit(intent).ok and s.resume_pending_edit().ok,"locked target reaches full validation")
	editor._preview_owner="recovery";await wait_idle(s)
	check(not s.has_preview() and xy(s.view().manual_entities[0].ground_xy,280,250),"lock still prevents restored mutation")
	c.cancel();editor.queue_free();await process_frame
	print("PR1_PENDING_RECOVERY ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
