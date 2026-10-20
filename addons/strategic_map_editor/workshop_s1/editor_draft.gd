@tool
extends RefCounted
const A=preload("asset_descriptor.gd")
const Library=preload("template_library.gd")
static func validate(draft: Dictionary) -> String:
	if draft.has("selection_ids"):
		if not draft.selection_ids is Array or draft.selection_ids.size()>2000 or not draft.selection_ids.all(func(id):return id is String):return "恢复多选列表无效。"
	for key in ["library_fields","export_fields"]:
		if draft.has(key) and not draft[key] is Dictionary:return "恢复模板／导出属性必须为字典。"
	var d: Dictionary=draft.get("library_fields",{})
	if not d.is_empty():
		for key in ["title","version","kind","carry","selected_group_id","dirty","options_dirty","template","clipboard","values","raw_numbers","grid_kind","grid_visible","grid_snap","edge_snap","legend"]:
			if not d.has(key):return "模板恢复属性缺少字段。"
		for key in ["title","version","selected_group_id","legend"]:
			if not d[key] is String or d[key].length()>8192:return "模板恢复文本无效。"
		for key in ["carry","dirty","options_dirty","grid_visible","grid_snap","edge_snap"]:
			if not d[key] is bool:return "模板恢复开关无效。"
		for pair in [["kind",2],["grid_kind",1]]:
			if not A.numeric(d[pair[0]]) or float(d[pair[0]])!=floorf(float(d[pair[0]])) or d[pair[0]]<0 or d[pair[0]]>pair[1]:return "模板恢复选择越界。"
		if not d.values is Array or d.values.size()!=5 or not d.values.all(func(n):return A.numeric(n)) or not d.raw_numbers is Array or d.raw_numbers.size()!=5 or not d.raw_numbers.all(func(raw):return raw is String and raw.length()<256):return "模板恢复数字草稿无效。"
		if d.has("label_text"):
			if not d.label_text is String or d.label_text.length()>8192 or not d.get("label_id") is String or not d.get("label_dirty") is bool or not d.get("label_values") is Array or d.label_values.size()!=2 or not d.label_values.all(func(n):return A.numeric(n)) or not d.get("label_raw") is Array or d.label_raw.size()!=2 or not d.label_raw.all(func(s):return s is String and s.length()<256):return "标签恢复草稿无效。"
		for key in ["template","clipboard"]:
			if not d[key] is Dictionary:return "模板恢复内容无效。"
			if not d[key].is_empty():
				var issue:=Library.validate(d[key])
				if not issue.is_empty():return issue
	d=draft.get("export_fields",{})
	if not d.is_empty():
		if not d.get("destination") is String or d.destination.length()>4096 or not d.get("options") is Dictionary or not d.get("raw_numbers") is Array or d.raw_numbers.size()!=6 or not d.raw_numbers.all(func(raw):return raw is String and raw.length()<256):return "导出恢复属性无效。"
		var o: Dictionary=d.options
		if not o.get("bounds") is Array or o.bounds.size()!=4 or not o.bounds.all(func(n):return A.numeric(n)) or not A.numeric(o.get("scale")) or not A.numeric(o.get("tile_size")) or not o.get("selected_ids") is Array or not o.selected_ids.all(func(id):return id is String):return "导出恢复范围或选择无效。"
		for key in ["transparent_ground","layers","include_grid","include_legend"]:
			if not o.get(key) is bool:return "导出恢复开关无效。"
	return ""
static func resources(draft: Dictionary) -> Dictionary:
	var out: Dictionary={}
	for key in ["template","clipboard"]:
		for ref in draft.get("library_fields",{}).get(key,{}).get("asset_refs",{}):out[ref]=draft.library_fields[key].asset_refs[ref]
	return out
