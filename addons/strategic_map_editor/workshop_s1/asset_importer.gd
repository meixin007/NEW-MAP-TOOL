@tool
extends RefCounted
const OldImporter = preload("../art_importer.gd")
const Asset = preload("asset_descriptor.gd")
const Model = preload("project_model.gd")

func inspect_batch(paths: Array, source_notice: String, style_id: String) -> Dictionary:
	var items: Array = []
	var valid: Array = []
	if paths.size()>64 or source_notice.strip_edges().is_empty(): return {"ok":false,"error":"每批最多 64 张 PNG，且必须填写来源。","items":[],"valid":[]}
	var total := 0
	for i in range(paths.size()):
		var probe: Dictionary = OldImporter.probe(str(paths[i]))
		var item := {"index":i,"path":str(paths[i]),"ok":probe.ok,"error":str(probe.get("error",""))}
		if probe.ok:
			total += int(probe.bytes)
			var w := float(probe.width)
			var h := float(probe.height)
			var id := Model.new_id("asset")
			var descriptor := {"asset_id":id,"asset_version":"v1","style_id":style_id,"texture_ref":"assets/"+probe.sha256+".png","texture_sha256":probe.sha256,"texture_size_px":[w,h],"region_px":[0,0,w,h],"anchor_px":[w*0.5,h],"nominal_size_units":[120.0,120.0*h/w],"ground_footprint":[[-48,-16],[48,-16],[48,0],[-48,0]],"paint_envelope":[[0,0],[w,0],[w,h],[0,h]],"sockets":[],"orientation_variants":{"0":id},"shadow_mode":"baked","render_parts":[],"state_variants":{},"source_notice":source_notice.strip_edges(),"label":str(paths[i]).get_file().get_basename(),"tags":[],"category":"object"}
			item.descriptor = descriptor
			item.content = probe.content
			valid.append(item)
		items.append(item)
	if total>256*1024*1024: return {"ok":false,"error":"本批超过 256MiB，请减少图片数量。","items":items,"valid":[]}
	return {"ok":true,"items":items,"valid":valid,"bytes":total}

func commit_batch(session, batch: Dictionary, accepted_indices: Array) -> Dictionary:
	if not batch.get("ok",false) or accepted_indices.is_empty(): return {"ok":false,"error":"请选择并确认至少一件合格素材。"}
	var assets := {}
	var blobs := {}
	for i in accepted_indices:
		if not (i is int or i is float) or int(i)<0 or int(i)>=batch.items.size() or not batch.items[int(i)].ok: return {"ok":false,"error":"所选子集包含不合格素材，整批未提交。"}
		var item: Dictionary = batch.items[int(i)]
		var issue := Asset.validate(item.descriptor)
		if not issue.is_empty(): return {"ok":false,"error":issue}
		assets[Asset.key(item.descriptor)] = item.descriptor.duplicate(true)
		blobs[item.descriptor.texture_sha256] = item.content
	var result: Dictionary = session.dispatch({"op":"add_assets","assets":assets})
	if result.ok:
		for sha in blobs: session.asset_blobs[sha]=blobs[sha]
	return result

func import_pack(session, path: String) -> Dictionary:
	var parsed:=JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(path))!=OK or not parsed.data is Dictionary:return {"ok":false,"error":"素材包 JSON 无法读取。"}
	var pack: Dictionary=parsed.data
	if pack.get("document_type")!="shanhe.asset_pack" or pack.get("schema_version")!=1 or not pack.get("assets") is Array or pack.assets.is_empty() or pack.assets.size()>64:return {"ok":false,"error":"未知素材包协议或超出64件预算。"}
	var descriptors: Dictionary={};var blobs: Dictionary={};var bytes:=0
	for a in pack.assets:
		if not a is Dictionary:return {"ok":false,"error":"素材包描述无效。"}
		var issue:=Asset.validate(a)
		if not issue.is_empty():return {"ok":false,"error":issue}
		var key:=Asset.key(a)
		if descriptors.has(key) or session.snapshot().asset_refs.has(key):return {"ok":false,"error":"包内版本重复或已存在，未覆盖："+key}
		var probe:=probe_material(path.get_base_dir().path_join(a.texture_ref)) if a.category=="ground" and a.tags.has("surface_material") else OldImporter.probe(path.get_base_dir().path_join(a.texture_ref))
		if not probe.ok:return probe
		if probe.sha256!=a.texture_sha256 or probe.width!=a.texture_size_px[0] or probe.height!=a.texture_size_px[1]:return {"ok":false,"error":"素材包图片 hash／尺寸不符："+key}
		bytes+=probe.bytes
		if bytes>256*1024*1024:return {"ok":false,"error":"素材包超过256MiB预算。"}
		descriptors[key]=a.duplicate(true);blobs[a.texture_sha256]=probe.content
	var result: Dictionary=session.dispatch({"op":"add_assets","assets":descriptors})
	if result.ok:
		for hash in blobs:session.asset_blobs[hash]=blobs[hash]
	return result

static func probe_material(path: String) -> Dictionary:
	# Opaque tile materials have no cutout margin; ordinary sprite validation stays unchanged.
	if not path.to_lower().ends_with(".png") or not FileAccess.file_exists(path):return {"ok":false,"error":"表面材质须为本机 PNG。"}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"ok":false,"error":"无法读取表面材质。"}
	if file.get_length()>32*1024*1024:file.close();return {"ok":false,"error":"单张表面材质超过32MiB。"}
	var content:=file.get_buffer(file.get_length());file.close()
	if content.size()<24 or content.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return {"ok":false,"error":"表面材质 PNG 签名无效。"}
	var width: int=(int(content[16])<<24)+(int(content[17])<<16)+(int(content[18])<<8)+int(content[19]);var height: int=(int(content[20])<<24)+(int(content[21])<<16)+(int(content[22])<<8)+int(content[23])
	if content.slice(12,16)!=PackedByteArray([73,72,68,82]) or width<32 or height<32 or width>4096 or height>4096:return {"ok":false,"error":"表面材质头部或尺寸无效。"}
	var image:=Image.new()
	if image.load_png_from_buffer(content)!=OK or image.get_width()<32 or image.get_height()<32 or image.get_width()>4096 or image.get_height()>4096:return {"ok":false,"error":"表面材质尺寸须为32—4096像素。"}
	if image.get_used_rect().size==Vector2i.ZERO:return {"ok":false,"error":"表面材质不能全透明。"}
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(content)
	return {"ok":true,"width":image.get_width(),"height":image.get_height(),"bytes":content.size(),"sha256":hash.finish().hex_encode(),"content":content}
