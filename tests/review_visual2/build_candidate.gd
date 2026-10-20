extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const C=preload("res://addons/strategic_map_editor/workshop_s1/compound_model.gd")
const P=preload("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
var failures: Array=[]
func check(r: Dictionary) -> void:
	if not r.ok:failures.append(r);printerr(r)
func asset(id: String,ref: String,xy: Vector2) -> Dictionary:
	return {"entity_id":id,"kind":"asset","asset_ref":ref+"@candidate2","ground_xy":[xy.x,xy.y],"surface_id":"ground","local_height":0,"scale":1,"orientation":0,"management":"manual","label":id,"locked":false}
func socket(p: Dictionary,e: Dictionary,id: String) -> Vector2:
	var a: Dictionary=p.asset_refs[e.asset_ref]
	for s in a.sockets:
		if s.socket_id==id:return P.project_point(p,Vector2(e.ground_xy[0],e.ground_xy[1]))+(Vector2(s.position_px[0],s.position_px[1])-Vector2(a.anchor_px[0],a.anchor_px[1]))*float(a.nominal_size_units[0])/float(a.region_px[2])
	assert(false,"missing socket "+id);return Vector2.ZERO
func joined(p: Dictionary,id: String,ref: String,own_socket: String,target: Vector2) -> Dictionary:
	var e:=asset(id,ref,Vector2.ZERO)
	var xy:=P.ground_point(p,target-socket(p,e,own_socket))
	e.ground_xy=[xy.x,xy.y];return e
func terrace(id: String,ring: Array,height: float,color: String) -> Dictionary:
	var styles: Array=[];var widths: Array=[];var directions: Array=[];var gradients: Array=[]
	for i in range(ring.size()):
		styles.append("cliff" if i in [5,6,7] else "slope");widths.append(0 if i in [5,6,7] else 22+((i*17)%29));directions.append(-15+(i*11)%32);gradients.append(0.85)
	return {"surface_id":id,"kind":"terrace","parent_surface_id":"ground","height":height,"outline":ring,"edge_styles":styles,"edge_widths":widths,"edge_directions":directions,"edge_gradients":gradients,"top_color":color,"edge_color":"c8b58b","locked":false}
func path(id: String,points: Array,widths: Array,surface: String="ground") -> Dictionary:
	var cp: Array=[];var seg: Array=[]
	for i in range(points.size()):
		cp.append({"point_id":"p"+str(i),"ground_xy":points[i],"width":widths[i]})
		if i>0:seg.append({"segment_id":"s"+str(i),"from":"p"+str(i-1),"to":"p"+str(i)})
	return {"recipe_id":id,"kind":"path","path_type":"road","name":"关口道路","control_points":cp,"segments":seg,"seed":42,"surface_id":surface,"style":"dirt","roles":[],"wall_asset_ref":"","roadside":{},"source_feature_id":""}
func forest(p: Dictionary,id: String,ring: Array,surface: String="ground",density: float=0.8) -> Dictionary:
	var weights: Array=[]
	for ref in p.asset_refs:
		if ref.begins_with("tree_unit"):weights.append({"asset_ref":ref,"weight":1})
	return {"recipe_id":id,"kind":"plot","name":"六种树形混用","plot_type":"forest","shape":"polygon","outer":ring,"holes":[],"surface_id":surface,"seed":291,"density":density,"spacing":[16,16],"scale_range":[1.0,1.35],"asset_weights":weights,"cluster_strength":0.35,"locked":false}
func _initialize() -> void:
	var s=S.new();var importer=preload("res://addons/strategic_map_editor/workshop_s1/asset_importer.gd").new()
	check(importer.import_pack(s,"res://samples/reference_assets.assetpack.json"));check(importer.import_pack(s,"res://samples/fortification_candidate2.assetpack.json"))
	var p: Dictionary=s.snapshot();p.project_id="project_fortification_candidate2";p.title="关口组合 · 候选2（待视觉审核）";p.legacy_document.canvas_size=[2200,1600]
	p.style_profile.ground_matrix=[1.0,0.14,-0.43,0.72];p.style_profile.paper_color="eadbb5";p.style_profile.style_id="reference_oblique_sparse_pending";p.style_profile.ink_mode="sparse"
	p.provenance.visual_review="pending_user_review";p.provenance.previous_candidate="candidate1 rejected by user: 素材和组合都需要调整";p.provenance.creation="Built-in image_gen raw PNGs, explicit socket placement, editable native terrain/road/rooms. Original three samples preserved."
	var west: Array=[[185,235],[214,200],[245,205],[279,172],[326,182],[362,170],[390,201],[438,212],[452,239],[487,251],[480,285],[511,309],[488,347],[495,373],[451,380],[425,408],[382,406],[356,432],[307,415],[281,426],[251,391],[214,382],[222,342],[193,318],[205,276]]
	var east: Array=[[1190,220],[1220,206],[1252,212],[1281,186],[1325,193],[1360,215],[1395,218],[1430,265],[1424,304],[1450,340],[1430,360],[1420,401],[1382,408],[1360,444],[1328,421],[1293,432],[1270,418],[1242,378],[1220,365],[1230,332],[1175,300],[1194,266]]
	p.surfaces.append(terrace("west_bank",west,18,"ccc494"));p.surfaces.append(terrace("east_bank",east,14,"c7c18c"))
	var gate:=asset("review2.gate","review_gate",Vector2(820,660))
	var left:=joined(p,"review2.wall.left","review_wall_front","right",socket(p,gate,"wall_left")+Vector2(2,0))
	var right:=joined(p,"review2.wall.right","review_wall_front","left",socket(p,gate,"wall_right")-Vector2(2,0))
	var corner:=joined(p,"review2.corner.right","review_corner_tower","left",socket(p,right,"right")-Vector2(4,0))
	var left_corner:=joined(p,"review2.corner.left","review_corner_tower","right",socket(p,left,"left")+Vector2(4,0))
	var side:=joined(p,"review2.wall.side","review_wall_side","near",socket(p,corner,"rear")-Vector2(8,3))
	p.manual_entities=[gate,left,right,corner,left_corner,side]
	var yard:=C.entity("review2.yard","ground",Vector2(930,470),C.plan("courtyard",200,150));yard.room_plan.roof_color="74756a";yard.room_plan.wall_color="d0bd94";p.manual_entities.append(yard)
	var room:=C.entity("review2.store","ground",Vector2(675,485),C.plan("room",78,64,"storage"));room.room_plan.roof_color="74756a";room.room_plan.wall_color="d0bd94";p.manual_entities.append(room)
	p.recipes=[path("review2.road",[[940,1110],[900,1030],[842,940],[812,840],[820,735],[820,660],[820,590],[827,525],[830,485]],[30,28,25,27,26,25,27,28,24]),path("review2.branch",[[824,550],[874,510],[930,482]],[16,18,18]),forest(p,"review2.forest.west",[[160,490],[260,460],[360,485],[425,540],[400,645],[325,715],[195,685],[142,595]]),forest(p,"review2.forest.east",[[1290,520],[1430,500],[1510,555],[1480,710],[1375,770],[1270,725]],"ground",0.9),forest(p,"review2.forest.back",[[555,220],[735,190],[880,220],[950,280],[880,330],[675,310],[565,285]],"ground",0.85),forest(p,"review2.forest.hill.west",[[252,244],[321,221],[396,240],[450,283],[451,329],[390,364],[320,366],[265,332]],"west_bank",0.85),forest(p,"review2.forest.hill.east",[[1230,258],[1305,232],[1370,267],[1400,326],[1362,381],[1290,367],[1245,323]],"east_bank",0.85)]
	# Pad the authored scene so the rectangular review camera stays inside paper.
	var offset:=Vector2(260,250)
	for e in p.manual_entities:e.ground_xy=[float(e.ground_xy[0])+offset.x,float(e.ground_xy[1])+offset.y]
	for surface in p.surfaces:
		if surface.has("outline"):
			for q in surface.outline:q[0]+=offset.x;q[1]+=offset.y
	for recipe in p.recipes:
		if recipe.kind=="path":
			for point in recipe.control_points:point.ground_xy[0]+=offset.x;point.ground_xy[1]+=offset.y
		else:
			for q in recipe.outer:q[0]+=offset.x;q[1]+=offset.y
	p.materialized_snapshot=s.Model.materialize(p)
	if p.materialized_snapshot.get("ok",true)==false:printerr(p.materialized_snapshot)
	check(s.replace_project(p))
	if failures.is_empty():check(s.save_file(OS.get_cmdline_user_args()[0]))
	print("VISUAL2_BUILD ",JSON.stringify({"failures":failures,"input_hash":s.authority_signature(),"entities":s.view().materialized_snapshot.entities.size(),"visual_approval":"pending"}));quit(0 if failures.is_empty() else 1)
