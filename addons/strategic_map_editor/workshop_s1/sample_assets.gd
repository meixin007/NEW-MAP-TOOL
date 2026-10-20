@tool
extends RefCounted
## Original geometric engineering fixtures. These are explicitly NOT finished art.
const Importer = preload("asset_importer.gd")
const Asset = preload("asset_descriptor.gd")
const NAMES := ["灰盒_关门","灰盒_横墙","灰盒_纵墙","灰盒_角楼","灰盒_仓储","灰盒_院落","灰盒_阔叶树","灰盒_针叶树","灰盒_地面","灰盒_坡岸"]

static func install(session, directory: String) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK: return {"ok":false,"error":"无法创建独立灰盒目录。"}
	var paths: Array = []
	for i in range(NAMES.size()):
		var image := Image.create(160,128,false,Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var stone := Color("7d867f")
		var roof := Color("667b80")
		if i == 0:
			image.fill_rect(Rect2i(12,48,52,56),stone)
			image.fill_rect(Rect2i(96,48,52,56),stone)
			image.fill_rect(Rect2i(36,18,88,26),roof)
			image.fill_rect(Rect2i(48,42,16,62),Color("55615c"))
			image.fill_rect(Rect2i(96,42,16,62),Color("55615c"))
		elif i == 1:
			image.fill_rect(Rect2i(8,56,144,48),stone)
			for x in range(12,148,20): image.fill_rect(Rect2i(x,48,12,10),Color("a0a79c"))
		elif i == 2:
			image.fill_rect(Rect2i(60,16,40,96),stone)
			image.fill_rect(Rect2i(54,16,12,96),Color("a0a79c"))
		elif i == 3:
			image.fill_rect(Rect2i(48,40,64,64),stone)
			image.fill_rect(Rect2i(36,24,88,24),roof)
		elif i in [4,5]:
			image.fill_rect(Rect2i(28,58,104,46),Color("b9b09b"))
			image.fill_rect(Rect2i(20,34,120,36),roof)
			if i==5: image.fill_rect(Rect2i(60,56,40,40),Color("d5cbb3"))
		elif i in [6,7]:
			image.fill_rect(Rect2i(76,54,8,52),Color("8b785d"))
			for y in range(22,76):
				var half := int(30 if i==6 else (y-16)*0.6)
				image.fill_rect(Rect2i(80-half,y,half*2,1),Color("819a70") if i==6 else Color("657e65"))
		else:
			image.fill_rect(Rect2i(12,46,136,58),Color("c4b896") if i==8 else Color("a9ac89"))
			for x in range(18,144,16): image.fill_rect(Rect2i(x,64,6,2),Color("b3a787"))
		var path := directory.path_join("prototype_%02d.png"%i)
		if image.save_png(path)!=OK: return {"ok":false,"error":"无法写入灰盒 PNG。"}
		paths.append(path)
	var importer := Importer.new()
	var batch := importer.inspect_batch(paths,"自有几何灰盒；源码 sample_assets.gd；非正式美术、非商业素材", "engineering_graybox_pending")
	if not batch.ok or batch.valid.size()!=10: return {"ok":false,"error":"灰盒批量校验失败。"}
	var ids: Array = []
	for item in batch.items: ids.append(item.descriptor.asset_id)
	for i in range(batch.items.size()):
		var a: Dictionary = batch.items[i].descriptor
		a.label=NAMES[i]
		a.tags=["灰盒","技术小样","待画风审核"]
		a.shadow_mode="none"
		a.category=["gate","wall","wall","tower","building","building","tree","tree","ground","ground"][i]
		a.nominal_size_units=[160.0,128.0]
		a.anchor_px=[80.0,104.0]
		a.ground_footprint=[[-60,-16],[60,-16],[60,8],[-60,8]] if i not in [2,3,6,7] else [[-20,-30],[20,-30],[20,8],[-20,8]]
		if i in [1,2]:
			a.default_orientation=90.0 if i==2 else 0.0
			a.orientation_variants={"0":ids[1],"90":ids[2],"180":ids[1],"270":ids[2]}
			a.sockets=[{"socket_id":"a","position_px":[8,104] if i==1 else [80,16],"direction_deg":180.0 if i==1 else 270.0,"role":"wall"},{"socket_id":"b","position_px":[152,104] if i==1 else [80,112],"direction_deg":0.0 if i==1 else 90.0,"role":"wall"}]
		elif i==0:
			a.passage_width_units=32.0
			a.sockets=[{"socket_id":"wall_a","position_px":[12,104],"direction_deg":180.0,"role":"wall"},{"socket_id":"wall_b","position_px":[148,104],"direction_deg":0.0,"role":"wall"},{"socket_id":"entrance","position_px":[80,104],"direction_deg":90.0,"role":"road"}]
		elif i==3:
			a.sockets=[{"socket_id":"west","position_px":[48,104],"direction_deg":180.0,"role":"wall"},{"socket_id":"east","position_px":[112,104],"direction_deg":0.0,"role":"wall"},{"socket_id":"north","position_px":[80,72],"direction_deg":270.0,"role":"wall"},{"socket_id":"south","position_px":[80,104],"direction_deg":90.0,"role":"wall"}]
		elif i in [4,5]: a.sockets=[{"socket_id":"entrance","position_px":[80,104],"direction_deg":90.0,"role":"road"}]
	var accepted: Array = range(10)
	var result := importer.commit_batch(session,batch,accepted)
	result.graybox = true
	return result
