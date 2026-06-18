# placement_manager.gd
# Standalone building placement for the mesh prototype.
# Owns its own occupancy state — no autoload dependencies.
extends Node3D

const BUILDING_DIR := "res://data/buildings/"
const SLOPE_MAX    := 0.18  # max elev01 spread across footprint cells

@onready var _world_gen:    Node3D        = get_node("../World")
@onready var _camera:       Camera3D      = get_node("../Camera3D")
@onready var _btn_container: VBoxContainer = $BuildingUI/Panel/VBox
@onready var _status_label:  Label         = $BuildingUI/StatusLabel

var available_buildings: Array[BuildingResource] = []

var _selected_res:  BuildingResource = null
var _current_tile:  Vector2i         = Vector2i(-99999, -99999)
var _preview_inst:  Node3D           = null  # wrapper holding the scene instance
var _preview_ind:   MeshInstance3D   = null  # flat footprint indicator
var _indicator_mat: StandardMaterial3D
var _preview_valid: bool             = false
var _rotation:      int              = 0  # 0..3, 90° steps around Y

var placed_buildings: Dictionary = {}  # Vector2i anchor → {resource, node}
var cell_to_anchor:   Dictionary = {}  # Vector2i cell   → Vector2i anchor


func _ready() -> void:
	_load_buildings()
	_build_ui()


# ── Asset loading ─────────────────────────────────────────────────────────────

