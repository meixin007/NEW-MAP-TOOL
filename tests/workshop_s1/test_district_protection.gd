extends "test_districts.gd"
const C=preload("res://addons/strategic_map_editor/workshop_s1/compound_model.gd")
const D=preload("res://addons/strategic_map_editor/workshop_s1/district_generator.gd")
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const T=preload("res://addons/strategic_map_editor/workshop_s1/terrain_geometry.gd")
func _initialize() -> void:
	var s=S.new();check(s.dispatch({"op":"add_recipe","recipe":road("main",[80,480],[1520,480])}).ok,"main road")
	var r:=D.recipe("district","along_road",[[40,40],[1560,40],[1560,920],[40,920]],"ground",["main"]);r.density=1;r.vacancy=0;r.future_fraction=0
	check(s.dispatch({"op":"add_recipe","recipe":r}).ok,"district")
	var children: Array=s.snapshot().materialized_snapshot.entities.filter(func(e):return e.kind=="compound")
	if children.size()<3:check(false,"enough fixtures");quit(1);return
	var fixed: Dictionary=children[0];var detached: Dictionary=children[1];var deleted: Dictionary=children[2]
	check(s.dispatch({"op":"fix_entity","entity_id":fixed.entity_id}).ok,"fix courtyard")
	check(s.snapshot().materialized_snapshot.entities.any(func(e):return e.get("candidate_id")=="access/"+fixed.candidate_id),"fixed courtyard retains access street")
	check(s.dispatch({"op":"detach_entity","entity_id":detached.entity_id}).ok,"detach exact identity")
	var moved: Array=[detached.ground_xy[0],detached.ground_xy[1]+16]
	check(s.dispatch({"op":"update_entity","entity_id":detached.entity_id,"patch":{"ground_xy":moved}}).ok,"move detached courtyard")
	check(s.dispatch({"op":"delete_entity","entity_id":deleted.entity_id}).ok,"tombstone auto courtyard")
	var held: Dictionary=s.snapshot().manual_overrides.fixed.duplicate(true);var manual: Array=s.snapshot().manual_entities.duplicate(true)
	var start:=Time.get_ticks_msec()
	for seed in range(50):
		var result: Dictionary=s.dispatch({"op":"update_recipe","recipe_id":"district","patch":{"seed":seed,"density":0.5}})
		check(result.ok,"bounded regeneration "+str(seed)+": "+str(result.get("error","")))
		check(s.snapshot().manual_overrides.fixed==held and s.snapshot().manual_entities==manual,"exact protected source survives "+str(seed))
		check(not s.snapshot().materialized_snapshot.entities.any(func(e):return e.entity_id==deleted.entity_id),"tombstone survives "+str(seed))
		check(s.snapshot().materialized_snapshot.entities.any(func(e):return e.get("candidate_id")=="access/"+fixed.candidate_id),"fixed entrance keeps legal connection "+str(seed))
	var before: String=s.Model.input_hash(s.snapshot());var crossing: Array=fixed.ground_xy.duplicate();crossing[1]-=60
	var conflict: Dictionary=s.dispatch({"op":"update_path_point","recipe_id":"main","point_id":"a","patch":{"ground_xy":[80,crossing[1]]}})
	check(not conflict.ok and s.Model.input_hash(s.snapshot())==before,"road invading protected courtyard refuses atomically")
	check(not s.dispatch({"op":"remove_recipe","recipe_id":"main","confirmed":true}).ok,"main road dependency refuses deletion")
	var bad: Dictionary=r.duplicate(true);bad.recipe_id="huge";bad.layout="orthogonal";bad.outer=[[0,0],[100000,0],[100000,100000],[0,100000]]
	check(not s.dispatch({"op":"add_recipe","recipe":bad}).ok,"bounded solver refuses excess candidate budget")
	var narrow:=D.recipe("narrow","orthogonal",[[100,100],[150,100],[150,800],[100,800]],"ground",["main"])
	check(s.dispatch({"op":"add_recipe","recipe":narrow}).ok and s.snapshot().materialized_snapshot.lots.filter(func(l):return l.recipe_id=="narrow").is_empty(),"narrow region stays empty; no building downscale")
	var bad_plan:=C.plan("room",160,140);bad_plan.holes=[C.rect(-80,-140,20,20)]
	check(not C.validate_plan(bad_plan,{}).is_empty(),"touching hole boundary refused")
	var plan:=C.plan("courtyard");var area:=0.0
	for poly in C.floor_parts(plan):area+=T.area(poly)
	check(is_equal_approx(area,T.area(s.Model.Asset.packed(plan.outer))-T.area(s.Model.Asset.packed(plan.holes[0]))),"actual floor triangles preserve exact hole area")
	var closed: Dictionary=plan.duplicate(true);closed.walls[2].openings=[]
	check(C.entrance(C.entity("closed","ground",Vector2(400,400),closed)).is_empty(),"closed outer wall does not invent an entrance socket")
	for field in ["room_fields","district_fields"]:
		check(not S._validate_recovery_draft({field:{"values":{"script":1}}},s.snapshot()).is_empty(),"hostile recovery getter key refused")
	check(not S._validate_recovery_draft({"w5_canvas":{"compound_points":[[INF,0]]}},s.snapshot()).is_empty(),"nonfinite recovery refused")
	var frozen: Dictionary=s.snapshot();var reopened=S.new();check(reopened.load_text(JSON.stringify(frozen)).ok and not reopened.read_only,"JSON integer/float roundtrip keeps district output editable")
	var tampered: Dictionary=frozen.duplicate(true);tampered.materialized_snapshot.lots[0].lot_role="future" if tampered.materialized_snapshot.lots[0].lot_role!="future" else "buildable"
	check(not S.new().replace_project(tampered).ok,"tampered derived lot authority refused")
	var clearance: Dictionary={"recipe_id":"all_clear","kind":"plot","name":"永久空地","plot_type":"clearance","shape":"polygon","outer":[[30,30],[1570,30],[1570,930],[30,930]],"holes":[],"surface_id":"ground","seed":42,"density":0,"spacing":[96,64],"scale_range":[1,1],"asset_weights":[],"cluster_strength":0,"locked":false}
	var clean=S.new();clean.dispatch({"op":"add_recipe","recipe":road("main",[80,480],[1520,480])});clean.dispatch({"op":"add_recipe","recipe":clearance})
	check(clean.dispatch({"op":"add_recipe","recipe":r}).ok and clean.snapshot().materialized_snapshot.lots.is_empty(),"all-excluded district finite empty result; roads not counted as vacant lots")
	print("WORKSHOP_DISTRICT_PROTECTION ",JSON.stringify({"checks":checks,"failures":failures,"regenerations":50,"elapsed_ms":Time.get_ticks_msec()-start}));quit(0 if failures.is_empty() else 1)
