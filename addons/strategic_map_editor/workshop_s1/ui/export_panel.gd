@tool
extends VBoxContainer
const Adapter=preload("../export_adapter.gd")
const Preview=preload("readonly_preview.gd")
var host
var adapter
var scale_field: SpinBox
var tile_size: SpinBox
var bounds_fields: Array=[]
var ground: CheckBox
var layers: CheckBox
var grid: CheckBox
var legend: CheckBox
var destination: LineEdit
var progress_label: Label
var dialog: FileDialog
var preview_dialog: FileDialog
var preview_window: Window
var dirty:=false
var last_result: Dictionary={}
func number(label: String,value: float,lo: float,hi: float,step: float=1) -> SpinBox:
	var field:=SpinBox.new();field.prefix=label+" ";field.min_value=lo;field.max_value=hi;field.step=step;field.value=value;add_child(field);return field
func toggle(text: String,value: bool) -> CheckBox:
	var field:=CheckBox.new();field.text=text;field.button_pressed=value;add_child(field);return field
func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hint:=Label.new();hint.text="合成、透明地面、选择组、层序片和分页共享固定范围。\n只写新目录；取消／失败保留旧交付。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	scale_field=number("导出比例",1,0.1,4,0.1);tile_size=number("分页像素",2048,64,2048,64)
	for name in ["投影范围 X","投影范围 Y","范围宽","范围高"]:bounds_fields.append(number(name,0,-100000,100000))
	host.button(self,"采用当前完整范围",fit_bounds)
	ground=toggle("输出透明地面",true);layers=toggle("输出连续层序片",true);grid=toggle("导出网格",false);legend=toggle("导出图例",true)
	destination=LineEdit.new();destination.placeholder_text="新导出目录的完整地址";add_child(destination)
	host.button(self,"选择导出父目录",func():dialog.popup_centered_ratio(0.7))
	host.button(self,"开始导出冻结快照",start)
	host.button(self,"取消当前导出",func():adapter.cancel();progress_label.text="正在取消，等待当前文件完成。")
	progress_label=Label.new();progress_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(progress_label)
	host.button(self,"打开导出清单只读预览",func():preview_dialog.popup_centered_ratio(0.7))
	dialog=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR;host.add_child(dialog);dialog.dir_selected.connect(func(path):destination.text=path.path_join("导出_"+host.Model.new_id("s1")))
	preview_dialog=FileDialog.new();preview_dialog.access=FileDialog.ACCESS_FILESYSTEM;preview_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;preview_dialog.filters=PackedStringArray(["manifest.json ; 工坊导出清单"]);host.add_child(preview_dialog);preview_dialog.file_selected.connect(open_preview)
	adapter=Adapter.new();add_child(adapter);adapter.progress.connect(func(message,current,total):progress_label.text=message+" · %d/%d"%[current,total])
	fit_bounds()
func fit_bounds() -> void:
	var rect:=Adapter.default_bounds(host.session.snapshot())
	for i in range(4):bounds_fields[i].value=[rect.position.x,rect.position.y,rect.size.x,rect.size.y][i]
func options() -> Dictionary:
	return {"bounds":bounds_fields.map(func(f):return f.value),"scale":scale_field.value,"tile_size":tile_size.value,"transparent_ground":ground.button_pressed,"layers":layers.button_pressed,"selected_ids":host.selected_entity_ids(),"include_grid":grid.button_pressed,"include_legend":legend.button_pressed}
func start() -> void:
	if host.canvas.has_pending_input() or host.has_pending_fields():host.status.text="先应用或取消属性／画布输入。";return
	if destination.text.is_empty():host.status.text="选择父目录或填写新的导出目录。";return
	last_result=await adapter.export_project(host.session,destination.text,options());host.report(last_result);progress_label.text="已完成："+destination.text if last_result.ok else str(last_result.error)
func open_preview(path: String) -> void:
	var validation:=Adapter.validate_bundle(path)
	if not validation.ok:host.report(validation);return
	preview_window=Window.new();preview_window.title="工坊数据包 · 只读预览";preview_window.size=Vector2i(1200,760);preview_window.close_requested.connect(preview_window.queue_free);host.add_child(preview_window)
	var preview:=Preview.new();preview_window.add_child(preview);preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview_window.popup_centered();var opened: Dictionary=await preview.open_manifest(path);host.report(opened)
func capture_draft() -> Dictionary:
	return {"destination":destination.text,"options":options(),"raw_numbers":bounds_fields.map(func(f):return f.get_line_edit().text)+[scale_field.get_line_edit().text,tile_size.get_line_edit().text]}
func restore_draft(d: Dictionary) -> void:
	if d.is_empty():return
	destination.text=d.destination;var o: Dictionary=d.options
	for i in range(4):bounds_fields[i].value=o.bounds[i];bounds_fields[i].get_line_edit().text=d.raw_numbers[i]
	scale_field.value=o.scale;tile_size.value=o.tile_size;scale_field.get_line_edit().text=d.raw_numbers[4];tile_size.get_line_edit().text=d.raw_numbers[5];ground.button_pressed=o.transparent_ground;layers.button_pressed=o.layers;grid.button_pressed=o.include_grid;legend.button_pressed=o.include_legend
