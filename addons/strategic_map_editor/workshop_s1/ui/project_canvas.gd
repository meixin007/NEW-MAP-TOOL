@tool
extends Control
const Model = preload("../project_model.gd")
const Plan = preload("../render_plan.gd")
const SurfaceProject = preload("../surface_projection.gd")
const Paths = preload("../path_generator.gd")
const EntityGeometry = preload("../entity_geometry.gd")
const PlotGeometry=preload("../plot_geometry.gd")
const Brush=preload("../brush_sampler.gd")
const Terrain=preload("../terrain_geometry.gd")
const Support=preload("../support_query.gd")
const Compounds=preload("../compound_model.gd")
signal compound_drawn(points: Array,tool: String)
signal district_drawn(points: Array,tool: String)
signal district_lot_selected(recipe_id: String,candidate_id: String)
var compound_points: Array=[]
var district_points: Array=[]
var compound_target_id: String=""
var show_district_lots:=true
signal terrain_drawn(points: Array,tool: String)
signal terrain_selected(surface_id: String)
signal support_ambiguous(choices: Array,entity: Dictionary)
signal plot_drawn(outer: Array, shape: String, hole: bool)
signal brush_drawn(recipe: Dictionary)
signal brush_started
signal selected(entity_id: String)
signal reported(message: String)
signal recipe_selected(recipe_id: String, point_id: String)
signal template_placed(point: Array)
signal label_placed(point: Array)
var _brush_surface_id: String="ground"
var _brush_next_surface: String=""
var automatic_surface:=true
var terrain_points: Array=[]
var terrain_parent: String="ground"
var terrain_from: String="ground"
var terrain_to: String="ground"
var selected_terrain_id: String=""
var session
var mode := "select"
var selected_id := ""
var zoom := 0.7
var pan := Vector2(30,30)
var _panning := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_entity: Dictionary = {}
var entries: Array = []
var _last_revision := -1
var _view_project: Dictionary = {}
var _textures: Dictionary = {}
var _hit_masks: Dictionary = {}
var show_envelopes := true
var active_asset_ref := ""
var active_surface_id := "ground"
var active_orientation := 0.0
var selected_recipe_id := ""
var selected_point_id := ""
var path_type := "road"
var path_style := "dirt"
var path_width := 24.0
var path_seed := 42
var path_wall_ref := ""
var path_points: Array = []
var _point_dragging := false
var _transient_command: Dictionary={}
var _transient_layer: Node2D
var edit_pending:=false
var snap_source_socket := ""
var snap_source_entity_id := ""
var snap_target_entity_id := ""
var _last_drag_error := ""
var plot_points: Array=[]
var plot_shape: String="rectangle"
var selected_plot_id: String=""
var brush_template: Dictionary={}
var brush_points: Array=[]
var _brush_drawing:=false
var _brush_overflow:=false
var show_plot_boundaries:=true
var render_only:=false
var preview_only:=false
var render_background:=true
var draw_paper:=true
var export_indices: Array=[]
var export_selected: Array=[]
var export_ground_only:=false
var export_include_grid:=false
var export_include_legend:=false
var export_overlay:=false
var _world_layer: Node2D
var _paint_signature: String=""
var _paint_revision: int=-1
var _preview_serial: int=-1
var draw_rebuilds: int=0
var plan_rebuilds: int=0
var last_plan_build_ms:=0.0
var _render_dependencies: String=""
var _paint_bounds:=Rect2()

func texture_for(a: Dictionary) -> Texture2D:
	if _textures.has(a.texture_sha256): return _textures[a.texture_sha256]
	var bytes: PackedByteArray = session.asset_bytes(a)
	if bytes.is_empty(): return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes)!=OK: return null
	var mask:=BitMap.new();mask.create_from_image_alpha(image,0.1);_hit_masks[a.texture_sha256]=mask
	var texture := ImageTexture.create_from_image(image)
	_textures[a.texture_sha256] = texture
	return texture

func asset_hit(entry: Dictionary,point: Vector2) -> bool:
	var a: Dictionary=entry.descriptor
	if not _hit_masks.has(a.texture_sha256):texture_for(a)
	if not _hit_masks.has(a.texture_sha256):return true # Missing asset remains selectable.
	var local: Vector2=(point-entry.position).rotated(-float(entry.rotation))
	if not entry.local_rect.has_point(local):return false
	var uv: Vector2=entry.source_rect.position+(local-entry.local_rect.position)/float(entry.unit)
	var mask: BitMap=_hit_masks[a.texture_sha256];var pixel:=Vector2i(uv.floor())
	return pixel.x>=0 and pixel.y>=0 and pixel.x<mask.get_size().x and pixel.y<mask.get_size().y and mask.get_bitv(pixel)

func _ready() -> void:
	_world_layer=preload("world_painter.gd").new();_world_layer.host=self;add_child(_world_layer)
	_transient_layer=preload("transient_painter.gd").new();_transient_layer.host=self;add_child(_transient_layer)
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	custom_minimum_size = Vector2(350,300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_process(true)

func _process(_delta: float) -> void:
	if not edit_pending:return
	var result: Dictionary=session.poll_preview_job()
	if result.status=="working":return
	edit_pending=false;_transient_command={};_transient_layer.queue_redraw();queue_redraw()
	if result.status=="committed":reported.emit("拖动已完整验证并提交；可撤销。")
	elif result.status=="failed":reported.emit(str(result.error))
	elif result.status=="discarded":reported.emit(str(result.message))

func world_at(screen: Vector2) -> Vector2:
	return (screen-pan)/zoom

func fit_map() -> void:
	if session == null: return
	var p: Dictionary = session.view()
	var extent := Vector2(p.legacy_document.canvas_size[0],p.legacy_document.canvas_size[1])
	var projected:=PackedVector2Array()
	for q in [Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)]:projected.append(SurfaceProject.project_point(p,q))
	var box:=Plan.bounds(projected)
	zoom = minf((size.x-60)/box.size.x,(size.y-60)/box.size.y)
	pan = (size-box.size*zoom)*0.5-box.position*zoom
	queue_redraw()

