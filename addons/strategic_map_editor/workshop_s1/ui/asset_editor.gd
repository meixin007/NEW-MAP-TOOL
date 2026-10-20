@tool
extends "../../dialog_shell.gd"
const Asset = preload("../asset_descriptor.gd")
const Model = preload("../project_model.gd")
const Preview = preload("asset_preview.gd")
signal saved(asset_ref: String)
var session
var asset_ref := ""
var selected_entity_id := ""
var preview
var label_field: LineEdit
var tags_field: LineEdit
var source_field: LineEdit
var category: OptionButton
var shadow: OptionButton
var nominal_width: SpinBox
var socket_picker: OptionButton
var socket_role: OptionButton
var socket_angle: SpinBox
var variant_angle: SpinBox
var variant_asset: OptionButton
var crop_fields: Array = []
var raw: TextEdit
var confirmed_paint: CheckBox
var adopt_selected: CheckBox
var feedback: Label
var _original: Dictionary = {}

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var b:=Button.new();b.text=caption;b.pressed.connect(action);parent.add_child(b);return b
func _field(parent: Node, caption: String, value: String) -> LineEdit:
	var l:=Label.new();l.text=caption;parent.add_child(l)
	var f:=LineEdit.new();f.text=value;parent.add_child(f);return f
func _spin(parent: Node, caption: String, value: float, minimum: float, maximum: float) -> SpinBox:
	var l:=Label.new();l.text=caption;parent.add_child(l)
	var f:=SpinBox.new();f.min_value=minimum;f.max_value=maximum;f.value=value;parent.add_child(f);return f
