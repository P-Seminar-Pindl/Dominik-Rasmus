extends Camera3D

const DefaultInfoPanelClass = preload("res://prototyping/production/ui/default_info_panel.gd")
const DEFAULT_INFO_PANEL_SCENE = preload("res://prototyping/production/ui/DefaultInfoPanel.tscn")
const ResourceDisplayClass = preload("res://prototyping/production/ui/resource_display.gd")

@onready var grid: GridMap = $"../GridMap"
@onready var ui_layer: CanvasLayer = $"../CanvasLayer"
@export var SensitivityMulti : float
@export var placement_debug: bool = true
const RAY_LENGTH = 10000.0
const CELL_SIZE := Vector3(2.0, 2.0, 2.0)

var anchor = Vector3.ZERO
var dragging = false
var right_dragging = false
var _last_chunk := Vector2i(999, 999)

var target_distance := 10.0
var zoom_speed = 0.1
var zoom_min = 2.0
var zoom_max = 1000.0

var orbit_sensitivity = 0.005
var yaw := 0.0
var pitch := 0.0
var distance := 10.0

var _ghost: MeshInstance3D = null
var _ghost_mesh: BoxMesh = null
var _ghost_mat: StandardMaterial3D = null
var _ghost_grid_pos: Vector3i = Vector3i(-99999, -99999, -99999)
var _debug_label: Label = null
var _last_selected_building: String = ""
var _active_panel: DefaultInfoPanelClass = null


func _ready() -> void:
	var offset = global_position - anchor
	distance = offset.length()

	yaw = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)

	_build_ghost()
	_build_debug_label()
	_ensure_resource_display()


func _build_debug_label() -> void:
	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 10)
	_debug_label.add_theme_font_size_override("font_size", 28)
	_debug_label.add_theme_color_override("font_color", Color.WHITE)
	_debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_debug_label.add_theme_constant_override("shadow_offset_x", 2)
	_debug_label.add_theme_constant_override("shadow_offset_y", 2)
	get_viewport().add_child(_debug_label)



# ── Ghost ─────────────────────────────────────────────────────────────────────

func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost_mesh = BoxMesh.new()
	_ghost_mesh.size = CELL_SIZE
	_ghost.mesh = _ghost_mesh
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.25)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.flags_do_not_receive_shadows = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	get_parent().add_child(_ghost)


func _update_ghost(grid_pos: Vector3i) -> void:
	if _ghost == null or not _ghost.is_inside_tree():
		return
	if grid_pos == _ghost_grid_pos:
		return
	_ghost_grid_pos = grid_pos
	_ghost.position = Vector3(
		(grid_pos.x) * CELL_SIZE.x + CELL_SIZE.x * 0.5,
		grid_pos.y * CELL_SIZE.y + CELL_SIZE.y * 0.5,
		(grid_pos.z) * CELL_SIZE.z + CELL_SIZE.z * 0.5,
	)


func _ensure_resource_display() -> void:
	if ui_layer == null:
		return
	if ui_layer.get_node_or_null("ResourceDisplay") != null:
		return
	var panel := ResourceDisplayClass.new()
	panel.name = "ResourceDisplay"
	ui_layer.add_child(panel)


func _refresh_ghost_size() -> void:
	var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
	if entry.is_empty():
		_ghost_mesh.size = CELL_SIZE
		return
	var fp: Vector2i = (entry["resource"] as BuildingResource).footprint_size
	_ghost_mesh.size = Vector3(fp.x * CELL_SIZE.x, CELL_SIZE.y, fp.y * CELL_SIZE.z)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	distance = lerp(distance, target_distance, delta * 10)
	_update_camera()
	_update_ghost_cursor()
	_update_chunks_if_moved()
	_update_debug_label()

	if Global.selected_building != _last_selected_building:
		_last_selected_building = Global.selected_building
		_refresh_ghost_size()