func _draw() -> void:
	if render_background:draw_rect(Rect2(Vector2.ZERO,size),Color("26322f"))
	if session==null or not is_instance_valid(_world_layer):return
	var serial: int=session.view_revision
	if _last_revision!=session.revision or _preview_serial!=serial:
		var next: Dictionary=session.preview_view()
		var used: Dictionary={}
		for a in next.asset_refs.values():used[a.texture_sha256]=true
		for hash in _textures.keys():
			if not used.has(hash):_textures.erase(hash);_hit_masks.erase(hash)
		var dependencies: String=Model.Paths.digest([next.asset_refs,next.surfaces,next.style_profile.ground_matrix,next.style_profile.height_axis,next.legacy_document.features])
		if _view_project.is_empty() or _view_project.materialized_snapshot.entities!=next.materialized_snapshot.entities or dependencies!=_render_dependencies:
			var began:=Time.get_ticks_usec()
			var prepared: Dictionary=session.prepared_render_plan(next)
			entries=prepared.entries if prepared.ok else Plan.build(next);plan_rebuilds+=1;last_plan_build_ms=(Time.get_ticks_usec()-began)/1000.0
		_view_project=next;_render_dependencies=dependencies
		_last_revision=session.revision;_preview_serial=serial
	_world_layer.position=pan;_world_layer.scale=Vector2.ONE*zoom
	var view:=Rect2(-pan/zoom,size/zoom)
	if not _paint_bounds.encloses(view):_paint_bounds=view.grow(384/zoom)
	var signature: String=str([session.revision,serial,zoom,_paint_bounds,selected_id,mode,selected_recipe_id,selected_point_id,path_points,plot_points,brush_points,terrain_points,compound_points,district_points,show_envelopes,show_plot_boundaries,show_district_lots,selected_terrain_id,render_only,draw_paper,export_indices,export_selected,export_ground_only,export_include_grid,export_include_legend,export_overlay])
	if signature!=_paint_signature:
		_paint_signature=signature;_world_layer.queue_redraw()

