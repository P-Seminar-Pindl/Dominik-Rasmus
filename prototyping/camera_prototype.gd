extends Camera3D

const _DefaultInfoPanel = preload("res://prototyping/ui/default_info_panel.gd")
const _sidebar_scene := preload("res://prototyping/ui/BuildingSidebar.tscn")
const _BuildingSidebar = preload("res://prototyping/ui/building_sidebar.gd")
const _ResourceDisplay = preload("res://prototyping/ui/resource_display.gd")

@onready var grid: GridMap = $".."
@export var SensitivityMulti: float = 1.0
const RAY_LENGTH = 10000.0
const CELL_SIZE := Vector3(2.0, 2.0, 2.0)

var anchor = Vector3.ZERO
var dragging = false
var right_dragging = false

var target_distance := 10.0
var zoom_speed = 0.1
var zoom_min = 2.0
var zoom_max = 1000.0

var orbit_sensitivity = 0.005
var yaw := 0.0
var pitch := 0.0
var distance := 10.0

# Ghost placement preview
var _ghost: MeshInstance3D = null
var _ghost_mesh: BoxMesh = null
var _ghost_mat: StandardMaterial3D = null
var _ghost_grid_pos: Vector3i = Vector3i(-99999, -99999, -99999)
var _last_selected_building: String = ""

# Info panel
var _canvas_layer: CanvasLayer = null
var _active_panel: _DefaultInfoPanel = null
var _default_panel_scene := preload("res://prototyping/ui/DefaultInfoPanel.tscn")


func _ready() -> void:
	var offset = global_position - anchor
	distance = offset.length()
	yaw = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)

	_build_ghost()

	_canvas_layer = CanvasLayer.new()
	get_parent().add_child.call_deferred(_canvas_layer)

	# Load buildings into LibraryManager if not already done
	# LibraryManager doesn't need to be in the scene tree — just call it directly.
	if LibraryManager.buildings.is_empty():
		var lm := LibraryManager.new()
		lm.populate_buildings_from_folder(grid, "res://data/buildings/")

	# Building selection sidebar — added to canvas layer before it enters the tree;
	# sidebar._ready() fires once the canvas layer is added (deferred above).
	var sidebar := _sidebar_scene.instantiate() as _BuildingSidebar
	_canvas_layer.add_child(sidebar)

	# Resource HUD — top-right corner.
	var res_display := _ResourceDisplay.new()
	_canvas_layer.add_child(res_display)


# ── Ghost ─────────────────────────────────────────────────────────────────────

func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost_mesh = BoxMesh.new()
	_ghost_mesh.size = CELL_SIZE
	_ghost.mesh = _ghost_mesh
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.3)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.flags_do_not_receive_shadows = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	get_parent().add_child.call_deferred(_ghost)


func _refresh_ghost_size() -> void:
	var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
	if entry.is_empty():
		return
	var fp: Vector2i = (entry["resource"] as BuildingResource).footprint_size
	_ghost_mesh.size = Vector3(fp.x * CELL_SIZE.x, CELL_SIZE.y, fp.y * CELL_SIZE.z)


func _update_ghost(origin: Vector3i) -> void:
	if origin == _ghost_grid_pos:
		return
	_ghost_grid_pos = origin
	var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
	var fp := Vector2i(1, 1)
	if not entry.is_empty():
		fp = (entry["resource"] as BuildingResource).footprint_size
	# Centre the ghost on the footprint
	_ghost.global_position = Vector3(
		(origin.x + (fp.x - 1) * 0.5) * CELL_SIZE.x + CELL_SIZE.x * 0.5,
		origin.y * CELL_SIZE.y + CELL_SIZE.y * 0.5,
		(origin.z + (fp.y - 1) * 0.5) * CELL_SIZE.z + CELL_SIZE.z * 0.5,
	)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	distance = lerp(distance, target_distance, delta * 10)
	_update_camera()
	_update_ghost_cursor()

	# Refresh ghost mesh size when selected building changes
	if Global.selected_building != _last_selected_building:
		_last_selected_building = Global.selected_building
		_refresh_ghost_size()