func _ready() -> void:
	title="资产描述 · 新版本与接点"
	ok_button_text="预览差异后保存新版本"
	super._ready()
	_original=session.snapshot().asset_refs[asset_ref].duplicate(true)
	var row:=HSplitContainer.new();row.custom_minimum_size=Vector2(850,460);content.add_child(row)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(left)
	preview=Preview.new();preview.descriptor=_original.duplicate(true)
	var image:=Image.new()
	if image.load_png_from_buffer(session.asset_bytes(_original))==OK: preview.texture=ImageTexture.create_from_image(image)
	left.add_child(preview)
	var modes:=HFlowContainer.new();left.add_child(modes)
	_button(modes,"拖锚点",func(): preview.mode="anchor")
	_button(modes,"描占地",func(): preview.mode="ground")
	_button(modes,"清空占地",func(): preview.descriptor.ground_footprint=[];preview.queue_redraw())
	_button(modes,"拖选中接点",func(): preview.mode="socket")
	var hint:=Label.new();hint.text="锚点与接点使用裁切后像素；占地使用 map_unit。\n描占地：先清空，再按顺序点击至少三个点。";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;left.add_child(hint)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.x=330;row.add_child(scroll)
	var form:=VBoxContainer.new();form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(form)
	label_field=_field(form,"资产名称",_original.label)
	tags_field=_field(form,"标签（逗号分隔）",", ".join(_original.tags))
	source_field=_field(form,"来源记录",_original.source_notice)
	category=OptionButton.new()
	for text in ["object","wall","gate","tower","building","tree","ground"]: category.add_item(text)
	category.select(["object","wall","gate","tower","building","tree","ground"].find(_original.category));form.add_child(category)
	shadow=OptionButton.new()
	for text in ["baked","separate","none"]: shadow.add_item(text)
	shadow.select(["baked","separate","none"].find(_original.shadow_mode));form.add_child(shadow)
	nominal_width=_spin(form,"标称宽度（等比）",_original.nominal_size_units[0],1,4096)
	var crop:=HFlowContainer.new();form.add_child(crop)
	for i in range(4): crop_fields.append(_spin(crop,["裁切 X","裁切 Y","宽","高"][i],_original.region_px[i],0,4096))
	_button(form,"应用裁切并同步锚点 / 接点",func():
		var values: Array=[]
		for field in crop_fields: values.append(int(field.value))
		var result:=Asset.with_region(preview.descriptor,values)
		if result.ok: preview.descriptor=result.descriptor;preview.queue_redraw();_refresh_raw()
		feedback.text="裁切已进入临时预览。" if result.ok else result.error)
	socket_picker=OptionButton.new();form.add_child(socket_picker)
	socket_picker.item_selected.connect(func(i): preview.socket_index=i;_refresh_socket())
	socket_role=OptionButton.new()
	for text in ["wall","road","entrance","attachment"]: socket_role.add_item(text)
	form.add_child(socket_role)
	socket_angle=_spin(form,"接点方向（度）",0,-360,360)
	_button(form,"新增接点",func():
		preview.descriptor.sockets.append({"socket_id":"socket_"+str(preview.descriptor.sockets.size())+"_"+str(Time.get_ticks_msec()),"position_px":preview.descriptor.anchor_px.duplicate(),"role":socket_role.get_item_text(socket_role.selected),"direction_deg":socket_angle.value})
		_refresh_sockets();socket_picker.select(socket_picker.item_count-1);preview.socket_index=socket_picker.item_count-1;preview.queue_redraw())
	_button(form,"应用接点方向 / 角色",func():
		if socket_picker.selected<0 or socket_picker.selected>=preview.descriptor.sockets.size(): return
		preview.descriptor.sockets[socket_picker.selected].direction_deg=socket_angle.value
		preview.descriptor.sockets[socket_picker.selected].role=socket_role.get_item_text(socket_role.selected)
		preview.queue_redraw();_refresh_raw())
	variant_angle=_spin(form,"允许方向（度）",0,0,359)
	variant_asset=OptionButton.new();form.add_child(variant_asset)
	for key in session.snapshot().asset_refs:
		variant_asset.add_item(session.snapshot().asset_refs[key].label)
		variant_asset.set_item_metadata(variant_asset.item_count-1,key)
	_button(form,"登记已制作方向变体",func():
		if variant_asset.selected>=0: preview.descriptor.orientation_variants[str(int(variant_angle.value))]=variant_asset.get_selected_metadata();_refresh_raw())
	_button(form,"移除此方向",func(): preview.descriptor.orientation_variants.erase(str(int(variant_angle.value)));_refresh_raw())
	confirmed_paint=CheckBox.new();confirmed_paint.text="确认黄色 paint 包含完整阴影";confirmed_paint.clip_text=true;content.add_child(confirmed_paint)
	adopt_selected=CheckBox.new();adopt_selected.text="仅更新当前选中对象";adopt_selected.clip_text=true;adopt_selected.disabled=selected_entity_id.is_empty();content.add_child(adopt_selected)
	raw=TextEdit.new();raw.custom_minimum_size.y=160;form.add_child(raw)
	_button(form,"从高级描述更新预览",func():
		var parsed: Variant=JSON.parse_string(raw.text)
		if not parsed is Dictionary: feedback.text="高级描述 JSON 无效。";return
		var issue:=Asset.validate(parsed)
		if not issue.is_empty(): feedback.text=issue;return
		if parsed.asset_id!=_original.asset_id or parsed.texture_sha256!=_original.texture_sha256: feedback.text="修改图像请重新导入，不能在元数据里替换文件身份。";return
		preview.descriptor=parsed;preview.queue_redraw();_refresh_sockets())
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(feedback)
	preview.edited.connect(_refresh_raw)
	_refresh_sockets();_refresh_raw()
	confirmed.connect(_save)
	canceled.connect(queue_free)

func _refresh_sockets() -> void:
	socket_picker.clear()
	for s in preview.descriptor.sockets: socket_picker.add_item(s.socket_id)
	preview.socket_index=maxi(0,socket_picker.selected)
	_refresh_socket()