func paint_world(drawer: CanvasItem) -> void:
	draw_rebuilds+=1
	var p: Dictionary = _view_project
	drawer.draw_set_transform(Vector2.ZERO)
	var paper:=PackedVector2Array();var extent:=Vector2(p.legacy_document.canvas_size[0],p.legacy_document.canvas_size[1])
	for q in [Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)]:paper.append(SurfaceProject.project_point(p,q))
	if draw_paper:drawer.draw_colored_polygon(paper,Color(str(p.style_profile.get("paper_color","e4dfcb"))) if p.style_profile.paper_enabled else Color("b1b7a0"))
	for surface in p.surfaces:
		if not draw_paper or surface.surface_id == "ground" or surface.has("kind"): continue
		var outline := PackedVector2Array()
		for point in surface.outline: outline.append(SurfaceProject.project_point(p,Vector2(point[0],point[1]),surface.surface_id))
		drawer.draw_colored_polygon(outline,Color("b0b79a"))
		outline.append(outline[0])
		drawer.draw_polyline(outline,Color("677660"),2.0/zoom)
	var visible:=_paint_bounds
	for index in range(entries.size()):
		var e: Dictionary=entries[index]
		if render_only:
			if not export_indices.is_empty() and index not in export_indices:continue
			if not export_selected.is_empty() and e.entity_id not in export_selected:continue
			if export_ground_only and e.entity.kind!="terrain" and e.get("render_layer",2)!=0 and e.entity.kind!="ribbon":continue
		if not visible.intersects(e.paint_bounds): continue
		var pos: Vector2 = e.position
		if e.entity.kind == "terrain":
			_draw_terrain(e,drawer)
		elif e.entity.kind == "legacy_label":
			drawer.draw_string(ThemeDB.fallback_font,pos,str(e.entity.label),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("334139"))
		elif e.entity.kind=="compound":
			var polygon: PackedVector2Array=e.polygons[0];var texture: Texture2D=texture_for(p.asset_refs[e.material]) if not e.material.is_empty() else null
			drawer.draw_polygon(polygon,PackedColorArray([e.color]),e.uvs,texture)
			if e.outline:
				var ink:=polygon.duplicate();ink.append(ink[0]);drawer.draw_polyline(ink,Color("504734"),0.9,true)
		elif e.entity.kind == "ribbon":
			var tint:=Color("b7a57d") if e.entity.style=="dirt" else (Color("9eaaa2") if e.entity.style=="stone" else Color("97c0bf"))
			for polygon in e.polygons: drawer.draw_colored_polygon(polygon,tint)
		elif e.entity.kind == "asset":
			var texture := texture_for(e.descriptor)
			if texture != null:
				drawer.draw_set_transform(pos,float(e.rotation))
				drawer.draw_texture_rect_region(texture,e.local_rect,e.source_rect)
				drawer.draw_set_transform(Vector2.ZERO)
			else:
				drawer.draw_rect(e.paint_bounds,Color("a86a5a"),false,2.0/zoom)
				drawer.draw_string(ThemeDB.fallback_font,pos,"缺资源",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("8c3024"))
			if show_envelopes and (e.entity_id==selected_id or mode=="socket_snap"):
				var footprint := PackedVector2Array()
				for point in e.ground_footprint: footprint.append(SurfaceProject.project_point(p,point,e.entity.surface_id,float(e.entity.local_height)))
				footprint.append(footprint[0])
				drawer.draw_polyline(footprint,Color("55966b"),2.0/zoom)
				for socket in e.descriptor.sockets:
					var socket_pos: Vector2 = pos+(Vector2(socket.position_px[0],socket.position_px[1])-Vector2(e.descriptor.anchor_px[0],e.descriptor.anchor_px[1])).rotated(float(e.rotation))*float(e.unit)
					drawer.draw_circle(socket_pos,4.0/zoom,Color("429dc3"))
		else:
			drawer.draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-32),pos+Vector2(16,0),pos+Vector2(-16,0)]),Color("7e9680"))
			drawer.draw_string(ThemeDB.fallback_font,pos+Vector2(20,-8),str(e.entity.get("label","")),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("334139"))
		if e.entity_id == selected_id and e.entity.kind!="compound": drawer.draw_rect(e.paint_bounds,Color("d89024"),false,2.0/zoom)
	if render_only:
		_draw_editor_overlays(p,drawer);return
	for recipe in p.recipes:
		if recipe.kind!="path" or recipe.recipe_id!=selected_recipe_id: continue
		var line:=PackedVector2Array()
		for point in recipe.control_points: line.append(SurfaceProject.project_point(p,Vector2(point.ground_xy[0],point.ground_xy[1]),recipe.surface_id))
		drawer.draw_polyline(line,Color("cc9f47"),1.5/zoom)
		for i in range(recipe.control_points.size()):
			drawer.draw_circle(line[i],(6.0 if recipe.control_points[i].point_id==selected_point_id else 4.0)/zoom,Color("dca441"))
	if not path_points.is_empty():
		var line:=PackedVector2Array()
		for point in path_points: line.append(SurfaceProject.project_point(p,Vector2(point[0],point[1]),active_surface_id))
		for point in line: drawer.draw_circle(point,4.0/zoom,Color("e0b348"))
		if line.size()>1: drawer.draw_polyline(line,Color("e0b348"),3.0/zoom)
	_draw_plots(p,drawer)
	_draw_w5(p,drawer)
	_draw_editor_overlays(p,drawer)
	if not terrain_points.is_empty():
		var line:=PackedVector2Array()
		for i in range(terrain_points.size()):line.append(SurfaceProject.project_point(p,Terrain.vec(terrain_points[i]),terrain_from if mode=="terrain_ramp" and i==0 else (terrain_to if mode=="terrain_ramp" else terrain_parent)))
		for q in line:drawer.draw_circle(q,4/zoom,Color("c98c35"))
		if line.size()>1:drawer.draw_polyline(line,Color("c98c35"),2/zoom)
	var selected_surface:=Terrain.surface(p,selected_terrain_id)
	if selected_surface.get("kind")=="terrace":
		for q in Terrain.outline(selected_surface):drawer.draw_circle(SurfaceProject.project_point(p,q,selected_terrain_id),3/zoom,Color("c98c35"))
	drawer.draw_set_transform(Vector2.ZERO)