func _load_buildings() -> void:
	var dir := DirAccess.open(BUILDING_DIR)
	if dir == null:
		push_error("PlacementManager: cannot open " + BUILDING_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with(".") and fname.ends_with(".tres"):
			var res := load(BUILDING_DIR + fname) as BuildingResource
			if res != null and res.show_in_sidebar and res.scene != null:
				available_buildings.append(res)
		fname = dir.get_next()


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	for res in available_buildings:
		var btn := Button.new()
		btn.text = res.name
		btn.custom_minimum_size = Vector2(130, 26)
		btn.pressed.connect(_select_building.bind(res))
		_btn_container.add_child(btn)


# ── Selection ─────────────────────────────────────────────────────────────────

func _select_building(res: BuildingResource) -> void:
	_selected_res = res
	_destroy_preview()
	_rotation = 0
	if res == null:
		_status_label.text = ""
		return
	_status_label.text = "Placing: " + res.name + "   [A/D] rotate   [RMB] cancel"

	# Scene preview wrapper
	_preview_inst = Node3D.new()
	add_child(_preview_inst)
	_preview_inst.add_child(res.scene.instantiate())
	_update_preview_orientation()

	# Flat footprint indicator (PlaneMesh shows valid/invalid area)
	var fp := _footprint_for_rotation(res.footprint_size, _rotation)
	var plane := PlaneMesh.new()
	plane.size = Vector2(fp.x, fp.y)
	_indicator_mat            = StandardMaterial3D.new()
	_indicator_mat.albedo_color    = Color(0.3, 1.0, 0.3, 0.45)
	_indicator_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_mat.no_depth_test   = true
	_preview_ind               = MeshInstance3D.new()
	_preview_ind.mesh          = plane
	_preview_ind.material_override = _indicator_mat
	add_child(_preview_ind)


func _destroy_preview() -> void:
	if is_instance_valid(_preview_inst):
		_preview_inst.queue_free()
	if is_instance_valid(_preview_ind):
		_preview_ind.queue_free()
	_preview_inst  = null
	_preview_ind   = null
	_indicator_mat = null


# ── Per-frame preview update ──────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _selected_res == null or not is_instance_valid(_preview_inst):
		return

	var mouse_pos  := get_viewport().get_mouse_position()
	_current_tile   = _tile_under_cursor(mouse_pos)
	_preview_valid  = _can_place(_current_tile, _footprint_for_rotation(_selected_res.footprint_size, _rotation))

	var fp := _footprint_for_rotation(_selected_res.footprint_size, _rotation)
	var h  = _world_gen.get_height_at(_current_tile)
	var center := Vector3(_current_tile.x + fp.x * 0.5, h, _current_tile.y + fp.y * 0.5)

	_preview_inst.position = center
	_preview_ind.position  = center + Vector3(0, 0.05, 0)
	_update_preview_orientation()
func _input(event: InputEvent) -> void:
	if _selected_res != null and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A:
			_rotate_selection(-1)
		elif event.keycode == KEY_D:
			_rotate_selection(1)
		return

	if not (event is InputEventMouseButton) or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_LEFT and _selected_res != null:
		if _preview_valid:
			_place_building(_current_tile, _selected_res)
		get_viewport().set_input_as_handled()  # always consume; prevents orbit drag

	elif event.button_index == MOUSE_BUTTON_RIGHT and _selected_res != null:
		_select_building(null)
		get_viewport().set_input_as_handled()


# ── Raycasting ────────────────────────────────────────────────────────────────

func _tile_under_cursor(screen_pos: Vector2) -> Vector2i:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir    := _camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.001:
		return Vector2i(-99999, -99999)
	# Step 1: project onto y=0 for approximate tile.
	var t0 := -ray_origin.y / ray_dir.y
	if t0 < 0.0:
		t0 = 0.0
	var hit0  := ray_origin + ray_dir * t0
	var tile0 := Vector2i(floori(hit0.x), floori(hit0.z))
	# Step 2: refine using actual terrain height at that tile.
	var h0 = _world_gen.get_height_at(tile0)
	var t1 = (h0 - ray_origin.y) / ray_dir.y
	if t1 <= 0.0:
		return tile0
	var hit1 = ray_origin + ray_dir * t1
	return Vector2i(floori(hit1.x), floori(hit1.z))


# ── Rotation helpers ──────────────────────────────────────────────────────────

func _footprint_for_rotation(fp: Vector2i, rotation: int) -> Vector2i:
	return fp if rotation % 2 == 0 else Vector2i(fp.y, fp.x)

func _rotate_selection(direction: int) -> void:
	_rotation = (_rotation + direction) % 4
	if _rotation < 0:
		_rotation += 4
	if _selected_res != null:
		_status_label.text = "Placing: " + _selected_res.name + "   [A/D] rotate   [RMB] cancel"
		_update_preview_orientation()
		if is_instance_valid(_preview_ind):
			var fp := _footprint_for_rotation(_selected_res.footprint_size, _rotation)
			_preview_ind.mesh.size = Vector2(fp.x, fp.y)

func _update_preview_orientation() -> void:
	if is_instance_valid(_preview_inst):
		_preview_inst.rotation_degrees = Vector3(0, _rotation * 90, 0)


# ── Placement validation ──────────────────────────────────────────────────────

func _can_place(anchor: Vector2i, fp: Vector2i) -> bool:
	var elev_lo := INF
	var elev_hi := -INF
	for dx in range(fp.x):
		for dz in range(fp.y):
			var cell := anchor + Vector2i(dx, dz)
			if cell_to_anchor.has(cell):
				return false
			var e = _world_gen.get_elev01_at(cell)
			if e < _world_gen.cfg.threshold_ocean:
				return false
			if _world_gen.river_tile_set.has(cell):
				return false
			elev_lo = minf(elev_lo, e)
			elev_hi = maxf(elev_hi, e)
	return (elev_hi - elev_lo) <= SLOPE_MAX

func _first_occupied_cell(anchor: Vector2i, fp: Vector2i) -> Vector2i:
	for dx in range(fp.x):
		for dz in range(fp.y):
			var cell := anchor + Vector2i(dx, dz)
			if cell_to_anchor.has(cell):
				return cell
	return Vector2i(-99999, -99999)


# ── Placement ─────────────────────────────────────────────────────────────────

func _place_building(anchor: Vector2i, res: BuildingResource) -> void:
	var fp := _footprint_for_rotation(res.footprint_size, _rotation)
	if not _can_place(anchor, fp):
		var collision := _first_occupied_cell(anchor, fp)
		if collision != Vector2i(-99999, -99999):
			_status_label.text = "Cannot place " + res.name + ": Space occupied"
		else:
			_status_label.text = "Cannot place " + res.name + ": Invalid terrain"
		return

	var h  = _world_gen.get_height_at(anchor)
	var wrapper := Node3D.new()
	wrapper.position = Vector3(anchor.x + fp.x * 0.5, h, anchor.y + fp.y * 0.5)
	wrapper.rotation_degrees = Vector3(0, _rotation * 90, 0)
	wrapper.add_child(res.scene.instantiate())
	add_child(wrapper)

	placed_buildings[anchor] = {"resource": res, "node": wrapper, "rotation": _rotation}
	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor[anchor + Vector2i(dx, dz)] = anchor
