extends Node
var canvas
var rows: Array=[]
var active:=false
var start: int=0
var previous: int=0
func begin() -> void:
	start=Time.get_ticks_usec();previous=start;active=true
func _process(_delta: float) -> void:
	if not active:return
	var now:=Time.get_ticks_usec()
	rows.append({"elapsed_ms":(now-start)/1000.0,"frame_ms":(now-previous)/1000.0,"pan":[canvas.pan.x,canvas.pan.y],"zoom":canvas.zoom,"plans":canvas.plan_rebuilds,"paint_commands":canvas.draw_rebuilds,"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
	previous=now