func cancel() -> void:
	_dragging = false
	_point_dragging = false
	_last_drag_error = ""
	_drag_entity={};_transient_command={};
	if is_instance_valid(_transient_layer):_transient_layer.queue_redraw()
	terrain_points.clear()
	compound_points.clear();district_points.clear()
	path_points.clear()
	plot_points.clear();brush_points.clear();_brush_drawing=false
	_brush_overflow=false
	session.cancel_preview()
	_last_revision = -1
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if session == null: return
	if render_only:return
	if edit_pending and ((event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventKey and event.keycode==KEY_DELETE)):
		reported.emit("正在验证拖动；请等待结果，或按Esc取消。");accept_event();return
	if event is InputEventMouseButton:
		grab_focus()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var world := world_at(event.position)
			zoom = clampf(zoom*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),0.08,6.0)
			pan = event.position-world*zoom
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			cancel()
			_panning = event.pressed
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			mode = "select"
			accept_event()
			return
		if preview_only:return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var world := world_at(event.position)
			if event.pressed and mode in ["template_place","label_place"]:
				if session.has_preview() or session.job_in_progress():reported.emit("先应用或取消预览。");return
				var point:=SurfaceProject.ground_point(session.view(),world,"ground")
				var style: Dictionary=session.view().style_profile
				if style.get("grid_snap",false):point=preload("../snap_resolver.gd").hex_round(point,style.get("grid_size",32)) if style.get("grid_kind")=="hex" else point.snapped(Vector2.ONE*float(style.get("grid_size",32)))
				if mode=="template_place":template_placed.emit([point.x,point.y])
				else:label_placed.emit([point.x,point.y])
				queue_redraw();accept_event();return
			if event.pressed and (mode.begins_with("compound_") or mode in ["district_rectangle","district_polygon","district_hole"]):
				if session.has_preview() or session.job_in_progress():reported.emit("请先应用或取消预览。");return
				var q:=SurfaceProject.ground_point(session.view(),world,active_surface_id)
				if mode in ["compound_room","compound_hole"]:
					var target:=_compound_target(session.view())
					if target.is_empty():reported.emit("待编辑的院落不存在。");return
					q=(SurfaceProject.ground_point(session.view(),world,target.surface_id)-Terrain.vec(target.ground_xy)).rotated(-deg_to_rad(float(target.orientation)))/float(target.scale)
				if mode.begins_with("compound_"):
					compound_points.append([snappedf(q.x,1),snappedf(q.y,1)])
					if compound_points.size()==2:finish_w5()
				else:
					if district_points.size()>=128:reported.emit("街区最多128个点。");return
					district_points.append([snappedf(q.x,1),snappedf(q.y,1)])
					if mode=="district_rectangle" and district_points.size()==2:finish_w5()
				queue_redraw();accept_event();return
			if event.pressed and mode=="district_lot":
				for lot in session.view().materialized_snapshot.get("lots",[]):
					var q:=SurfaceProject.ground_point(session.view(),world,lot.surface_id)
					if Geometry2D.is_point_in_polygon(q,Model.Asset.packed(lot.polygon)):district_lot_selected.emit(lot.recipe_id,lot.candidate_id);queue_redraw();accept_event();return
				reported.emit("此处没有完整合法地块。");accept_event();return
			if event.pressed and mode in ["terrain_rectangle","terrain_polygon","terrain_ramp"]:
				if session.has_preview() or session.job_in_progress():reported.emit("请先应用或取消预览。");return
				if terrain_points.size()>=128:reported.emit("台地最多128个点。");return
				var id: String=terrain_parent if mode!="terrain_ramp" else (terrain_from if terrain_points.is_empty() else terrain_to)
				var q:=SurfaceProject.ground_point(session.view(),world,id)
				terrain_points.append([snappedf(q.x,1),snappedf(q.y,1)])
				if mode!="terrain_polygon" and terrain_points.size()==2:finish_terrain()
				queue_redraw();accept_event();return
			if mode=="plot_brush":
				if event.pressed:
					if session.job_in_progress() or session.has_preview():reported.emit("请先应用或取消现有候选。");return
					brush_started.emit()
					if automatic_surface and Terrain.enabled(session.view()):
						var weights: Array=brush_template.get("asset_weights",[])
						var template: Dictionary={"kind":"marker","local_height":0}
						if not weights.is_empty():template={"kind":"asset","asset_ref":weights[0].asset_ref,"scale":float(brush_template.get("scale_range",[1,1])[1]),"orientation":float(session.view().asset_refs[weights[0].asset_ref].get("default_orientation",0)),"local_height":0}
						var choices:=Support.candidates(session.view(),world,template)
						if not _brush_next_surface.is_empty():choices=choices.filter(func(c):return c.surface_id==_brush_next_surface);_brush_next_surface=""
						if choices.size()>1:support_ambiguous.emit(choices,{"brush_choice":true});accept_event();return
						if choices.is_empty():reported.emit("落笔点没有完整支撑素材的可用面，整笔未开始。");return
						active_surface_id=choices[0].surface_id;brush_template.surface_id=active_surface_id
					_brush_surface_id=str(brush_template.get("surface_id",active_surface_id))
					_brush_drawing=true;_brush_overflow=false;brush_points=[];_append_brush_point(world)
				elif _brush_drawing:
					_append_brush_point(world);_brush_drawing=false
					if _brush_overflow:brush_points.clear();reported.emit("本笔超过256个转折点，整笔未提交；请分笔绘制。");queue_redraw();accept_event();return
					var recipe: Dictionary=brush_template.duplicate(true);recipe.recipe_id=Model.new_id("brush");recipe.stroke_points=Brush.normalize(brush_points)
					brush_points.clear();brush_drawn.emit(recipe)
				queue_redraw();accept_event();return
			if event.pressed and mode in ["plot_draw","plot_hole"]:
				if session.job_in_progress() or session.has_preview():reported.emit("请先应用或取消现有候选。");return
				var point:=SurfaceProject.ground_point(session.view(),world,active_surface_id)
				if point.x<0 or point.y<0 or point.x>session.view().legacy_document.canvas_size[0] or point.y>session.view().legacy_document.canvas_size[1]:reported.emit("区域点超出画布。");return
				if plot_points.size()>=128:reported.emit("区域最多128个点。");return
				plot_points.append([snappedf(point.x,1),snappedf(point.y,1)])
				if mode=="plot_draw" and plot_shape!="polygon" and plot_points.size()==2:finish_plot()
				queue_redraw();accept_event();return
			if event.pressed and mode=="path_draw":
				var point:=SurfaceProject.ground_point(session.view(),world,active_surface_id)
				var extent: Array=session.view().legacy_document.canvas_size
				if point.x<0 or point.y<0 or point.x>extent[0] or point.y>extent[1] or path_points.size()>=256: reported.emit("控制点超出画布或已达到 256 点上限。 ");return
				path_points.append([snappedf(point.x,1),snappedf(point.y,1)])
				queue_redraw();accept_event();return
			if event.pressed and mode=="path_insert":
				var recipe:=paths_recipe()
				if recipe.is_empty(): reported.emit("先选择一条路径。 ");return
				var p:=SurfaceProject.ground_point(session.view(),world,recipe.surface_id)
				var closest:=INF
				var chosen: Dictionary={}
				for i in range(recipe.segments.size()):
					var a:=Vector2(recipe.control_points[i].ground_xy[0],recipe.control_points[i].ground_xy[1])
					var b:=Vector2(recipe.control_points[i+1].ground_xy[0],recipe.control_points[i+1].ground_xy[1])
					var q:=Geometry2D.get_closest_point_to_segment(p,a,b)
					if p.distance_to(q)<closest: closest=p.distance_to(q);chosen={"segment_id":recipe.segments[i].segment_id,"ground_xy":[q.x,q.y]}
				if closest*zoom>16: reported.emit("请点在所选路径附近。 ");return
				var result: Dictionary=session.dispatch({"op":"split_path_segment","recipe_id":selected_recipe_id,"segment_id":chosen.segment_id,"ground_xy":chosen.ground_xy})
				if not result.ok: reported.emit(result.error)
				accept_event();return
			if event.pressed and mode=="socket_snap":
				var source: Dictionary={}
				var target: Dictionary={}
				for e in session.view().materialized_snapshot.entities:
					if e.entity_id==snap_source_entity_id: source=e
				if source.is_empty(): reported.emit("来源对象不存在。 ");return
				var source_socket: Dictionary={}
				for socket in EntityGeometry.sockets(session.view(),source):
					if socket.socket_id==snap_source_socket: source_socket=socket
				if source_socket.is_empty(): reported.emit("来源接点不存在。 ");return
				var best:=16.0/zoom
				var target_socket: String=""
				for e in session.view().materialized_snapshot.entities:
					if e.entity_id==source.entity_id or e.surface_id!=source.surface_id or (not snap_target_entity_id.is_empty() and e.entity_id!=snap_target_entity_id): continue
					for socket in EntityGeometry.sockets(session.view(),e):
						if socket.role!=source_socket.role or absf(wrapf(float(source_socket.direction_deg)-float(socket.direction_deg)-180,-180,180))>3.0: continue
						var point:=SurfaceProject.project_point(session.view(),Vector2(socket.ground_xy[0],socket.ground_xy[1]),e.surface_id,float(e.local_height))
						if point.distance_to(world)<best: best=point.distance_to(world);target=e;target_socket=socket.socket_id
				if target.is_empty(): reported.emit("16 屏幕像素内没有相容接点；可先在对象列表指定目标。 ");return
				var result: Dictionary=session.dispatch({"op":"snap_entity","entity_id":source.entity_id,"source_socket":snap_source_socket,"target_entity_id":target.entity_id,"target_socket":target_socket})
				if not result.ok: reported.emit(result.error)
				else: reported.emit("已按相容接点一次吸附；可撤销。")
				accept_event();return
			if event.pressed and mode=="path_edit":
				var recipe:=paths_recipe()
				for point in recipe.get("control_points",[]):
					var projected:=SurfaceProject.project_point(session.view(),Vector2(point.ground_xy[0],point.ground_xy[1]),recipe.surface_id)
					if projected.distance_to(world)*zoom<=10:
						selected_point_id=point.point_id;_point_dragging=true;_last_drag_error="";_transient_command={};recipe_selected.emit(selected_recipe_id,selected_point_id);queue_redraw();accept_event();return
			if event.pressed and mode in ["marker","asset"]:
				var point := SurfaceProject.ground_point(session.view(),world,active_surface_id)
				var id := Model.new_id("manual")
				var entity := {"entity_id":id,"kind":"marker","ground_xy":[point.x,point.y],"surface_id":active_surface_id,"local_height":0.0,"label":"手工对象"}
				if mode == "asset":
					if not session.view().asset_refs.has(active_asset_ref): reported.emit("请选择已导入资产。 ");return
					entity.merge({"kind":"asset","asset_ref":active_asset_ref,"orientation":active_orientation,"scale":1.0,"label":session.view().asset_refs[active_asset_ref].label,"management":"manual"},true)
				if automatic_surface and Terrain.enabled(session.view()):
					var choices:=Support.candidates(session.view(),world,entity)
					if choices.size()>1:support_ambiguous.emit(choices,entity);accept_event();return
					if choices.is_empty():reported.emit("没有完整支撑该占地的可用面，未放置。");return
					entity.surface_id=choices[0].surface_id;entity.ground_xy=choices[0].ground_xy
				place_entity(entity)
			elif event.pressed:
				selected_id = Plan.pick(entries,world,asset_hit)
				if selected_id.begins_with("surface:"):
					selected_terrain_id=selected_id.trim_prefix("surface:");terrain_selected.emit(selected_terrain_id);queue_redraw();accept_event();return
				selected.emit(selected_id)
				for entity in session.view().materialized_snapshot.entities:
					if entity.entity_id == selected_id:
						if entity.kind=="ribbon":
							if entity.get("role")!="district_street":selected_recipe_id=entity.recipe_id;recipe_selected.emit(selected_recipe_id,"")
							break
						_drag_entity = entity
						_drag_offset = SurfaceProject.ground_point(session.view(),world,entity.surface_id,float(entity.local_height))-Vector2(entity.ground_xy[0],entity.ground_xy[1])
						_dragging = true
						_last_drag_error = ""
						_transient_command={}
			elif _point_dragging:
				_point_dragging=false
				if not _last_drag_error.is_empty(): _transient_command={};reported.emit(_last_drag_error)
				else:
					var result: Dictionary=_commit_drag()
					if not result.ok: reported.emit(result.error)
				_last_revision=-1
			elif _dragging:
				_dragging = false
				if not _last_drag_error.is_empty(): _transient_command={};reported.emit(_last_drag_error)
				else:
					var result: Dictionary = _commit_drag()
					if not result.ok: reported.emit(result.error)
				_last_revision=-1
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if _brush_drawing:
			_append_brush_point(world_at(event.position));queue_redraw()
		elif _panning:
			pan += event.relative
			queue_redraw()
		elif _point_dragging:
			var recipe:=paths_recipe()
			var point:=SurfaceProject.ground_point(session.view(),world_at(event.position),recipe.surface_id)
			var result: Dictionary=_preview_drag({"op":"update_path_point","recipe_id":selected_recipe_id,"point_id":selected_point_id,"patch":{"ground_xy":[snappedf(point.x,1),snappedf(point.y,1)]}})
			_last_drag_error="" if result.ok else str(result.error)
			if not result.ok: reported.emit(result.error)
			queue_redraw()
		elif _dragging:
			var point := SurfaceProject.ground_point(session.view(),world_at(event.position),_drag_entity.surface_id,float(_drag_entity.local_height))-_drag_offset
			var snapped: Dictionary={"ground_xy":[point.x,point.y]} # Socket solve runs once on release.
			if session.view().style_profile.get("grid_snap",false):
				var grid: float=session.view().style_profile.get("grid_size",32)
				var q: Vector2=preload("../snap_resolver.gd").hex_round(point,grid) if session.view().style_profile.get("grid_kind")=="hex" else point.snapped(Vector2.ONE*grid)
				snapped.ground_xy=[q.x,q.y]
			var result: Dictionary = _preview_drag({"op":"update_entity","entity_id":selected_id,"patch":{"ground_xy":snapped.ground_xy}})
			_last_drag_error="" if result.ok else str(result.error)
			if not result.ok: reported.emit(result.error)
			queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed and not preview_only:
		if event.keycode == KEY_ESCAPE: cancel();accept_event()
		elif event.keycode==KEY_ENTER and (mode.begins_with("compound_") or mode in ["district_rectangle","district_polygon","district_hole"]):finish_w5();accept_event()
		elif event.keycode==KEY_BACKSPACE and (mode.begins_with("compound_") or mode in ["district_rectangle","district_polygon","district_hole"]):
			var points: Array=compound_points if mode.begins_with("compound_") else district_points
			if not points.is_empty():points.pop_back();queue_redraw()
			accept_event()
		elif event.keycode == KEY_ENTER and mode in ["terrain_rectangle","terrain_polygon","terrain_ramp"]:finish_terrain();accept_event()
		elif event.keycode == KEY_BACKSPACE and mode in ["terrain_rectangle","terrain_polygon","terrain_ramp"]:
			if not terrain_points.is_empty():terrain_points.pop_back();queue_redraw()
			accept_event()
		elif event.keycode == KEY_ENTER and mode in ["plot_draw","plot_hole"]:finish_plot();accept_event()
		elif event.keycode == KEY_BACKSPACE and mode in ["plot_draw","plot_hole"]:
			if not plot_points.is_empty():plot_points.pop_back();queue_redraw()
			accept_event()
		elif event.keycode == KEY_ENTER and mode=="path_draw": finish_path();accept_event()
		elif event.keycode == KEY_BACKSPACE and mode=="path_draw":
			if not path_points.is_empty(): path_points.pop_back();queue_redraw()
			accept_event()
		elif event.keycode == KEY_DELETE and not selected_id.is_empty():
			var result: Dictionary = session.dispatch({"op":"delete_entity","entity_id":selected_id})
			if not result.ok: reported.emit(result.error)
			accept_event()

