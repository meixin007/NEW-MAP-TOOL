extends SceneTree
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var path: String="res://addons/strategic_map_editor/workshop_s1/export_adapter.gd"
	if not ResourceLoader.exists(path):check(false,"W7 export adapter must exist");quit(1);return
	if DisplayServer.get_name()=="headless":check(false,"export pixel test requires real renderer");quit(1);return
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var C=load("res://addons/strategic_map_editor/workshop_s1/compound_model.gd");var s=S.new();s.dispatch({"op":"add_manual","entity":C.entity("yard","ground",Vector2(350,360),C.plan("courtyard"))})
	var args:=OS.get_cmdline_user_args();var output: String=args[0] if not args.is_empty() else "user://export_test_"+str(OS.get_process_id())
	var adapter=load(path).new();root.add_child(adapter)
	var result: Dictionary=await adapter.export_project(s,output,{"scale":1.0,"tile_size":256,"layers":true,"transparent_ground":true,"selected_ids":["yard"]})
	check(result.ok,"frozen atomic export: "+str(result.get("error","")))
	if result.ok:
		var loaded: Dictionary=adapter.validate_bundle(output.path_join("manifest.json"));check(loaded.ok,"hash/dependency validation: "+str(loaded.get("error","")))
		if not loaded.ok:adapter.queue_free();await process_frame;quit(1);return
		check(loaded.manifest.has("render_stack") and not loaded.manifest.tiles.is_empty(),"render stack and fixed tile origins")
		var reopened=S.new();check(reopened.load_file(output.path_join("project.shwork.json")).ok and not reopened.read_only,"clean-directory editable project")
		check(not (await adapter.export_project(s,output,{})).ok,"existing output never overwritten")
	print("WORKSHOP_EXPORT_BUNDLE ",JSON.stringify({"failures":failures}));adapter.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
