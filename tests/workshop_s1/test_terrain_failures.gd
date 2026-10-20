extends "test_terrain.gd"
var rows: Array=[]
func json_safe(v: Variant) -> Variant:
	if v is float and not is_finite(v):return "NaN" if is_nan(v) else "Infinity"
	if v is Array:return v.map(json_safe)
	if v is Dictionary:
		var d: Dictionary={}
		for key in v:d[key]=json_safe(v[key])
		return d
	return v
func rejected(s,c: Dictionary,meaning: String) -> void:
	var before: String=s.Model.input_hash(s.snapshot());var result: Dictionary=s.dispatch(c)
	var passed: bool=not result.ok and s.Model.input_hash(s.snapshot())==before
	check(passed,meaning);rows.append({"case":meaning,"command":json_safe(c),"passed":passed,"diagnostic":result.get("error",""),"before_hash":before,"after_hash":s.Model.input_hash(s.snapshot())})
func _initialize() -> void:
	var S=load("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd");var s=S.new()
	check(s.dispatch({"op":"add_terrain","surface":terrace("top")}).ok,"valid fixture")
	for patch in [{"outline":[[200,200],[700,650],[700,200],[200,650]]},{"outline":[[200,200],[700,200],[700,650],[450,650],[450,210],[440,210],[440,650],[200,650]],"edge_styles":["cliff","cliff","cliff","cliff","cliff","cliff","cliff","cliff"],"edge_widths":[0,0,0,0,0,0,0,0]},{"edge_widths":"bad"},{"edge_styles":[]},{"edge_widths":[0,0,INF,0]},{"parent_surface_id":"missing"},{"height":-1},{"height":NAN},{"locked":"yes"},{"edge_directions":[0,0,0,61]},{"edge_gradients":[1,1,1,-1]}]:
		rejected(s,{"op":"update_terrain","surface_id":"top","patch":patch},"malformed/unsupported terrace "+str(rows.size()))
	var bad:=terrace("bad");bad.edge_styles={};rejected(s,{"op":"add_terrain","surface":bad},"malformed sibling inspected safely")
	var ramp: Dictionary={"surface_id":"r","kind":"ramp","height":0,"from_surface_id":"ground","to_surface_id":"top","start":[500,820],"end":[500,550],"width":64,"style":"dirt","locked":false}
	for patch in [{"from_surface_id":[]},{"start":"bad"},{"end":[NAN,0]},{"width":-1},{"to_surface_id":"unknown"},{"from_surface_id":"top","to_surface_id":"top"},{"start":[500,680],"end":[500,640]},{"end":[900,550]}]:
		var surface: Dictionary=ramp.duplicate(true);surface.merge(patch,true);rejected(s,{"op":"add_terrain","surface":surface},"malformed/unsupported ramp "+str(rows.size()))
	# Unknown recovery control names must never reach Object.get()/LineEdit restore.
	var Model=s.Model
	for draft in [{"terrain_draft":{"points":"bad"}},{"terrain_fields":{"values":{"free":3}}},{"terrain_fields":{"edge":9}},{"terrain_fields":{"values":{"height":60},"raw_numbers":{"height":[]}}}]:
		check(not S._validate_recovery_draft(draft,s.snapshot()).is_empty(),"hostile W4 recovery input "+str(draft))
	check(s.dispatch({"op":"add_terrain","surface":ramp}).ok,"valid ramp still works after failed transactions")
	var P=load("res://addons/strategic_map_editor/workshop_s1/surface_projection.gd")
	var maximum:=0.0
	for t in [-0.1,0.0,0.1,0.25,0.5,0.75,0.9,1.0,1.1]:
		for x in [-20,0,20]:
			var g:=Vector2(500+x,820-270*t);var screen: Vector2=P.project_point(s.snapshot(),g,"r")
			maximum=maxf(maximum,P.ground_point(s.snapshot(),screen,"r").distance_to(g))
	check(maximum<0.01,"ramp cap/interior inverse agrees across full-width samples")
	print("WORKSHOP_TERRAIN_FAILURES ",JSON.stringify({"checks":checks,"failures":failures,"rejections":rows,"inverse_max_error":maximum}));quit(0 if failures.is_empty() else 1)
