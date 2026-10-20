@tool
extends Control
const Preview=preload("readonly_preview.gd")
var viewer
var status: Label
func _ready() -> void:
	var root:=VBoxContainer.new();add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status=Label.new();status.text="工坊数据包 · 只读预览";root.add_child(status)
	var button:=Button.new();button.text="打开导出 manifest.json";root.add_child(button)
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["manifest.json ; 工坊导出数据包"]);add_child(dialog);button.pressed.connect(func():dialog.popup_centered_ratio(0.7));dialog.file_selected.connect(open_manifest)
	viewer=Preview.new();viewer.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(viewer)
	var args:=OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i]=="--manifest":await open_manifest(args[i+1]);return
func open_manifest(path: String) -> void:
	var result: Dictionary=await viewer.open_manifest(path);status.text="只读："+path if result.ok else str(result.error)