func _update_ghost_cursor() -> void:
	if Global.selected_building == "":
		_ghost.visible = false
		return
	var hit: Dictionary = _raycast_grid(get_viewport().get_mouse_position())
	if hit.is_empty():
		_ghost.visible = false
	else:
		_ghost.visible = true
		var origin := _cell_above(hit)
		_update_ghost(origin)
		# Tint red if blocked, blue if clear
		var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
		var fp := Vector2i(1, 1)
		if not entry.is_empty():
			fp = (entry["resource"] as BuildingResource).footprint_size
		if _can_place(origin, fp):
			_ghost_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.3)
		else:
			_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.4)


# ── Camera ────────────────────────────────────────────────────────────────────

func _update_camera() -> void:
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)
	global_position = anchor + Vector3(x, y, z)
	look_at(anchor)


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

func _input(event: InputEvent) -> void:
	# Left click — place or inspect
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not dragging:
		var hit: Dictionary = _raycast_grid(event.position)
		if not hit.is_empty():
			var cell := _cell_above(hit)
			if Global.selected_building != "":
				_place_at(cell)
			else:
				_inspect_at(cell)
		elif Global.selected_building != "":
			# Fallback: place on ground plane
			var pt = Plane(Vector3.UP, 0.0).intersects_ray(
				project_ray_origin(event.position),
				project_ray_normal(event.position)
			)
			if pt:
				_place_at(grid.local_to_map(pt))

	# Scroll zoom
	if event is InputEventMouseButton and event.pressed:
		var zoom_dir := 0
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

	# Orbit (middle drag)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed

	# Pan (right drag)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		right_dragging = event.pressed

	if event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.relative
		yaw   -= delta.x * orbit_sensitivity
		pitch += delta.y * orbit_sensitivity
		pitch = clamp(pitch, deg_to_rad(3), deg_to_rad(89))
		var x = distance * cos(pitch) * sin(yaw)
		var y = distance * sin(pitch)
		var z = distance * cos(pitch) * cos(yaw)
		global_position = anchor + Vector3(x, y, z)
		look_at(anchor)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and right_dragging:
		var delta: Vector2 = event.relative
		var right := global_transform.basis.x
		var forward := -global_transform.basis.z
		right.y = 0
		forward.y = 0
		right = right.normalized()
		forward = forward.normalized()
		var sensitivity := global_position.distance_to(anchor) * SensitivityMulti / 1000.0
		var move: Vector3 = (right * -delta.x + forward * delta.y) * sensitivity
		global_position += move
		anchor += move


# ── Footprint helpers ─────────────────────────────────────────────────────────

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


# ── Placement ─────────────────────────────────────────────────────────────────

func _place_at(origin: Vector3i) -> void:
	if Global.selected_building == "":
		return
	var entry: Dictionary = LibraryManager.buildings.get(Global.selected_building, {})
	if entry.is_empty():
		return
	var res := entry["resource"] as BuildingResource
	if not _can_place(origin, res.footprint_size):
		return
	# Check the player can afford the build cost.
	for cost in res.costs:
		if not ResourceManager.has_enough(cost.item, cost.amount):
			print("Cannot afford %s: need %d %s" % [res.name, cost.amount, cost.item])
			return
	# Deduct costs.
	for cost in res.costs:
		ResourceManager.remove(cost.item, cost.amount)
	# Place mesh at anchor cell only; occupancy covers all footprint cells
	grid.set_cell_item(origin, entry["index"])
	Global.place_building(origin, Global.selected_building)
	print("building placed")
	await BuildingNetwork.rebuild_network()
	print("network recalced")

# ── Inspect ───────────────────────────────────────────────────────────────────

func _inspect_at(cell: Vector3i) -> void:
	var data: Dictionary = Global.get_building_at(cell)
	if data.is_empty():
		if _active_panel:
			_active_panel.hide()
		return

	var res := data.get("resource", null) as BuildingResource
	var panel_scene: PackedScene = res.info_panel if res and res.info_panel else _default_panel_scene

	# Swap panel if type changed
	if _active_panel == null or _active_panel.get_meta("panel_scene", null) != panel_scene:
		if _active_panel:
			_active_panel.queue_free()
		_active_panel = panel_scene.instantiate() as _DefaultInfoPanel
		_active_panel.set_meta("panel_scene", panel_scene)
		_canvas_layer.add_child(_active_panel)

	_active_panel.show_building(data)
	_active_panel.set_position(get_viewport().get_mouse_position() + Vector2(12.0, 12.0))
