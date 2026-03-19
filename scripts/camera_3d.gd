extends Camera3D

@onready var grid = $"../GridMap"
@onready var camera = $"."
const RAY_LENGTH = 1000.0
var Anchor = Vector3.ZERO
@onready var game_manager = get_tree().get_first_node_in_group("game_manager")

var dragging = false
var orbit_sensitivity = 0.005  # radians per pixel

var Buildings = LibraryManager.Buildings

func LookAtAnchor():
	camera.look_at(Anchor)

var zoom_speed = 0.1  # fraction of current distance per scroll tick
var zoom_min = 2.0    # minimum distance from anchor
var zoom_max = 100.0  # maximum distance from anchor

func _input(event):
	# --- Left click: place building ---
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var origin = project_ray_origin(event.position)
		var normal = project_ray_normal(event.position)
		var ground_plane = Plane(Vector3.UP, 0.0)
		var intersection = ground_plane.intersects_ray(origin, normal)
		if intersection:
			Anchor = intersection
			PlaceBuilding(grid.local_to_map(intersection))

	# --- Scroll wheel: zoom ---
	if event is InputEventMouseButton and event.pressed:
		var zoom_dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = -1  # scroll up = zoom in = move closer
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = 1   # scroll down = zoom out = move farther

		if zoom_dir != 0:
			var offset = camera.global_position - Anchor
			var current_dist = offset.length()
			var new_dist = clamp(current_dist + current_dist * zoom_speed * zoom_dir, zoom_min, zoom_max)
			camera.global_position = Anchor + offset.normalized() * new_dist
			get_viewport().set_input_as_handled()

	# --- Middle click: start/stop orbit drag ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed

	# --- Mouse motion: orbit around Anchor ---
	if event is InputEventMouseMotion and dragging:
		var delta = event.relative
		var yaw = Basis(Vector3.UP, -delta.x * orbit_sensitivity)
		var pitch = Basis(camera.global_transform.basis.x, -delta.y * orbit_sensitivity)
		var offset = camera.global_position - Anchor
		offset = yaw * pitch * offset
		camera.global_position = Anchor + offset
		camera.look_at(Anchor)
		get_viewport().set_input_as_handled()

func PlaceBuilding(position: Vector3):
	if Global.selected_building == null:
		return
	grid.set_cell_item(position, LibraryManager.Tiles.get(Global.selected_building))
