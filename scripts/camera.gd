extends Camera3D
@onready var grid: GridMap = $"../GridMap"
@onready var game_manager = get_tree().get_first_node_in_group("game_manager")
@export var SensitivityMulti : float
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
var _ghost_grid_pos: Vector3i = Vector3i(-99999, -99999, -99999)
var _debug_label: Label = null


func _ready() -> void:
	var offset = global_position - anchor
	distance = offset.length()

	yaw = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)

	_build_ghost()
	_build_debug_label()


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
	var mesh = BoxMesh.new()
	mesh.size = CELL_SIZE
	_ghost.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.flags_do_not_receive_shadows = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = mat
	_ghost.visible = false
	get_parent().add_child(_ghost)


func _update_ghost(grid_pos: Vector3i) -> void:
	if grid_pos == _ghost_grid_pos:
		return
	_ghost_grid_pos = grid_pos
	_ghost.global_position = Vector3(
		grid_pos.x * CELL_SIZE.x + CELL_SIZE.x * 0.5,
		grid_pos.y * CELL_SIZE.y + CELL_SIZE.y * 0.5,
		grid_pos.z * CELL_SIZE.z + CELL_SIZE.z * 0.5,
	)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	distance = lerp(distance, target_distance, delta * 10)
	_update_camera()
	_update_ghost_cursor()
	_update_chunks_if_moved()
	_update_debug_label()


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
		_update_ghost(_cell_above(hit))

func _update_chunks_if_moved() -> void:
	# Convert world pos → tile pos
	var tile_anchor = Vector2(anchor.x / CELL_SIZE.x, anchor.z / CELL_SIZE.z)
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
		var hit = _raycast_grid(event.position)
		if not hit.is_empty():
			_place_at(_cell_above(hit))
		else:
			var pt = Plane(Vector3.UP, 0.0).intersects_ray(
				project_ray_origin(event.position),
				project_ray_normal(event.position)
			)
			if pt:
				_place_at(grid.local_to_map(pt))

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
# ── Placement ─────────────────────────────────────────────────────────────────

func _place_at(grid_pos: Vector3i) -> void:
	if Global.selected_building == "":
		return
	var item: int = LibraryManager.buildings.get(Global.selected_building, {}).get("id", -1)
	if item == -1:
		item = LibraryManager.tiles.get(Global.selected_building, -1)
	if item == -1:
		return
	grid.set_cell_item(grid_pos, item)
	if LibraryManager.buildings.has(Global.selected_building):
		Global.place_building(grid_pos, Global.selected_building)
