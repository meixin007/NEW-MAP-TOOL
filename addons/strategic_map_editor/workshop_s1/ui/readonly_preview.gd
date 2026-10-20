@tool
extends Control
const Adapter=preload("../export_adapter.gd")
const Canvas=preload("project_canvas.gd")
var canvas
var session
func open_manifest(path: String) -> Dictionary:
	var result:=Adapter.validate_bundle(path)
	if not result.ok:return result
	session=result.session;session.read_only=true
	if is_instance_valid(canvas):remove_child(canvas);canvas.queue_free()
	canvas=Canvas.new();canvas.session=session;canvas.preview_only=true;canvas.show_envelopes=false;canvas.show_plot_boundaries=false;canvas.show_district_lots=false;add_child(canvas);canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame;canvas.fit_map()
	return {"ok":true}
