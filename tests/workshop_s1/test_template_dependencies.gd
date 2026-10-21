extends "test_templates.gd"
func _initialize() -> void:
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var L=load("res://addons/strategic_map_editor/workshop_s1/template_library.gd");var C=load("res://addons/strategic_map_editor/workshop_s1/compound_model.gd");var s=S.new()
	var top: Dictionary={"surface_id":"top","kind":"terrace","parent_surface_id":"ground","height":60,"outline":[[100,100],[550,100],[550,550],[100,550]],"edge_styles":["cliff","cliff","cliff","cliff"],"edge_widths":[0,0,0,0],"top_color":"c5bf89","edge_color":"b69d70","locked":false}
	check(s.dispatch({"op":"add_terrain","surface":top}).ok,"authored support")
	check(s.dispatch({"op":"add_manual","entity":C.entity("house","top",Vector2(300,400),C.plan("courtyard"))}).ok,"attached courtyard")
	var captured: Dictionary=L.capture(s.snapshot(),["house"],"map_group","山顶组")
	check(captured.ok and captured.template.surfaces.size()==1,"support closure included")
	var target=S.new();check(target.dispatch({"op":"instantiate_template","template":captured.template,"ground_xy":[900,600]}).ok,"translated independent support closure")
	check(target.snapshot().surfaces[1].surface_id!="top" and target.snapshot().manual_entities[0].surface_id==target.snapshot().surfaces[1].surface_id,"support references remapped")
	var group_id: String=target.snapshot().prefab_instances[0].instance_id
	var transform: Dictionary={"op":"transform_instance","instance_id":group_id,"pivot":[900,600],"offset":[50,30],"angle":15,"factor":1}
	var original: Dictionary=target.snapshot();check(target.dispatch(transform).ok,"support and attached group transform atomically")
	check(target.snapshot().surfaces[1].outline!=original.surfaces[1].outline and target.snapshot().manual_entities[0].ground_xy!=original.manual_entities[0].ground_xy,"group transforms authored support and members")
	check(target.undo() and target.Model.input_hash(target.snapshot())==target.Model.input_hash(original),"whole support group undo restores exact authority")
	var locked_id: String=target.snapshot().manual_entities[0].entity_id;target.dispatch({"op":"set_entity_locked","entity_id":locked_id,"locked":true});var locked_hash: String=target.Model.input_hash(target.snapshot())
	check(not target.dispatch(transform).ok and target.Model.input_hash(target.snapshot())==locked_hash,"locked member rejects entire surface transform")
	target.undo()
	var before: String=target.Model.input_hash(target.snapshot());check(not target.dispatch({"op":"instantiate_template","template":captured.template,"ground_xy":[900,600]}).ok and target.Model.input_hash(target.snapshot())==before,"overlapping support refuses entire placement")
	var invalid: Dictionary=captured.template.duplicate(true);invalid.surfaces[0].outline="bad";check(not L.validate(invalid).is_empty(),"malformed surface refused before geometry traversal")
	var sample=load("res://addons/strategic_map_editor/workshop_s1/sample_assets.gd");var assets=S.new();check(sample.install(assets,"user://w67_dependency_assets").ok,"self-owned fixture assets")
	var ref: String=assets.snapshot().asset_refs.keys()[6]
	for pair in [["a",[400,400]],["b",[700,400]]]:
		check(assets.dispatch({"op":"add_manual","entity":{"entity_id":pair[0],"kind":"asset","asset_ref":ref,"surface_id":"ground","ground_xy":pair[1],"local_height":0,"scale":1,"orientation":0,"management":"manual"}}).ok,"source image "+pair[0])
	check(assets.dispatch({"op":"update_entity","entity_id":"a","patch":{"socket_binding":{"mode":"snap_once","target_entity_id":"b","source_socket":"source","target_socket":"target"}}}).ok,"internal relationship fixture")
	var group: Dictionary=L.capture(assets.snapshot(),["a","b"],"asset_composite","附件组");var pasted=S.new();check(group.ok and pasted.dispatch({"op":"instantiate_template","template":group.template,"ground_xy":[500,600]}).ok,"image composite cloning")
	var members: Array=pasted.snapshot().manual_entities;check(members[0].socket_binding.target_entity_id==members[1].entity_id and members[0].socket_binding.target_entity_id!="b","internal socket target remapped")
	var single: Dictionary=L.capture(assets.snapshot(),["a"],"map_group","清除外部接点");check(single.ok and not single.template.entities[0].has("socket_binding"),"external socket target cleared")
	var hash: String=pasted.Model.input_hash(pasted.snapshot());var ids: Array=members.map(func(e):return e.entity_id)
	check(not pasted.dispatch({"op":"transform_entities","entity_ids":ids,"pivot":[500,600],"offset":[0,0],"angle":37,"factor":1}).ok and pasted.Model.input_hash(pasted.snapshot())==hash,"missing directional variant refuses entire group")
	var forest: Dictionary={"recipe_id":"forest","kind":"plot","name":"林地预设","plot_type":"forest","shape":"rectangle","outer":[[80,80],[1400,80],[1400,800],[80,800]],"holes":[],"surface_id":"ground","seed":42,"density":0.6,"spacing":[96,64],"scale_range":[0.8,1],"asset_weights":[{"asset_ref":ref,"weight":1}],"cluster_strength":0.3,"locked":false}
	check(assets.dispatch({"op":"add_recipe","recipe":forest}).ok,"editable forest recipe")
	var original_region: Dictionary=assets.snapshot();check(assets.dispatch({"op":"transform_recipes","recipe_ids":["forest"],"pivot":[700,400],"offset":[0,0],"angle":7,"factor":1}).ok,"region rotation changes authoritative polygon")
	check(assets.snapshot().recipes[0].shape=="polygon" and assets.snapshot().recipes[0].outer!=forest.outer,"rotation preserves real geometry rather than bounding rectangle")
	assets.undo();check(assets.Model.input_hash(assets.snapshot())==assets.Model.input_hash(original_region),"region rotation undo restores children and source")
	var children: Array=assets.snapshot().materialized_snapshot.entities.filter(func(e):return e.get("recipe_id")=="forest")
	check(children.size()>2,"preset protection fixtures")
	if children.size()>2:
		assets.dispatch({"op":"fix_entity","entity_id":children[0].entity_id});assets.dispatch({"op":"delete_entity","entity_id":children[1].entity_id})
		var preset: Dictionary=L.capture(assets.snapshot(),[],"recipe_preset","林地",["forest"],true);var clone=S.new();check(preset.ok and clone.dispatch({"op":"instantiate_template","template":preset.template,"ground_xy":[80,80]}).ok,"preset carries explicitly selected fixed/deletion intent")
		check(clone.snapshot().recipes[0].recipe_id!="forest" and clone.snapshot().manual_overrides.fixed.size()==1 and clone.snapshot().manual_overrides.tombstones.size()==1,"new recipe and generated identity namespace")
	print("WORKSHOP_TEMPLATE_DEPENDENCIES ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
