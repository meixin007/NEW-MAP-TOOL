@tool
extends Node2D
var host
func _draw() -> void:
	if is_instance_valid(host):host.paint_transient(self)