func paths_recipe() -> Dictionary:
	for recipe in session.view().recipes:
		if recipe.kind=="path" and recipe.recipe_id==selected_recipe_id: return recipe
	return {}

func has_pending_input() -> bool:
	return edit_pending or _dragging or _point_dragging or session.has_preview() or session.job_in_progress() or not compound_points.is_empty() or not district_points.is_empty() or not terrain_points.is_empty() or not path_points.is_empty() or not plot_points.is_empty() or not brush_points.is_empty() or _brush_drawing

func _compound_target(p: Dictionary) -> Dictionary:
	for e in p.materialized_snapshot.entities:
		if e.entity_id==compound_target_id and e.kind=="compound":return e
	return {}
func finish_w5() -> void:
	var compound:=mode.begins_with("compound_");var points: Array=compound_points if compound else district_points
	if points.size()<(2 if compound or mode=="district_rectangle" else 3):reported.emit("两角需要2点，多边形需要至少3点。");return
	var tool:=mode;var result: Array=points.duplicate(true)
	if tool=="district_rectangle":result=PlotGeometry.shape("rectangle",result[0],result[1])
	if not compound:
		var issue:=PlotGeometry.validate(result,[])
		if not issue.is_empty():reported.emit(issue);return
	points.clear();mode="select"
	if compound:compound_drawn.emit(result,tool)
	else:district_drawn.emit(result,tool)
	queue_redraw()
