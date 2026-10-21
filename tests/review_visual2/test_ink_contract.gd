extends SceneTree
const S=preload("res://addons/strategic_map_editor/workshop_s1/session_transaction.gd")
const E=preload("res://addons/strategic_map_editor/workshop_s1/editor_contract.gd")
const Plan=preload("res://addons/strategic_map_editor/workshop_s1/render_plan.gd")
var failures: Array=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize() -> void:
	check(E.validate_style({}).is_empty(),"old styles default to unchanged classic presentation")
	for value in ["classic","sparse"]:check(E.validate_style({"ink_mode":value}).is_empty(),"declared ink mode accepted "+value)
	for value in ["unknown",1,null,{},[]]:check(not E.validate_style({"ink_mode":value}).is_empty(),"unknown or non-string ink mode rejected "+str(value))
	var s=S.new();check(s.load_file("res://samples/fortification_candidate2.shwork.json").ok,"new candidate readable")
	var original: Dictionary=s.snapshot();original.style_profile.erase("ink_mode");var style_only:=original.duplicate(true);style_only.style_profile.ink_mode="sparse"
	check(Plan.inspect(original)==Plan.inspect(style_only),"ink presentation preserves support geometry, picking bounds and painter order")
	check(s.Model.generator_version(style_only)==s.Model.generator_version(original)+".ink-sparse1","new presentation declares its version; old readers cannot silently treat it as classic")
	var before:=s.authority_signature();var bad:=original.duplicate(true);bad.style_profile.ink_mode="unknown";check(not s.replace_project(bad).ok and s.authority_signature()==before,"invalid presentation rejected atomically")
	check(s.replace_project(style_only).ok,"sparse mode passes full project validation")
	var path: String=OS.get_cmdline_user_args()[0].path_join("ink_roundtrip.shwork.json");check(s.save_file(path).ok,"sparse mode save")
	var reopened=S.new();check(reopened.load_file(path).ok and reopened.view().style_profile.get("ink_mode")=="sparse" and reopened.authority_signature()==s.authority_signature(),"sparse mode serialized without authority drift")
	print("VISUAL2_INK_CONTRACT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