func _update_debug_label() -> void:
	var hit = _raycast_grid(get_viewport().get_mouse_position())
	if hit.is_empty():
		_debug_label.text = ""
		return
	var cell: Vector3i = hit["cell"]
	var item_id: int = grid.get_cell_item(cell)
	var tile_name: String = LibraryManager.tile_id_to_name.get(item_id, "?")
	_debug_label.text = "Biome: %s  (%d, %d, %d)" % [tile_name, cell.x, cell.y, cell.z]


func _update_ghost_cursor() -> void:
	if Global.selected_building == "":
		_ghost.visible = false
		return
	var hit = _raycast_grid(get_viewport().get_mouse_position())
	if hit.is_empty():
		_ghost.visible = false
	else:
		_ghost.visible = true
		var origin := _cell_above(hit)
		_update_ghost(origin)
		var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
		var fp := Vector2i(1, 1)
		if not entry.is_empty():
			fp = (entry["resource"] as BuildingResource).footprint_size
		if _can_place(origin, fp):
			_ghost_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.25)
		else:
			_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.4)

func _update_chunks_if_moved() -> void:
	# Convert world pos → tile pos
	var tile_anchor = Vector2(anchor.x / CELL_SIZE.x, anchor.z / CELL_SIZE.z)
	Global.anchor = tile_anchor
	WorldGen.stream_chunks(
		grid,
		Global.distribution_curve,
		tile_anchor,
)

func _frame_budget_usec() -> int:
	# Leave ~40% of the frame for rendering, physics, etc.
	var target_fps: float = Engine.max_fps if Engine.max_fps > 0 else 10
	var frame_usec: float = 1_000_000.0 / target_fps
	return int(frame_usec * 0.3)  # spend max 30% of frame on chunk loading
# ── Raycasting ────────────────────────────────────────────────────────────────

func _raycast_grid(screen_pos: Vector2) -> Dictionary:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		project_ray_origin(screen_pos),
		project_ray_origin(screen_pos) + project_ray_normal(screen_pos) * RAY_LENGTH
	)
	var result = space.intersect_ray(query)
	if result.is_empty():
		return {}
	var inside = result["position"] - result["normal"] * 0.1
	return {
		"cell":   grid.local_to_map(grid.to_local(inside)),
		"normal": result["normal"],
	}


func _cell_above(hit: Dictionary) -> Vector3i:
	var normal: Vector3 = hit["normal"]
	if normal.y > 0.5:
		return hit["cell"] + Vector3i(0, 1, 0)
	return hit["cell"] + Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))


# ── Input ─────────────────────────────────────────────────────────────────────
func _update_camera() -> void:
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)

	global_position = anchor + Vector3(x, y, z)
	look_at(anchor)
func _input(event: InputEvent) -> void:

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not dragging:
		if _is_pointer_over_blocking_ui():
			_debug_place("Click ignored: pointer over interactive UI")
			return
		var hit = _raycast_grid(event.position)
		if not hit.is_empty():
			if Global.selected_building == "":
				_debug_place("Inspect mode click")
				var hit_cell: Vector3i = hit["cell"]
				if Global.get_building_at(hit_cell).is_empty():
					_inspect_at(_cell_above(hit))
				else:
					_inspect_at(hit_cell)
			else:
				_debug_place("Place click on raycast cell %s" % [str(_cell_above(hit))])
				_place_at(_cell_above(hit))
		else:
			if Global.selected_building != "":
				_debug_place("Raycast missed, trying ground-plane fallback")
				var pt = Plane(Vector3.UP, 0.0).intersects_ray(
					project_ray_origin(event.position),
					project_ray_normal(event.position)
				)
				if pt:
					_place_at(grid.local_to_map(pt))
				else:
					_debug_place("Ground-plane fallback failed")

	if event is InputEventMouseButton and event.pressed:
		var zoom_dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = 1

		if zoom_dir != 0:
			target_distance = clamp(
			target_distance + target_distance * zoom_speed * zoom_dir,
			zoom_min, zoom_max
			)
			get_viewport().set_input_as_handled()
				

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		right_dragging = event.pressed

	if event is InputEventMouseMotion and dragging:
		var delta = event.relative

		yaw -= delta.x * orbit_sensitivity
		pitch += delta.y * orbit_sensitivity

		pitch = clamp(pitch, deg_to_rad(3), deg_to_rad(89))

		var x = distance * cos(pitch) * sin(yaw)
		var y = distance * sin(pitch)
		var z = distance * cos(pitch) * cos(yaw)

		global_position = anchor + Vector3(x, y, z)
		look_at(anchor)

		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and right_dragging:
		var delta = event.relative
		

		var right = global_transform.basis.x
		var forward = -global_transform.basis.z

		# remove vertical influence
		right.y = 0
		forward.y = 0

		right = right.normalized()
		forward = forward.normalized()
		var sensitivity = global_position.distance_to(anchor) * SensitivityMulti / 1000
		var move = (right * -delta.x + forward * delta.y) * sensitivity

		global_position += move
		anchor += move


