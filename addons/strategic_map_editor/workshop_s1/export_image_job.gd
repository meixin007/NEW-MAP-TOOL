@tool
extends RefCounted
## The worker owns its Image/bytes exclusively. No scene, texture or viewport API.
var mutex:=Mutex.new()
var _cancelled:=false
var _rows_done:=0
func cancel() -> void:
	mutex.lock();_cancelled=true;mutex.unlock()
func state() -> Dictionary:
	mutex.lock();var value: Dictionary={"cancelled":_cancelled,"rows_done":_rows_done};mutex.unlock();return value
func encode(image: Image,unpremultiply: bool) -> Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	if unpremultiply:
		var bytes:=image.get_data();var width:=image.get_width()
		for y in range(image.get_height()):
			if y%16==0:
				mutex.lock();_rows_done=y;var stop:=_cancelled;mutex.unlock()
				if stop:return {"ok":false}
			for index in range((y*width)*4+3,((y+1)*width)*4,4):
				var alpha: int=bytes[index]
				if alpha>0 and alpha<255:
					for channel in range(index-3,index):bytes[channel]=clampi(roundi(float(bytes[channel])*255.0/alpha),0,255)
		image=Image.create_from_data(width,image.get_height(),false,Image.FORMAT_RGBA8,bytes)
	if state().cancelled:return {"ok":false}
	# Godot's native PNG codec has no mid-call cancellation. It runs off the UI
	# thread; cancellation is checked before/after encoding and before publication.
	var png:=image.save_png_to_buffer()
	return {"ok":not state().cancelled,"image":image,"png":png}