func _draw_w5(p: Dictionary,drawer: CanvasItem) -> void:
	if show_district_lots:
		for lot in p.materialized_snapshot.get("lots",[]):
			var line:=PackedVector2Array();var color:=Color("8e7748") if lot.lot_role=="buildable" else Color("4f8c9c") if lot.lot_role=="future" else Color("b16d50")
			for q in lot.polygon:line.append(SurfaceProject.project_point(p,Terrain.vec(q),lot.surface_id))
			if line.size()>2:line.append(line[0]);drawer.draw_polyline(line,color,1.1/zoom)
			var entrance:=SurfaceProject.project_point(p,Terrain.vec(lot.entrance.ground_xy),lot.surface_id)
			drawer.draw_circle(entrance,2.5/zoom,color)
	for e in p.materialized_snapshot.entities:
		if e.kind!="compound" or e.entity_id!=selected_id:continue
		var line:=PackedVector2Array()
		for q in Compounds.footprint(e):line.append(SurfaceProject.project_point(p,q,e.surface_id))
		line.append(line[0]);drawer.draw_polyline(line,Color("d89024"),2/zoom)
		var entry:=Compounds.entrance(e)
		if not entry.is_empty():drawer.draw_circle(SurfaceProject.project_point(p,Terrain.vec(entry.ground_xy),e.surface_id),4/zoom,Color("429dc3"))
	for group in [compound_points,district_points]:
		if group.is_empty():continue
		var line:=PackedVector2Array();var target:=_compound_target(p)
		for point in group:
			var q:=Terrain.vec(point);var support:=active_surface_id
			if group==compound_points and mode in ["compound_room","compound_hole"] and not target.is_empty():q=Compounds.world(target,q);support=target.surface_id
			line.append(SurfaceProject.project_point(p,q,support))
		for q in line:drawer.draw_circle(q,4/zoom,Color("dca441"))
		if line.size()>1:drawer.draw_polyline(line,Color("dca441"),2/zoom)

