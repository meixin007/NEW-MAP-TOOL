extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const A=preload("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var s=S.new();var adapter=A.new();root.add_child(adapter)
	var options: Dictionary={"bounds":[0,0,1904,932],"scale":0.6,"layers":false,"transparent_ground":false,"tile_size":256}
	root.mode=Window.MODE_MINIMIZED
	var result: Dictionary=await adapter.export_project(s,OS.get_cmdline_user_args()[0].path_join("hidden"),options)
	root.mode=Window.MODE_WINDOWED
	var valid:=A.validate_bundle(result.path.path_join("manifest.json")) if result.ok else result
	print("REVIEW_BACKGROUND_EXPORT ",JSON.stringify({"result":result.get("ok"),"validation":valid.get("ok"),"error":valid.get("error","")}))
	adapter.queue_free();await process_frame;quit(0 if result.ok and valid.ok else 1)
