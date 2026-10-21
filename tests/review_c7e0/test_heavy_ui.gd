extends "../workshop_s1/test_templates_ui.gd"
const Probe=preload("../workshop_s1/frame_probe.gd")
var measurements: Array=[]
func wait_candidate() -> void:
	var start:=Time.get_ticks_msec()
	while editor.session.job_in_progress() and Time.get_ticks_msec()-start<30000:await process_frame
	await process_frame;await process_frame
	check(editor.session.has_preview(),"full candidate ready: "+editor.status.text)
func measured_preview(caption: String,apply_caption: String) -> void:
	var probe:=Probe.new();probe.canvas=editor.canvas;root.add_child(probe);probe.begin()
	var stamp:=Time.get_ticks_usec();await click_button(caption)
	var macro_ms: float=(Time.get_ticks_usec()-stamp)/1000.0
	await wait_candidate();await click_button(apply_caption);await settle(15)
	probe.active=false
	measurements.append({"action":caption,"click_macro_ms_includes_settle":macro_ms,"total_ms":(Time.get_ticks_usec()-stamp)/1000.0,"max_frame_ms":probe.rows.map(func(r):return r.frame_ms).max(),"refresh_ms":editor.last_refresh_ms,"stages":editor.session.last_timing.duplicate(),"trajectory":probe.rows})
	probe.queue_free()
func run() -> void:
	wb=load("res://addons/strategic_map_editor/workbench.gd").new();wb.restore_last_map_on_start=false;wb.layout_persistence_enabled=false;root.add_child(wb);current_scene=wb
	await settle(20);await click_button("Canvas 制作 · workshop_s1");await settle(15);editor=wb.workshop_s1_panel
	await project_file_dialog("open",OS.get_cmdline_user_args()[1])
	check(editor.session.view().materialized_snapshot.entities.size()==5000,"normal heavy UI fixture open")
	await asset_tab(editor,4)
	for i in range(editor.terrain_panel.surfaces.item_count):
		if editor.terrain_panel.surfaces.get_item_metadata(i)=="profile.top":await select_list(editor.terrain_panel.surfaces,i);break
	await text_in(editor.terrain_panel.height.get_line_edit(),"21")
	await measured_preview("预览地形属性／顶点／所选边","应用地形预览（一次撤销）")
	check(editor.session.view().surfaces[-1].height==21,"normal heavy terrain edit adopted")
	await asset_tab(editor,3)
	for i in range(editor.plot_panel.recipes.item_count):
		if editor.plot_panel.recipes.get_item_metadata(i)=="review.profile.forest":await select_list(editor.plot_panel.recipes,i);break
	await text_in(editor.plot_panel.density.get_line_edit(),"0.5")
	await measured_preview("预览所选区域参数","应用区域预览（一次撤销）")
	check(editor.session.view().recipes[0].density==0.5,"normal heavy density edit adopted")
	var file:=FileAccess.open(output.path_join("HEAVY_UI.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"measurements":measurements,"scope":"actual workbench controls; frozen editing UI-Core 5000/120 variant"},"\t"));file.close()
	for m in measurements:m.erase("trajectory")
	print("REVIEW_HEAVY_UI ",JSON.stringify({"failures":failures,"measurements":measurements}))
	wb.queue_free();await settle(10);quit(0 if failures.is_empty() else 1)