func _append_brush_point(world: Vector2) -> void:
	var point:=SurfaceProject.ground_point(session.view(),world,_brush_surface_id)
	var extent: Array=session.view().legacy_document.canvas_size
	point=point.clamp(Vector2.ZERO,Vector2(extent[0],extent[1]))
	brush_points=Brush.normalize(brush_points+[[point.x,point.y]])
	if brush_points.size()>256:_brush_overflow=true;brush_points.pop_back();reported.emit("笔迹超过256个转折点，松开后整笔取消。")
func finish_plot() -> void:
	if plot_points.size()<3 and (plot_shape=="polygon" or mode=="plot_hole"):reported.emit("多边形／洞至少3点。");return
	if plot_points.size()<2:reported.emit("请先指定两角。");return
	var outer: Array=plot_points.duplicate(true) if plot_shape=="polygon" or mode=="plot_hole" else PlotGeometry.shape(plot_shape,plot_points[0],plot_points[1])
	var issue:=PlotGeometry.validate(outer,[])
	if not issue.is_empty():reported.emit(issue);return
	var hole: bool=mode=="plot_hole"
	plot_points.clear();mode="select";plot_drawn.emit(outer,plot_shape,hole);queue_redraw()
func _draw_plots(p: Dictionary,drawer: CanvasItem) -> void:
	for recipe in p.recipes:
		if recipe.kind!="plot" or not show_plot_boundaries:continue
		var color:=Color("687d4c") if recipe.plot_type!="clearance" else Color("b55d46")
		if recipe.recipe_id==selected_plot_id:color=Color("ca8e2c")
		for ring in [recipe.outer]+recipe.holes:
			var line:=PackedVector2Array()
			for point in ring:line.append(SurfaceProject.project_point(p,Vector2(point[0],point[1]),recipe.surface_id))
			if not line.is_empty():line.append(line[0]);drawer.draw_polyline(line,color,1.5/zoom)
	if not plot_points.is_empty():
		var line:=PackedVector2Array()
		for point in plot_points:line.append(SurfaceProject.project_point(p,Vector2(point[0],point[1]),active_surface_id))
		for point in line:drawer.draw_circle(point,4/zoom,Color("dca441"))
		if line.size()>1:drawer.draw_polyline(line,Color("dca441"),2/zoom)
	if not brush_points.is_empty():
		var line:=PackedVector2Array()
		for point in brush_points:line.append(SurfaceProject.project_point(p,Vector2(point[0],point[1]),active_surface_id))
		var tint:=Color(0.72,0.25,0.18,0.3) if brush_template.get("brush_mode")=="erase" else Color(0.3,0.5,0.3,0.3)
		for point in line:drawer.draw_circle(point,float(brush_template.get("radius",90)),tint)
		if line.size()>1:drawer.draw_polyline(line,tint,float(brush_template.get("radius",90))*2)

func finish_path() -> void:
	if path_points.size()<2: reported.emit("路径至少需要两个控制点。 ");return
	var id:=Model.new_id("path")
	var points: Array=[]
	var segments: Array=[]
	for i in range(path_points.size()):
		points.append({"point_id":Model.new_id("point"),"ground_xy":path_points[i].duplicate(),"width":path_width})
		if i>0: segments.append({"segment_id":Model.new_id("segment"),"from":points[i-1].point_id,"to":points[i].point_id})
	var recipe: Dictionary={"recipe_id":id,"kind":"path","path_type":path_type,"name":{"road":"道路","wall":"城墙","river":"河流"}[path_type],"control_points":points,"segments":segments,"seed":path_seed,"surface_id":active_surface_id,"style":"water" if path_type=="river" else path_style,"roles":[],"wall_asset_ref":path_wall_ref,"roadside":{},"source_feature_id":""}
	var result: Dictionary=session.dispatch({"op":"add_recipe","recipe":recipe})
	if not result.ok: reported.emit(result.error);return
	path_points.clear();selected_recipe_id=id;selected_point_id=points[0].point_id;mode="path_edit";recipe_selected.emit(id,selected_point_id);queue_redraw()

