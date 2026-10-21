extends SceneTree
const Editor=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_editor.gd")
const Export=preload("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd")
var failures: Array=[]
var rows: Array=[]
var frames: Array=[]
var action: String=""
var previous:=0
var began:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	var now:=Time.get_ticks_usec()
	if not action.is_empty():frames.append({"action":action,"ms":(now-previous)/1000.0})
	previous=now;return false
func begin(label: String) -> void:
	action=label;began=Time.get_ticks_usec();previous=began
func end(extra: Dictionary={}) -> void:
	await process_frame;await process_frame
	var times: Array=[]
	for row in frames:
		if row.action==action:times.append(row.ms)
	var row: Dictionary={"action":action,"total_ms":(Time.get_ticks_usec()-began)/1000.0,"max_frame_ms":times.max() if not times.is_empty() else 0,"over_33ms":times.filter(func(n):return n>33).size(),"over_50ms":times.filter(func(n):return n>50).size(),"over_100ms":times.filter(func(n):return n>100).size()}
	row.merge(extra);rows.append(row);action=""
func run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[0]
	var editor=Editor.new();root.add_child(editor);await process_frame;await process_frame
	var s=editor.session;check(s.load_file(args[1]).ok,"fixture opens")
	for i in range(12):await process_frame
	var async_io: bool=s.has_method("start_io_job")
	for iteration in range(3):
		begin("project_save_"+str(iteration));var stamp:=Time.get_ticks_usec()
		if async_io:
			check(editor.queue_save(out.path_join("map.shwork.json")).ok,"save dispatch")
			var input_ms: float=(Time.get_ticks_usec()-stamp)/1000.0
			while s.io_in_progress():await process_frame
			await end({"input_ms":input_ms})
		else:
			check(s.save_file(out.path_join("map.shwork.json")).ok,"sync baseline save")
			await end({"input_ms":(Time.get_ticks_usec()-stamp)/1000.0})
		begin("recovery_save_"+str(iteration));stamp=Time.get_ticks_usec()
		if async_io:
			check(editor.queue_recovery().ok,"recovery dispatch")
			var input_ms: float=(Time.get_ticks_usec()-stamp)/1000.0
			while s.io_in_progress():await process_frame
			await end({"input_ms":input_ms})
		else:
			check(editor.save_recovery().ok,"sync baseline recovery")
			await end({"input_ms":(Time.get_ticks_usec()-stamp)/1000.0})
	var adapter=Export.new();root.add_child(adapter)
	begin("export_512")
	var exported: Dictionary=await adapter.export_project(s,out.path_join("export"),{"bounds":[0,0,512,512],"scale":1,"layers":false,"transparent_ground":false,"tile_size":256})
	check(exported.ok,"export success: "+str(exported.get("error","")));await end({"stages":adapter.last_timing if "last_timing" in adapter else {}})
	var result: Dictionary={"failures":failures,"async_io":async_io,"fixture_input_hash":s.view().materialized_snapshot.input_hash,"rows":rows,"frames":frames,"scope":"native rendered editor, immutable 5000/120 fixture; dispatch and operation frames recorded separately"}
	var f:=FileAccess.open(out.path_join("OPERATIONS.json"),FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	result.erase("frames");print("PR1_OPERATIONS ",JSON.stringify(result))
	editor.queue_free();adapter.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
