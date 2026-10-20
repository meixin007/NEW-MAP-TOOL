extends "../workshop_s1/test_export_bundle.gd"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:check(false,"output and accepted sample required");quit(1);return
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var A=load("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd");var s=S.new();check(s.load_file(args[1]).ok,"accepted sample readable")
	var adapter=A.new();root.add_child(adapter)
	var freeze: String=s.Model.input_hash(s.snapshot());var changed:=false
	adapter.progress.connect(func(_name,current,_total):
		if current==1 and not changed:changed=true;s.dispatch({"op":"rename","title":"during export"}))
	var result: Dictionary=await adapter.export_project(s,args[0].path_join("pixels"),{"bounds":[360,555,830,470],"scale":0.8,"tile_size":256,"layers":true,"transparent_ground":true,"selected_ids":["review2.gate"]})
	check(result.ok,"export accepted scene")
	if not result.ok:adapter.queue_free();quit(1);return
	check(result.manifest.frozen_input_hash==freeze and s.Model.input_hash(s.snapshot())!=freeze,"editing during export cannot enter frozen output")
	var loaded: Dictionary=A.validate_bundle(args[0].path_join("pixels/manifest.json"));check(loaded.ok,"bundle drawing stack matches rebuilt project: "+str(loaded.get("error","")))
	var full:=Image.load_from_file(args[0].path_join("pixels/composite.png"));full.convert(Image.FORMAT_RGBA8)
	var viewport:=SubViewport.new();viewport.size=full.get_size();viewport.transparent_bg=true;viewport.disable_3d=true;root.add_child(viewport)
	var preview=load("res://addons/strategic_map_editor/workshop_s1/ui/readonly_preview.gd").new();viewport.add_child(preview);preview.size=Vector2(viewport.size)
	check((await preview.open_manifest(args[0].path_join("pixels/manifest.json"))).ok,"readonly Godot preview loads strict bundle")
	check(not preview.session.dispatch({"op":"rename","title":"forbidden"}).ok,"readonly preview refuses editing authority")
	preview.canvas.render_only=true;preview.canvas.render_background=false;preview.canvas.draw_paper=true;preview.canvas.zoom=result.manifest.scale;preview.canvas.pan=-Vector2(result.manifest.bounds[0],result.manifest.bounds[1])*float(result.manifest.scale);preview.canvas.size=Vector2(viewport.size);preview.canvas.queue_redraw();viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;await RenderingServer.frame_post_draw;await process_frame
	var preview_image: Image=A.straight_alpha(viewport.get_texture().get_image());check(preview_image.get_data()==full.get_data(),"readonly preview uses identical frozen geometry, scale, bounds and pixels")
	viewport.queue_free()
	var tiles:=Image.create(full.get_width(),full.get_height(),false,Image.FORMAT_RGBA8);tiles.fill(Color.TRANSPARENT)
	for item in result.manifest.tiles:
		var page:=Image.load_from_file(args[0].path_join("pixels").path_join(item.path));page.convert(Image.FORMAT_RGBA8);tiles.blit_rect(page,Rect2i(Vector2i.ZERO,page.get_size()),Vector2i(item.pixel_origin[0],item.pixel_origin[1]))
	var layers:=reconstruct_layers(args[0].path_join("pixels"),result.manifest.layers,full.get_size())
	var rows: Array=[]
	# Freeze threshold before measurement: max channel error 2, >=99.99% channels within 1.
	for pair in [["tiles",tiles],["layers",layers]]:
		var a:=full.get_data();var b: PackedByteArray=pair[1].get_data();var maximum:=0;var above_one:=0
		for i in range(a.size()):
			var delta:=absi(int(a[i])-int(b[i]));maximum=maxi(maximum,delta)
			if delta>1:above_one+=1
		var passed: bool=maximum<=2 and float(above_one)/a.size()<=0.0001;check(passed,"pixel reconstruction "+pair[0]+" max="+str(maximum)+" above_one="+str(above_one));rows.append({"kind":pair[0],"max_channel_error":maximum,"fraction_above_one":float(above_one)/a.size(),"passed":passed})
	var old_hash:=FileAccess.get_sha256(args[0].path_join("pixels/composite.png"))
	var cancelled: bool=false
	var cancellation: Dictionary={"requested_ms":0}
	adapter.progress.connect(func(_name,current,_total):
		if current==1 and not cancelled:cancelled=true;cancellation.requested_ms=Time.get_ticks_msec();adapter.cancel())
	var cancel_result: Dictionary=await adapter.export_project(s,args[0].path_join("cancelled"),{"scale":0.4});check(not cancel_result.ok and not DirAccess.dir_exists_absolute(args[0].path_join("cancelled")),"cancel never publishes partial manifest")
	cancellation.latency_ms=Time.get_ticks_msec()-int(cancellation.requested_ms)
	adapter.progress.disconnect(adapter.progress.get_connections()[-1].callable)
	adapter.write_hook=func(relative,_bytes):return relative!="ground.png"
	var failed: Dictionary=await adapter.export_project(s,args[0].path_join("failed"),{"scale":0.4});check(not failed.ok and not DirAccess.dir_exists_absolute(args[0].path_join("failed")),"write failure never publishes partial manifest")
	check(old_hash==FileAccess.get_sha256(args[0].path_join("pixels/composite.png")),"earlier export preserved")
	var manifest_path: String=args[0].path_join("pixels/manifest.json");var manifest_text:=FileAccess.get_file_as_string(manifest_path);var malformed: Dictionary=JSON.parse_string(manifest_text);malformed.project_ref="../escape.shwork.json"
	var broken:=FileAccess.open(manifest_path,FileAccess.WRITE);broken.store_string(JSON.stringify(malformed));broken.close();check(not A.validate_bundle(manifest_path).ok,"traversal manifest refused")
	broken=FileAccess.open(manifest_path,FileAccess.WRITE);broken.store_string(manifest_text);broken.close()
	var missing: String=args[0].path_join("pixels/ground.png");DirAccess.rename_absolute(missing,missing+".held");check(not A.validate_bundle(manifest_path).ok,"missing dependency refused");DirAccess.rename_absolute(missing+".held",missing);check(A.validate_bundle(manifest_path).ok,"original bundle restored after fault checks")
	var file:=FileAccess.open(args[0].path_join("PIXEL_RESULT.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"threshold":{"max_channel_error":2,"fraction_above_one":0.0001},"comparisons":rows,"cancellation":cancellation},"\t"));file.close();print("VISUAL2_EXPORT_PIXELS ",JSON.stringify({"failures":failures,"comparisons":rows,"cancellation":cancellation}));adapter.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func reconstruct_layers(directory: String,items: Array,size: Vector2i) -> Image:
	# Independent straight-alpha source-over reference. Accumulate in float64 and
	# quantize once, avoiding repeated RGBA8 rounding or Image blend format rules.
	var values:=PackedFloat64Array();values.resize(size.x*size.y*4)
	for item in items:
		var layer:=Image.load_from_file(directory.path_join(item.path));layer.convert(Image.FORMAT_RGBA8)
		var bytes:=layer.get_data()
		for i in range(0,bytes.size(),4):
			if bytes[i+3]==0:continue
			var alpha: float=bytes[i+3]/255.0
			var prior: float=values[i+3]*(1.0-alpha)
			var total: float=alpha+prior
			for c in range(3):values[i+c]=(bytes[i+c]*alpha+values[i+c]*prior)/total
			values[i+3]=total
	var output:=PackedByteArray();output.resize(values.size())
	for i in range(0,output.size(),4):
		for c in range(3):output[i+c]=clampi(roundi(values[i+c]),0,255)
		output[i+3]=clampi(roundi(values[i+3]*255.0),0,255)
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,output)