func _footprint_cells(origin: Vector3i, fp: Vector2i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dx in range(fp.x):
		for dz in range(fp.y):
			cells.append(origin + Vector3i(dx, 0, dz))
	return cells


func _can_place(origin: Vector3i, fp: Vector2i) -> bool:
	for cell in _footprint_cells(origin, fp):
		if Global.is_cell_occupied(cell):
			return false
	return true


func _first_occupied_cell(origin: Vector3i, fp: Vector2i) -> Vector3i:
	for cell in _footprint_cells(origin, fp):
		if Global.is_cell_occupied(cell):
			return cell
	return Vector3i(-99999, -99999, -99999)


func _is_pointer_over_blocking_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false

	var current: Control = hovered
	while current != null:
		# The fullscreen post-process ColorRect is decorative and should not block world input.
		if current is ColorRect:
			current = current.get_parent() as Control
			continue
		if current is Button or current is ScrollContainer or current is Panel or current is PanelContainer:
			return true
		current = current.get_parent() as Control

	return false


func _debug_place(message: String) -> void:
	if placement_debug:
		print("[PlacementDebug] " + message)


func _inspect_at(cell: Vector3i) -> void:
	var data: Dictionary = Global.get_building_at(cell)
	if data.is_empty():
		if _active_panel:
			_active_panel.hide()
		return

	var res := data.get("resource", null) as BuildingResource
	var panel_scene: PackedScene = DEFAULT_INFO_PANEL_SCENE
	if res and res.info_panel:
		panel_scene = res.info_panel

	if _active_panel == null or _active_panel.get_meta("panel_scene", null) != panel_scene:
		if _active_panel:
			_active_panel.queue_free()
		_active_panel = panel_scene.instantiate() as DefaultInfoPanelClass
		_active_panel.set_meta("panel_scene", panel_scene)
		if ui_layer:
			ui_layer.add_child(_active_panel)
		else:
			get_viewport().add_child(_active_panel)

	_active_panel.show_building(data)
	_active_panel.position = get_viewport().get_mouse_position() + Vector2(12, 12)
# ── Placement ─────────────────────────────────────────────────────────────────

func _place_at(origin: Vector3i) -> void:
	if Global.selected_building == "":
		_debug_place("Place aborted: no selected building")
		return
	var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
	if entry.is_empty():
		_debug_place("Place aborted: building '%s' not found in LibraryManager.buildings" % Global.selected_building)
		return
	var res := entry["resource"] as BuildingResource
	if not _can_place(origin, res.footprint_size):
		var blocked := _first_occupied_cell(origin, res.footprint_size)
		_debug_place("Place blocked: footprint occupied at %s" % str(blocked))
		return

	for cost in res.costs:
		if not ResourceManager.has_enough(cost.item, cost.amount):
			_debug_place("Place blocked: missing %s (%d required, %d available)" % [cost.item, cost.amount, ResourceManager.get_amount(cost.item)])
			return

	for cost in res.costs:
		ResourceManager.remove(cost.item, cost.amount)

	grid.set_cell_item(origin, entry["index"])
	Global.place_building(origin, Global.selected_building)
	BuildingNetwork.rebuild_network()
	_debug_place("Placed '%s' at %s" % [Global.selected_building, str(origin)])
