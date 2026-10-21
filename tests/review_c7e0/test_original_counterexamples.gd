extends SceneTree
## Original review draft adapted for baseline/current replay. Native outcomes
## are recorded separately; this file does not declare acceptance.
## Run through tests/run.py in a disposable copy (see tests/README.md).
## In-memory synthetic fixtures only: no user map/save/asset file is written.
const Session = preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const Model = preload("res://addons/strategic_map_editor/workshop_s1/project_model.gd")
const Geometry = preload("res://addons/strategic_map_editor/workshop_s1/entity_geometry.gd")
const SurfaceProject = preload("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
const Overrides = preload("res://addons/strategic_map_editor/workshop_s1/override_resolver.gd")
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
	locked_asset_update()
	gate_direction()
	socket_height()
	print(JSON.stringify({"kind":"review_contract_regression","checks":check_count,
		"failures":failures,"fixture":"synthetic_in_memory","project_files_written":false},"\t"))
	quit(0 if failures.is_empty() else 1)
