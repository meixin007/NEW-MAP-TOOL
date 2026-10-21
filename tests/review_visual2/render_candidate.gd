extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const A=preload("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd")
var failures: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var output: String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var source=S.new();var loaded: Dictionary=source.load_file("res://samples/fortification_candidate2.shwork.json")
	if not loaded.ok:printerr(loaded);quit(1);return
	var built: Dictionary=source.snapshot();var adapter=A.new();root.add_child(adapter)
	for state in ["empty","built","breach","terrain_only","near","assets"]:
		var p:=built.duplicate(true)
		if state in ["empty","terrain_only"]:p.manual_entities=[]
		if state=="terrain_only":p.recipes=[]
		if state=="breach":
			p.manual_entities=p.manual_entities.filter(func(e):return e.entity_id!="review2.wall.left")
			for e in p.manual_entities:
				if e.kind=="compound":e.room_plan.roof_visible=false
		if state=="assets":
			p.surfaces=[{"surface_id":"ground","height":0}];p.recipes=[];p.manual_entities=p.manual_entities.filter(func(e):return e.entity_id in ["review2.gate","review2.wall.left","review2.wall.side","review2.corner.right"])
			for i in range(p.manual_entities.size()):p.manual_entities[i].ground_xy=[450+i*330,700]
		p.materialized_snapshot=S.Model.materialize(p)
		var s=S.new();s.current_path=source.current_path
		var adopted: Dictionary=s.replace_project(p)
		if not adopted.ok:failures.append(adopted);continue
		var options: Dictionary={"bounds":[-20,240,1610,950],"scale":1.0,"layers":false,"transparent_ground":false,"tile_size":2048}
		if state=="near":options.bounds=[372.5,596.4,820,430];options.scale=1.5
		if state=="assets":options.bounds=[50,260,1470,500];options.scale=1.0
		var exported: Dictionary=await adapter.export_project(s,output.path_join(state),options)
		if not exported.ok:failures.append(exported)
	print("VISUAL2_VIEWS ",JSON.stringify({"failures":failures,"states":"empty/built/breach are geometric construction views, not a complete destruction art system","visual_approval":"pending"}));adapter.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
