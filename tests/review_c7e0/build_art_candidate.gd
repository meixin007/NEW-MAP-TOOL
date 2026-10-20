extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const C=preload("res://addons/strategic_map_editor/workshop_s1/compound_model.gd")
var failures: Array=[]
func check(result: Dictionary) -> void:
	if not result.ok:failures.append(result);printerr(result)
func asset(id: String,ref: String,xy: Array) -> Dictionary:
	return {"entity_id":id,"kind":"asset","asset_ref":ref,"ground_xy":xy,"surface_id":"ground","local_height":0,"scale":1,"orientation":0,"management":"manual","label":id,"locked":false}
func road() -> Dictionary:
	return {"recipe_id":"review.road","kind":"path","path_type":"road","name":"关口道路","control_points":[{"point_id":"a","ground_xy":[800,600],"width":24},{"point_id":"b","ground_xy":[800,880],"width":24}],"segments":[{"segment_id":"ab","from":"a","to":"b"}],"seed":42,"surface_id":"ground","style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
func _initialize() -> void:
	var s=S.new();var importer=preload("res://addons/strategic_map_editor/workshop_s1/asset_importer.gd").new()
	check(importer.import_pack(s,"res://samples/reference_assets.assetpack.json"));check(importer.import_pack(s,"res://samples/fortification_candidate.assetpack.json"))
	var p: Dictionary=s.snapshot();p.title="关口组合 · 美术候选1（待视觉审核）";p.style_profile.ground_matrix=[1.0,0.14,-0.30,0.72];p.style_profile.paper_color="eadbb5";p.style_profile.style_id="reference_oblique_review_pending"
	p.provenance.visual_review="pending_user_review";p.provenance.creation="Reproducible transaction fixture; normal UI open/edit/save/export checked separately. No original sample replaced."
	p.surfaces.append({"surface_id":"bank","kind":"terrace","parent_surface_id":"ground","height":28,"outline":[[100,120],[500,140],[460,430],[150,400]],"edge_styles":["slope","slope","cliff","slope"],"edge_widths":[35,35,0,35],"top_color":"c5bf89","edge_color":"b69d70","locked":false})
	p.manual_entities=[asset("review.gate","review_gate@candidate1",[800,720]),asset("review.wall.left","review_wall_front@candidate1",[565,730]),asset("review.wall.right","review_wall_front@candidate1",[1000,710]),asset("review.wall.side","review_wall_side@candidate1",[1210,680]),asset("review.corner","review_corner_tower@candidate1",[1200,710])]
	var yard:=C.entity("review.yard","ground",Vector2(880,520),C.plan("courtyard"));yard.room_plan.roof_material="w5_gray_tile@v1";p.manual_entities.append(yard)
	p.recipes=[road(),{"recipe_id":"review.forest","kind":"plot","name":"六种树形混用","plot_type":"forest","shape":"polygon","outer":[[140,480],[490,440],[650,600],[480,680],[160,690]],"holes":[],"surface_id":"ground","seed":42,"density":0.9,"spacing":[16,16],"scale_range":[1.1,1.5],"asset_weights":[],"cluster_strength":0.75,"locked":false}]
	for ref in p.asset_refs:
		if ref.begins_with("tree_unit"):p.recipes[1].asset_weights.append({"asset_ref":ref,"weight":1})
	p.materialized_snapshot=s.Model.materialize(p)
	check(s.replace_project(p))
	if failures.is_empty():check(s.save_file(OS.get_cmdline_user_args()[0]))
	print("REVIEW_ART_CANDIDATE ",JSON.stringify({"failures":failures,"input_hash":s.authority_signature(),"entities":s.view().materialized_snapshot.entities.size()}));quit(0 if failures.is_empty() else 1)
