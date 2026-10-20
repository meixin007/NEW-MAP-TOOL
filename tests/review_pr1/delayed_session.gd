extends "res://addons/strategic_map_editor/workshop_s1/session_transaction.gd"
func _worker_candidate(source: Dictionary,command: Dictionary,known_source_bytes: int=0) -> Dictionary:
	OS.delay_msec(180) # Deterministic validating interval, on the worker only.
	return super._worker_candidate(source,command,known_source_bytes)
