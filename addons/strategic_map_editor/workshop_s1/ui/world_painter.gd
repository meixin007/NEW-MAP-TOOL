@tool
extends Node2D
var host
func _draw() -> void:
	if is_instance_valid(host) and not host._view_project.is_empty():host.paint_world(self)
