extends "test_terrain.gd"
func asset(id: String,ref: String,surface: String,xy: Array) -> Dictionary:
	return {"entity_id":id,"kind":"asset","ground_xy":xy,"surface_id":surface,"local_height":0,"asset_ref":ref,"scale":1,"orientation":0,"management":"manual","label":id}
func road(id: String,surface: String,a: Array,b: Array) -> Dictionary:
	return {"recipe_id":id,"kind":"path","path_type":"road","name":id,"surface_id":surface,"seed":42,"style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":"","control_points":[{"point_id":"a","ground_xy":a,"width":24},{"point_id":"b","ground_xy":b,"width":24}],"segments":[{"segment_id":"s","from":"a","to":"b"}]}
func _initialize() -> void:
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=S.new()
	var Samples=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd")
	var P=load("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd");var Plan=load("res://addons/strategic_map_editor/workshop_s1/render_plan.gd");var E=load("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd");var Q=load("res://addons/strategic_map_editor/workshop_s1/support_query.gd")
	check(Samples.install(s,"user://w4_lifecycle").ok,"fixtures")
	check(s.dispatch({"op":"add_terrain","surface":terrace("top")}).ok,"top")
	var refs: Array=s.snapshot().asset_refs.keys();var house:=asset("house",refs[4],"top",[450,450]);var tree:=asset("foot",refs[6],"ground",[760,700])
	check(s.dispatch({"op":"add_manual","entity":house}).ok and s.dispatch({"op":"add_manual","entity":tree}).ok,"house above and tree below")
	check(s.dispatch({"op":"add_manual","entity":asset("top_tree",refs[6],"top",[350,550])}).ok,"tree attaches to upper face")
	var before: Dictionary=s.snapshot();var sockets: Array=E.sockets(before,house);var projected: Vector2=P.project_point(before,Vector2(450,450),"top")
	check(s.dispatch({"op":"update_terrain","surface_id":"top","patch":{"height":100}}).ok,"height transaction")
	var after: Dictionary=s.snapshot();check(after.manual_entities==before.manual_entities,"height retains attachment coordinates and identities")
	check(P.project_point(after,Vector2(450,450),"top")==projected+Vector2(0,-40) and E.sockets(after,house)==sockets,"draw and sockets share support height")
	var socket_ground:=Vector2(sockets[0].ground_xy[0],sockets[0].ground_xy[1])
	check(P.project_point(after,socket_ground,"top")==P.project_point(before,socket_ground,"top")+Vector2(0,-40),"road socket screen point follows height")
	check(P.project_point(after,Vector2(350,550),"top")==P.project_point(before,Vector2(350,550),"top")+Vector2(0,-40) and P.project_point(after,Vector2(760,700))==P.project_point(before,Vector2(760,700)),"top tree follows while foot tree stays")
	check(Plan.pick(Plan.build(after),P.project_point(after,Vector2(450,440),"top"))=="house","pick follows new height")
	check(s.undo() and s.snapshot()==before and s.redo(),"undo redo restores full height edit")
	var bad:=asset("half_house",refs[4],"top",[675,500]);var signature: String=s.Model.input_hash(s.snapshot())
	check(not s.dispatch({"op":"add_manual","entity":bad}).ok and signature==s.Model.input_hash(s.snapshot()),"half unsupported house refused atomically")
	check(not s.dispatch({"op":"update_terrain","surface_id":"top","patch":{"outline":[[200,200],[420,200],[420,650],[200,650]]}}).ok,"outline cannot strand protected house")
	check(not s.dispatch({"op":"delete_terrain","surface_id":"top"}).ok,"attached house blocks terrain deletion")
	check(not s.dispatch({"op":"add_recipe","recipe":road("illegal","ground",[450,800],[450,300])}).ok,"road through cliff refused without ramp")
	var r: Dictionary={"surface_id":"r","kind":"ramp","height":0,"from_surface_id":"ground","to_surface_id":"top","start":[600,820],"end":[600,500],"width":64,"style":"dirt","locked":false}
	check(s.dispatch({"op":"add_terrain","surface":r}).ok,"ramp")
	check(s.dispatch({"op":"add_recipe","recipe":road("low","ground",[600,900],[600,820])}).ok,"ground landing road")
	check(s.dispatch({"op":"add_recipe","recipe":road("rroad","r",[600,820],[600,500])}).ok,"ramp supported road")
	check(s.dispatch({"op":"add_recipe","recipe":road("high","top",[600,500],[600,300])}).ok,"upper landing road")
	check(s.dispatch({"op":"lock_terrain","surface_id":"top","locked":true}).ok and not s.dispatch({"op":"update_terrain","surface_id":"top","patch":{"height":80}}).ok,"explicit terrain lock")
	check(s.dispatch({"op":"lock_terrain","surface_id":"top","locked":false}).ok,"explicit unlock")
	var path: String="user://w4_lifecycle/project.shwork.json";check(s.save_file(path).ok,"save")
	var other=S.new();check(other.load_file(path).ok and other.Model.input_hash(other.snapshot())==s.Model.input_hash(s.snapshot()) and other.Model.Paths.digest(other.snapshot().materialized_snapshot.entities)==s.Model.Paths.digest(s.snapshot().materialized_snapshot.entities) and not other.read_only,"editable lossless reopen")
	# Visually overlapping, physically separate tops must present an explicit choice.
	var overlap=S.new();check(Samples.install(overlap,"user://w4_overlap").ok,"overlap fixtures")
	check(overlap.dispatch({"op":"add_terrain","surface":terrace("back","ground",40,[[100,100],[400,100],[400,350],[100,350]])}).ok,"back hill")
	check(overlap.dispatch({"op":"add_terrain","surface":terrace("front","ground",220,[[100,400],[400,400],[400,650],[100,650]])}).ok,"front physically independent hill")
	var marker: Dictionary={"kind":"marker","local_height":0};var choices: Array=Q.candidates(overlap.snapshot(),Vector2(250,250),marker)
	check(choices.size()==2,"automatic support exposes both valid faces, never silently highest")
	# Ground tree behind front face must be below terrain in painter order.
	check(overlap.dispatch({"op":"add_manual","entity":asset("behind",overlap.snapshot().asset_refs.keys()[6],"ground",[250,380])}).ok,"tree behind raised front")
	var plan: Array=Plan.build(overlap.snapshot());var ti: int=-1;var oi: int=-1
	for i in range(plan.size()):
		if plan[i].entity_id=="surface:front":ti=i
		if plan[i].entity_id=="behind":oi=i
	check(oi>=0 and ti>oi,"ground tree behind cliff is occluded by terrain")
	var f=S.new();check(Samples.install(f,"user://w4_fixed").ok,"fixed fixtures")
	check(f.dispatch({"op":"add_terrain","surface":terrace("top")}).ok,"fixed support")
	var forest: Dictionary={"recipe_id":"forest","kind":"plot","name":"forest","plot_type":"forest","shape":"rectangle","outer":[[205,205],[695,205],[695,645],[205,645]],"holes":[],"surface_id":"top","seed":42,"density":1,"spacing":[64,64],"scale_range":[1,1],"asset_weights":[{"asset_ref":f.snapshot().asset_refs.keys()[6],"weight":1}],"cluster_strength":0,"locked":false}
	check(f.dispatch({"op":"add_recipe","recipe":forest}).ok,"generated forest uses terrain footprint")
	var generated: Array=f.snapshot().materialized_snapshot.entities
	check(generated.size()>5,"nonempty supported forest")
	check(f.dispatch({"op":"update_terrain","surface_id":"top","patch":{"height":90}}).ok and f.Model.Paths.digest(generated)==f.Model.Paths.digest(f.snapshot().materialized_snapshot.entities),"height regeneration preserves forest identities/transforms")
	if not generated.is_empty():
		var rightmost: Dictionary=generated[0]
		for e in generated:
			if e.ground_xy[0]>rightmost.ground_xy[0]:rightmost=e
		check(f.dispatch({"op":"fix_entity","entity_id":rightmost.entity_id}).ok,"fix terrain child")
		check(not f.dispatch({"op":"update_terrain","surface_id":"top","patch":{"outline":[[200,200],[400,200],[400,650],[200,650]]}}).ok,"fixed tree blocks unsupported outline edit")
	# Recovery carries typed W4 drafts and preview; hostile shapes must fail cleanly.
	check(not s.Model.Terrain.validate(s.snapshot()).length(),"terrain remains legal")
	var hostile: Dictionary=s.snapshot();hostile.surfaces[1].edge_widths="broken"
	check(not s.Model.validate(hostile).is_empty(),"hostile edge widths refused without engine error")
	print("WORKSHOP_TERRAIN_LIFECYCLE ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
