extends SceneTree
## Adapted from the independent review draft; execution status is in test results.
## Copy to a disposable source worktree at tests/review_c7e0/test_review_contracts.gd.
## Run with Godot 4.6.1 --headless --path <copy> --script res://tests/review_c7e0/test_review_contracts.gd
## In-memory synthetic fixtures only: no user map/save/asset file is written.
const Session = preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const Model = preload("res://addons/strategic_map_editor/workshop_s1/project_model.gd")
const Geometry = preload("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd")
const SurfaceProject = preload("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
const Overrides = preload("res://addons/strategic_map_editor/workshop_s1/override_resolver.gd")
const Export = preload("res://addons/strategic_map_editor/workshop_s1/export_adapter.gd")
const Asset = preload("res://addons/strategic_map_editor/workshop_s1/asset_descriptor.gd")
const Snap = preload("res://addons/strategic_map_editor/workshop_s1/snap_resolver.gd")
var failures: Array[String] = []
var check_count := 0

func expect(value: bool, label: String) -> void:
	check_count += 1
	if not value:
		failures.append(label)
		printerr("REVIEW_FAILED: ", label)

func descriptor(id: String, version: String = "v1") -> Dictionary:
	var sha := "0".repeat(64)
	return {
		"asset_id":id, "asset_version":version, "style_id":"review_synthetic",
		"texture_ref":"assets/"+sha+".png", "texture_sha256":sha,
		"texture_size_px":[100,100], "region_px":[0,0,100,100],
		"anchor_px":[50,50], "nominal_size_units":[100,100],
		"ground_footprint":[[-10,-5],[10,-5],[10,5],[-10,5]],
		"paint_envelope":[[0,0],[100,0],[100,100],[0,100]],
		"sockets":[], "orientation_variants":{"0":id},
		"shadow_mode":"none", "render_parts":[], "state_variants":{},
		"source_notice":"Synthetic in-memory regression descriptor; PNG intentionally not loaded",
		"label":id, "tags":[], "category":"object"
	}

func entity(id: String, asset_ref: String, height: float = 0.0) -> Dictionary:
	return {"entity_id":id,"kind":"asset","ground_xy":[500,500],
		"surface_id":"ground","local_height":height,"label":id,
		"management":"manual","asset_ref":asset_ref,"orientation":0.0,
		"scale":1.0,"locked":false}

func locked_asset_update() -> void:
	var session = Session.new()
	var a := descriptor("review_asset")
	var added: Dictionary = session.dispatch({"op":"add_assets","assets":{"review_asset@v1":a}})
	expect(added.get("ok",false), "setup: descriptor accepted")
	if not added.get("ok",false):
		printerr(added)
		return
	var e := entity("review.manual.locked", "review_asset@v1")
	e.locked = true
	var put: Dictionary = session.dispatch({"op":"add_manual","entity":e})
	expect(put.get("ok",false), "setup: locked manual entity accepted")
	if not put.get("ok",false):
		printerr(put)
		return
	var before: Dictionary = session.snapshot()
	var next := a.duplicate(true)
	next.asset_version = "v2"
	next.anchor_px = [52,50] # Changes visible placement without changing ground footprint.
	var adopted: Dictionary = session.dispatch({"op":"add_asset_version","descriptor":next,
		"adopt_entity_ids":[e.entity_id]})
	expect(not adopted.get("ok",false), "REV-NMT-01: locked entity must reject asset adoption without explicit unlock")
	var after: Dictionary = session.snapshot()
	expect(after.manual_entities[0].asset_ref == before.manual_entities[0].asset_ref,
		"REV-NMT-01: locked entity asset reference unchanged")

func gate_direction() -> void:
	var p: Dictionary = Model.blank()
	p.style_profile.ground_matrix = [1.0,0.14,-0.30,0.72]
	var a := descriptor("review_gate")
	a.category = "gate"
	a.ground_footprint = [[-50,-50],[50,-50],[50,50],[-50,50]]
	a.passage_width_units = 30.0
	var projected_axis: Vector2 = SurfaceProject.project_point(p,Vector2(0,1))-SurfaceProject.project_point(p,Vector2.ZERO)
	var angle := fposmod(rad_to_deg(projected_axis.angle()),360.0)
	a.sockets = [{"socket_id":"road_center","position_px":[50,50],
		"role":"road","direction_deg":angle}]
	p.asset_refs = {"review_gate@v1":a}
	var gate := entity("review.gate", "review_gate@v1")
	var ribbon := {"kind":"ribbon","role":"road","surface_id":"ground",
		"polygons":[[[490,400],[510,400],[510,600],[490,600]]]}
	expect(Overrides._gate_opening(p,ribbon,gate),
		"REV-NMT-02: a ground-vertical road must pass an aligned gate under oblique projection")
	# Positive control: identity mapping, same ground geometry.
	p.style_profile.ground_matrix = [1.0,0.0,0.0,1.0]
	p.asset_refs["review_gate@v1"].sockets[0].direction_deg = 90.0
	expect(Overrides._gate_opening(p,ribbon,gate), "control: identity-projection gate must accept road")

func socket_height() -> void:
	var p: Dictionary = Model.blank()
	var a := descriptor("review_socket_a")
	var b := descriptor("review_socket_b")
	a.sockets = [{"socket_id":"a","position_px":[50,50],"role":"attachment","direction_deg":0.0}]
	b.sockets = [{"socket_id":"b","position_px":[50,50],"role":"attachment","direction_deg":180.0}]
	p.asset_refs = {"review_socket_a@v1":a, "review_socket_b@v1":b}
	var source := entity("review.source", "review_socket_a@v1", 0.0)
	var target := entity("review.target", "review_socket_b@v1", 40.0)
	var result: Dictionary = Geometry.snap(p,source,"a",target,"b")
	# Rejection is acceptable; success must yield genuinely coincident sockets.
	if not result.get("ok",false):
		expect(true, "REV-NMT-09: incompatible heights rejected")
		return
	var moved := source.duplicate(true)
	moved.ground_xy = result.ground_xy
	if result.has("local_height"):
		moved.local_height = result.local_height
	var sa: Dictionary = Geometry.sockets(p,moved)[0]
	var sb: Dictionary = Geometry.sockets(p,target)[0]
	var pa: Vector2 = SurfaceProject.project_point(p,Vector2(sa.ground_xy[0],sa.ground_xy[1]),moved.surface_id,moved.local_height)
	var pb: Vector2 = SurfaceProject.project_point(p,Vector2(sb.ground_xy[0],sb.ground_xy[1]),target.surface_id,target.local_height)
	expect(pa.distance_to(pb)<0.01, "REV-NMT-09: reported-success snap cannot retain a 40-unit projected height gap")

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	locked_asset_update()
	gate_direction()
	socket_height()
	atomic_adoption()
	fixed_adoption()
	crop_and_export()
	direction_contract()
	alpha_picking()
	await immutable_and_jobs()
	print(JSON.stringify({"kind":"review_contract_regression","checks":check_count,
		"failures":failures,"fixture":"synthetic_in_memory","project_files_written":false},"\t"))
	quit(0 if failures.is_empty() else 1)

func atomic_adoption() -> void:
	var s=Session.new();var a:=descriptor("batch")
	expect(s.dispatch({"op":"add_assets","assets":{"batch@v1":a}}).ok,"batch setup")
	var one:=entity("unlocked","batch@v1");var two:=entity("locked","batch@v1");two.locked=true;two.ground_xy=[600,600]
	s.dispatch({"op":"add_manual","entity":one});s.dispatch({"op":"add_manual","entity":two})
	var b:=a.duplicate(true);b.asset_version="v2";b.anchor_px=[52,50]
	var sig: String=s.authority_signature();var size: int=s.undo_stack.size()
	expect(not s.dispatch({"op":"add_asset_version","descriptor":b,"adopt_entity_ids":["unlocked","locked"]}).ok,"mixed batch rejected")
	expect(s.authority_signature()==sig and not s.snapshot().asset_refs.has("batch@v2") and s.undo_stack.size()==size,"rejected batch changes no version/entity/history")
	expect(not s.dispatch({"op":"add_asset_version","descriptor":b,"adopt_entity_ids":["missing.generated"]}).ok,"nonmanual/fixed/generated target rejected before version insert")
	expect(s.dispatch({"op":"add_asset_version","descriptor":b,"adopt_entity_ids":["unlocked"]}).ok,"unlocked adoption accepted")
	expect(s.undo() and s.snapshot().manual_entities[0].asset_ref=="batch@v1","adoption undo restores version")
	expect(s.redo() and s.snapshot().manual_entities[0].asset_ref=="batch@v2","adoption redo exact")
	var p: Dictionary=s.snapshot();p.prefab_instances=[{"instance_id":"group","template_id":"fixture","template_version":"v1","kind":"asset_composite","label":"locked group","entity_ids":["locked"],"recipe_ids":[],"surface_ids":[]}]
	p.materialized_snapshot=Model.materialize(p)
	expect(s.replace_project(p).ok,"grouped locked member fixture adopted")
	# Entity locks remain authoritative whether or not a group also references it.
	expect(not s.dispatch({"op":"add_asset_version","descriptor":dict_version(a,"v3"),"adopt_entity_ids":["locked"]}).ok,"locked grouped member cannot adopt")

func dict_version(a: Dictionary,version: String) -> Dictionary:
	var b:=a.duplicate(true);b.asset_version=version;return b

func fixed_adoption() -> void:
	var s=Session.new();var a:=descriptor("generated")
	s.dispatch({"op":"add_assets","assets":{"generated@v1":a}})
	var r: Dictionary={"recipe_id":"generated.region","kind":"plot","name":"region","plot_type":"scatter","shape":"rectangle","outer":[[100,100],[400,100],[400,400],[100,400]],"holes":[],"surface_id":"ground","seed":42,"density":1,"spacing":[96,96],"scale_range":[1,1],"asset_weights":[{"asset_ref":"generated@v1","weight":1}],"cluster_strength":0,"locked":false}
	expect(s.dispatch({"op":"add_recipe","recipe":r}).ok,"generated target fixture")
	var id: String=s.view().materialized_snapshot.entities[0].entity_id
	expect(s.dispatch({"op":"fix_entity","entity_id":id}).ok,"generated target fixed")
	var sig: String=s.authority_signature()
	expect(not s.dispatch({"op":"add_asset_version","descriptor":dict_version(a,"v2"),"adopt_entity_ids":[id]}).ok and s.authority_signature()==sig,"actual fixed generated entity rejects direct adoption atomically")


func crop_and_export() -> void:
	var a:=descriptor("crop");a.sockets=[{"socket_id":"s","role":"wall","position_px":[80,50],"direction_deg":0}]
	var same:=Asset.with_region(a,[10,10,80,80]);var resized:=Asset.with_region(a,[10,10,80,80],"rescale")
	expect(same.ok and same.descriptor.nominal_size_units==[80.0,80.0],"default crop keeps pixel scale")
	expect((same.descriptor.sockets[0].position_px[0]-same.descriptor.anchor_px[0])*same.descriptor.nominal_size_units[0]/80.0==30,"crop socket remains 30 ground/display units from anchor")
	expect(resized.ok and resized.descriptor.nominal_size_units[0]==100 and resized.descriptor.ground_footprint==a.ground_footprint,"explicit rescale retains authored independent footprint")
	expect(not Asset.with_region(a,[10,10,80,80],"unknown").ok,"unknown crop mode rejected")
	var page: Dictionary={"pixel_origin":[2048,2048],"pixel_size":[15,27],"stored_size":[15,27],"core_rect":[0,0,15,27],"gutter":0}
	expect(Export.valid_page(page,Vector2i(2063,2075)),"edge page core contract")
	page.gutter=8;expect(not Export.valid_page(page,Vector2i(2063,2075)),"false physical gutter rejected")
	expect(not Export.estimate_output(Vector2i(8192,8192),5000,{"layers":true}).ok,"large layered export rejected before allocation")
	expect(Export.estimate_output(Vector2i(512,512),5000,{"layers":true}).ok,"small layered export positive control")

func direction_contract() -> void:
	var p:=Model.blank();p.style_profile.ground_matrix=[1.0,0.14,-0.30,0.72]
	for d in [Vector2.RIGHT,Vector2.DOWN,Vector2(2,3).normalized()]:
		var projected:=SurfaceProject.projected_direction(p,d)
		expect(SurfaceProject.ground_direction(p,projected).distance_to(d)<0.0001,"oblique direction inverse "+str(d))
	var a:=descriptor("scaled_gate");a.category="gate";a.passage_width_units=30;a.ground_footprint=[[-50,-50],[50,-50],[50,50],[-50,50]]
	a.sockets=[{"socket_id":"road","position_px":[50,50],"role":"road","direction_deg":rad_to_deg(SurfaceProject.projected_direction(p,Vector2.DOWN).angle())}]
	p.asset_refs={"scaled_gate@v1":a};var gate:=entity("scaled","scaled_gate@v1");gate.scale=2
	var road: Dictionary={"kind":"ribbon","role":"road","surface_id":"ground","polygons":[[[471,350],[529,350],[529,650],[471,650]]]}
	expect(Overrides._gate_opening(p,road,gate),"scaled gate uses scaled opening width")
	road.polygons=[[[469,350],[531,350],[531,650],[469,650]]]
	expect(not Overrides._gate_opening(p,road,gate),"scaled gate rejects road over width boundary")
	# A linear ramp fixture exercises the Jacobian independently of UI drawing.
	p.surfaces=[{"surface_id":"ground","height":0},{"surface_id":"top","height":40},{"surface_id":"r","kind":"ramp","from_surface_id":"ground","to_surface_id":"top","start":[0,0],"end":[100,0],"width":40}]
	for at in [Vector2.ZERO,Vector2(50,0),Vector2(100,0),Vector2(101,0)]:
		var d:=Vector2(1,1).normalized();var projected:=SurfaceProject.projected_direction(p,d,"r",at)
		expect(SurfaceProject.ground_direction(p,projected,"r",at).distance_to(d)<0.0001,"ramp direction roundtrip at "+str(at))

func immutable_and_jobs() -> void:
	var s=Session.new();var first: Dictionary=s.view()
	expect(first.is_read_only() and first.manual_entities.is_read_only() and first.style_profile.ground_matrix.is_read_only(),"UI view recursively read only")
	for i in range(25):s.dispatch({"op":"rename","title":"title"+str(i)})
	expect(first.title!=s.view().title and first.materialized_snapshot.input_hash!=s.view().materialized_snapshot.input_hash,"old immutable state survives later commits")
	expect(s.undo_stack.size()==20 and s._history_sizes.size()<=20,"combined history count and accounting cache bounded")
	for i in range(10):s.undo()
	expect(s.history_stats().undo+s.history_stats().redo==20,"redo included in history budget")
	var expected_bytes:=0
	for state in s.undo_stack+s.redo_stack:expected_bytes+=JSON.stringify(state).to_utf8_buffer().size()
	expect(s.history_stats().estimated_json_bytes==expected_bytes,"history estimate includes the newly pushed redo state")
	s.dispatch({"op":"rename","title":"fork history"})
	expect(s.redo_stack.is_empty() and s._history_sizes.size()<=s.undo_stack.size(),"redo and size cache pruned on fork")
	s.clear_history();expect(s._history_sizes.is_empty() and s.history_stats().estimated_json_bytes==0,"clear history releases all accounting")
	expect(s.start_edit_job({"op":"rename","title":"late"}).ok,"background edit starts")
	s.dispatch({"op":"rename","title":"newer"})
	var result: Dictionary={"status":"working"}
	while result.status=="working":await process_frame;result=s.poll_preview_job()
	expect(result.status=="discarded" and s.view().title=="newer","revision/token reject stale edit")
	expect(s.start_edit_job({"op":"rename","title":"committed worker"}).ok,"background positive starts")
	result={"status":"working"}
	while result.status=="working":await process_frame;result=s.poll_preview_job()
	expect(result.status=="committed" and s.view().title=="committed worker","background edit adopts one validated state")
	s.shutdown_jobs()
	var legacy=Session.new();var p: Dictionary=legacy.snapshot();p.materialized_snapshot.generator_version="old.review"
	expect(legacy.replace_project(p).ok and legacy.read_only,"old generator opens readonly")
	expect(legacy.rebuild_derived().ok,"old generator explicit rebuild")
	legacy.start_edit_job({"op":"rename","title":legacy.view().title})
	result={"status":"working"}
	while result.status=="working":await process_frame;result=legacy.poll_preview_job()
	expect(legacy.undo() and legacy.read_only,"undo rebuild restores readonly")
	expect(not legacy.prepared_render_plan(legacy.view()).ok,"prepared render plan cannot cross generator versions with same input hash")
	legacy.shutdown_jobs()

func alpha_picking() -> void:
	var canvas_script=preload("res://addons/strategic_map_editor/workshop_s1/ui/project_canvas.gd")
	var s=Session.new();var a:=descriptor("alpha")
	var image:=Image.create(100,100,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT);image.fill_rect(Rect2i(40,40,20,20),Color.GREEN)
	var png:=image.save_png_to_buffer();a.texture_sha256=Export.digest(png);a.texture_ref="assets/"+a.texture_sha256+".png"
	s.asset_blobs[a.texture_sha256]=png
	s.dispatch({"op":"add_assets","assets":{"alpha@v1":a}})
	s.dispatch({"op":"add_manual","entity":{"entity_id":"behind","kind":"marker","ground_xy":[460,480],"surface_id":"ground","local_height":0,"label":"behind"}})
	s.dispatch({"op":"add_manual","entity":entity("front","alpha@v1")})
	var canvas=canvas_script.new();canvas.session=s;root.add_child(canvas)
	var entries: Array=canvas_script.Plan.build(s.view())
	expect(canvas_script.Plan.pick(entries,Vector2(460,460),canvas.asset_hit)=="behind","cached alpha picking passes through transparent margins")
	expect(canvas_script.Plan.pick(entries,Vector2(500,500),canvas.asset_hit)=="front","cached alpha picking selects opaque pixels")
	canvas.queue_free()