func _refresh_socket() -> void:
	if socket_picker.selected<0: return
	var s: Dictionary=preview.descriptor.sockets[socket_picker.selected]
	socket_angle.value=float(s.direction_deg)
	socket_role.select(maxi(0,["wall","road","entrance","attachment"].find(s.role)))
func _refresh_raw() -> void:
	if is_instance_valid(raw): raw.text=JSON.stringify(preview.descriptor,"\t")
	if is_instance_valid(feedback): feedback.text="临时描述：占地 %d 点、接点 %d 个；原实例与素材未变化。"%[preview.descriptor.ground_footprint.size(),preview.descriptor.sockets.size()]
func _save() -> void:
	if not confirmed_paint.button_pressed:
		popup_centered(Vector2i(1050,680));feedback.text="请先确认完整 paint 范围。";return
	var next: Dictionary=preview.descriptor.duplicate(true)
	next.label=label_field.text.strip_edges()
	next.tags=Array(tags_field.text.split(",",false)).map(func(s): return str(s).strip_edges())
	next.source_notice=source_field.text.strip_edges()
	next.category=category.get_item_text(category.selected)
	next.shadow_mode=shadow.get_item_text(shadow.selected)
	next.nominal_size_units=[nominal_width.value,nominal_width.value*float(next.region_px[3])/float(next.region_px[2])]
	next.asset_version=Model.new_id("v")
	for angle in next.orientation_variants:
		var variant: String=next.orientation_variants[angle]
		if variant==asset_ref or variant==_original.asset_id: next.orientation_variants[angle]=next.asset_id
		elif not variant.contains("@"): next.orientation_variants[angle]=variant+"@"+_original.asset_version
	var issue:=Asset.validate(next)
	if not issue.is_empty(): popup_centered(Vector2i(1050,680));feedback.text=issue;return
	var result: Dictionary=session.dispatch({"op":"add_asset_version","descriptor":next,"adopt_entity_ids":[selected_entity_id] if adopt_selected.button_pressed else []})
	if not result.ok: popup_centered(Vector2i(1050,680));feedback.text=result.error;return
	saved.emit(Asset.key(next))
	queue_free()

func has_pending_changes() -> bool:
	return Model.Paths.digest(preview.descriptor)!=Model.Paths.digest(_original) or label_field.text!=_original.label or source_field.text!=_original.source_notice or tags_field.text!=", ".join(_original.tags) or category.get_item_text(category.selected)!=_original.category or shadow.get_item_text(shadow.selected)!=_original.shadow_mode or not is_equal_approx(nominal_width.value,float(_original.nominal_size_units[0])) or raw.text!=JSON.stringify(preview.descriptor,"\t")

func capture_draft() -> Dictionary:
	var crop: Array=[]
	for field in crop_fields: crop.append(field.value)
	return {"asset_ref":asset_ref,"selected_entity_id":selected_entity_id,"descriptor":preview.descriptor.duplicate(true),"label":label_field.text,"tags":tags_field.text,"source":source_field.text,"category":category.selected,"shadow":shadow.selected,"width":nominal_width.value,"crop":crop,"raw":raw.text,"paint_confirmed":confirmed_paint.button_pressed,"adopt_selected":adopt_selected.button_pressed}

func restore_draft(draft: Dictionary) -> void:
	preview.descriptor=draft.descriptor.duplicate(true)
	label_field.text=draft.label;tags_field.text=draft.tags;source_field.text=draft.source
	category.select(clampi(int(draft.category),0,6));shadow.select(clampi(int(draft.shadow),0,2));nominal_width.value=float(draft.width)
	for i in range(4): crop_fields[i].value=float(draft.crop[i])
	confirmed_paint.button_pressed=bool(draft.get("paint_confirmed",false));adopt_selected.button_pressed=bool(draft.get("adopt_selected",false))
	_refresh_sockets();_refresh_raw();raw.text=draft.raw;preview.queue_redraw()