func _draw_terrain(entry: Dictionary,drawer: CanvasItem) -> void:
	var ink:=Color("574e38")
	for mesh in entry.parts:
		var polygon: PackedVector2Array=mesh.polygon
		if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty():continue
		if mesh.has("colors"):drawer.draw_polygon(polygon,mesh.colors)
		else:drawer.draw_colored_polygon(polygon,Color(mesh.color))
		if mesh.style=="slope":drawer.draw_line(polygon[0],polygon[1],ink,1.05,true)
		elif mesh.style!="join":
			var line:=polygon.duplicate();line.append(line[0]);drawer.draw_polyline(line,ink,1.05,true)
		if mesh.style in ["cliff","slope","bank"] and polygon.size()==4:
			var count:=maxi(2,int(polygon[0].distance_to(polygon[1])/13))
			for i in range(1,count):
				var t: float=(float(i)+fposmod(sin(i*21.43+polygon[0].x)*10.3,0.75)-0.375)/count
				var a:=polygon[0].lerp(polygon[1],t);var b:=polygon[3].lerp(polygon[2],t)
				var tangent: Vector2=(polygon[1]-polygon[0]).normalized()*a.distance_to(b)*tan(deg_to_rad(float(mesh.get("direction",0))))*0.5
				a-=tangent;b+=tangent
				var token: float=fposmod(sin(i*47.17+polygon[0].x)*136.21,1)
				for clipped in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a.lerp(b,0.12+token*0.12),a.lerp(b,0.7+token*0.21)]),polygon):drawer.draw_polyline(clipped,Color("88734e"),0.7,true)
				if mesh.style=="cliff":drawer.draw_line(a.lerp(b,0.48)+Vector2(-2,1),a.lerp(b,0.5)+Vector2(3,-1),Color("88734e"),0.65)
		elif mesh.style=="top":
			# Sparse deterministic ground strokes, subordinate to editable outline geometry.
			var box:=Plan.bounds(polygon)
			for y in range(int(box.position.y/23)*23,int(box.end.y),23):
				for x in range(int(box.position.x/29)*29,int(box.end.x),29):
					var q:=Vector2(x+fposmod(sin(y+x*2.3)*12.3,9),y)
					if Geometry2D.is_point_in_polygon(q,polygon) and Geometry2D.is_point_in_polygon(q+Vector2(3,1),polygon):drawer.draw_line(q,q+Vector2(3,1),Color("ada575"),0.7)

func place_entity(entity: Dictionary) -> void:
	var result: Dictionary=session.dispatch({"op":"add_manual","entity":entity})
	if result.ok:selected_id=entity.entity_id;selected.emit(selected_id)
	else:reported.emit(result.error)
	queue_redraw()
func finish_terrain() -> void:
	if terrain_points.size()<(3 if mode=="terrain_polygon" else 2):reported.emit("轮廓点不足。");return
	var points: Array=terrain_points.duplicate(true)
	if mode=="terrain_rectangle":points=PlotGeometry.shape("rectangle",points[0],points[1])
	var tool:=mode;terrain_points.clear();mode="select";terrain_drawn.emit(points,tool);queue_redraw()

func _draw_editor_overlays(p: Dictionary,drawer: CanvasItem) -> void:
	if render_only and not export_overlay:return
	preload("editor_overlays.gd").draw(p,drawer,zoom,not render_only or export_include_grid,not render_only or export_include_legend)

## Transient input owns only a small command; authority/revision/history stay put.
func _preview_drag(command: Dictionary) -> Dictionary:
	_transient_command=command
	_transient_layer.queue_redraw()
	return {"ok":true}
func _commit_drag() -> Dictionary:
	var command:=_transient_command
	_transient_command={};_transient_layer.queue_redraw()
	if command.is_empty():return {"ok":true,"changed":false}
	if command.op=="update_entity":
		var xy: Array=command.patch.ground_xy
		var snapped: Dictionary=preload("../snap_resolver.gd").drag(session.view(),_drag_entity,Vector2(xy[0],xy[1]),zoom)
		command.patch.ground_xy=snapped.ground_xy
	var result: Dictionary=session.start_edit_job(command)
	if result.ok:edit_pending=true;_transient_command=command;reported.emit("正在完整验证拖动，可按Esc取消。")
	return result # Same full transaction runs off the input thread, guarded by revision.
func paint_transient(drawer: CanvasItem) -> void:
	if _transient_command.is_empty():return
	drawer.draw_set_transform(pan,0,Vector2.ONE*zoom)
	var p: Dictionary=session.view()
	if _transient_command.op=="update_entity":
		var e:=_drag_entity.duplicate(true);e.ground_xy=_transient_command.patch.ground_xy
		var line:=PackedVector2Array()
		for q in EntityGeometry.footprint(p,e):line.append(SurfaceProject.project_point(p,q,e.surface_id,e.local_height))
		if line.size()>2:line.append(line[0]);drawer.draw_polyline(line,Color("f4bf59"),2/zoom)
		var info:=EntityGeometry.resolved(p,e)
		if not info.is_empty():
			var a: Dictionary=info.descriptor;var tex:=texture_for(a)
			var unit: float=a.nominal_size_units[0]/float(a.region_px[2])*e.scale
			var pos:=SurfaceProject.project_point(p,Vector2(e.ground_xy[0],e.ground_xy[1]),e.surface_id,e.local_height)
			drawer.draw_set_transform(pan+pos*zoom,info.rotation,Vector2.ONE*zoom)
			if tex!=null:drawer.draw_texture_rect_region(tex,Rect2(-Vector2(a.anchor_px[0],a.anchor_px[1])*unit,Vector2(a.region_px[2],a.region_px[3])*unit),Rect2(a.region_px[0],a.region_px[1],a.region_px[2],a.region_px[3]),Color(1,1,1,0.65))
	else:
		var recipe:=paths_recipe();var line:=PackedVector2Array()
		for point in recipe.control_points:
			var xy: Array=_transient_command.patch.ground_xy if point.point_id==selected_point_id else point.ground_xy
			line.append(SurfaceProject.project_point(p,Vector2(xy[0],xy[1]),recipe.surface_id))
		if line.size()>1:drawer.draw_polyline(line,Color("f4bf59"),3/zoom)
	drawer.draw_set_transform(Vector2.ZERO)
	drawer.draw_string(ThemeDB.fallback_font,Vector2(12,26),"临时位置 · 松开后完整验证",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f4bf59"))
