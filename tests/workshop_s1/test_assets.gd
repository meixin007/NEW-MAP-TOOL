extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message);printerr("FAIL: ",message)
func _initialize() -> void:
	var path := "res://addons/strategic_map_editor/workshop_s1/asset_descriptor.gd"
	if not FileAccess.file_exists(path): printerr("RED: asset contract not implemented");quit(1);return
	var asset_script = load(path)
	var importer_script = load("res://addons/strategic_map_editor/workshop_s1/asset_importer.gd")
	if asset_script == null or importer_script == null or not asset_script.can_instantiate() or not importer_script.can_instantiate(): printerr("FAIL: asset modules compile");quit(1);return
	var dir := "user://workshop_s1_tests/import_"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var image := Image.create(64,96,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(8,8,48,80),Color("6f7f61"))
	image.save_png(dir.path_join("tree.png"))
	var opaque := Image.create(64,64,false,Image.FORMAT_RGB8)
	opaque.fill(Color.RED)
	opaque.save_png(dir.path_join("opaque.png"))
	var importer = importer_script.new()
	var batch: Dictionary = importer.inspect_batch([dir.path_join("tree.png"),dir.path_join("opaque.png"),dir.path_join("bad.png")],"用户自有灰盒", "fixed_oblique_pending")
	check(batch.items.size() == 3 and batch.valid.size() == 1, "batch reports every valid/invalid item")
	check(not batch.items[1].ok and not batch.items[2].ok,"no-alpha and missing image rejected")
	var a: Dictionary = batch.valid[0].descriptor
	check(asset_script.validate(a).is_empty(),"complete valid descriptor")
	check(a.anchor_px == [32.0,96.0] and a.paint_envelope.size() == 4,"anchor and full paint explicit")
	var b := a.duplicate(true)
	b.anchor_px = [900,0]
	check(not asset_script.validate(b).is_empty(),"anchor outside region rejected")
	b = a.duplicate(true)
	b.texture_ref = "../escape.png"
	check(not asset_script.validate(b).is_empty(),"traversal rejected")
	b = a.duplicate(true)
	b.orientation_variants = {"0":a.asset_id}
	check(not asset_script.orientation(b,45).ok,"unsupported orientation explicitly fails")
	b = a.duplicate(true)
	b.anchor_px=[32,80]
	b.sockets=[{"socket_id":"joint","position_px":[40,60],"direction_deg":0.0,"role":"wall"}]
	var cropped: Dictionary=asset_script.with_region(b,[4,4,56,88])
	check(cropped.ok and cropped.descriptor.anchor_px==[28.0,76.0] and cropped.descriptor.sockets[0].position_px==[36.0,56.0],"crop remaps anchor and socket in same pixel space")
	var session_script = load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
	var s = session_script.new()
	var imported: Dictionary = importer.commit_batch(s,batch,[0])
	check(imported.ok and s.snapshot().asset_refs.size() == 1 and s.undo_stack.size() == 1,"explicit accepted subset one transaction")
	check(not importer.commit_batch(s,batch,[0,1]).ok and s.snapshot().asset_refs.size() == 1,"invalid subset commits nothing")
	var entity := {"entity_id":"tree","kind":"asset","asset_ref":a.asset_id+"@"+a.asset_version,"ground_xy":[500,500],"surface_id":"ground","local_height":0.0,"orientation":0.0,"scale":1.0,"label":"树","management":"manual"}
	check(s.dispatch({"op":"add_manual","entity":entity}).ok,"imported asset placed")
	check(s.dispatch({"op":"add_surface_prototype","surface":{"surface_id":"top","height":60.0,"outline":[[300,300],[700,300],[700,700],[300,700]]}}).ok,"simple raised surface prototype")
	check(s.dispatch({"op":"update_manual","entity_id":"tree","patch":{"surface_id":"top"}}).ok,"explicit support selection")
	var plan_script = load("res://addons/strategic_map_editor/workshop_s1/render_plan.gd")
	var entries: Array = plan_script.build(s.snapshot())
	check(is_equal_approx(entries[0].position.y,440.0),"height offsets draw position")
	check(plan_script.pick(entries,entries[0].position-Vector2(0,40)) == "tree","paint-bound picking uses same height")
	check(entries[0].paint_bounds.intersects(Rect2(450,260,60,25)) and not Rect2(450,260,60,25).has_point(entries[0].position),"canopy visible with root outside view remains in render plan")
	check(not s.dispatch({"op":"update_manual","entity_id":"tree","patch":{"ground_xy":[305,500]}}).ok,"half-supported footprint rejected")
	check(s.dispatch({"op":"update_surface_prototype","surface_id":"top","patch":{"height":100.0}}).ok,"height prototype changes as one transaction")
	entries=plan_script.build(s.snapshot())
	check(is_equal_approx(entries[0].position.y,400.0),"attached draw and pick move after height edit")
	var variant := a.duplicate(true)
	variant.asset_version="v2"
	variant.label="新版本"
	check(s.dispatch({"op":"add_asset_version","descriptor":variant,"adopt_entity_ids":[]}).ok and s.snapshot().manual_entities[0].asset_ref==a.asset_id+"@v1","new asset version never propagates implicitly")
	variant.asset_version="adopted"
	check(s.dispatch({"op":"add_asset_version","descriptor":variant,"adopt_entity_ids":["tree"]}).ok,"unlocked version adoption")
	check(s.undo() and s.redo(),"adopted asset version undo/redo")
	check(s.save_file(dir.path_join("project.shwork.json")).ok,"save content-addressed asset and project")
	var other = session_script.new()
	check(other.load_file(dir.path_join("project.shwork.json")).ok and not other.read_only,"reload pinned dependency")
	check(other.snapshot().manual_entities[0].asset_ref==a.asset_id+"@adopted","adopted version survives disk save/reopen")
	check(other.snapshot().asset_refs == JSON.parse_string(JSON.stringify(s.snapshot().asset_refs)),"asset metadata survives")
	var ref: String = a.asset_id+"@"+a.asset_version
	var blob: String = dir.path_join(s.snapshot().asset_refs[ref].texture_ref)
	var f := FileAccess.open(blob,FileAccess.WRITE)
	f.store_string("damaged")
	f.close()
	var bad_load: Dictionary = other.load_file(dir.path_join("project.shwork.json"))
	check(bad_load.ok and other.read_only and not other.dependency_issues.is_empty(),"bad hash opens read-only with explicit missing resource diagnostic")
	var samples_script=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd")
	var prototype_session=session_script.new()
	check(samples_script.install(prototype_session,dir.path_join("samples")).ok and prototype_session.snapshot().asset_refs.size()==10,"ten original declared graybox samples validate")
	print("WORKSHOP_ASSETS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
