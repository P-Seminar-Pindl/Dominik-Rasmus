# placement_manager.gd
# Standalone building placement for the mesh prototype.
# Owns the occupancy state; economy/production lives in the Global autoload.
extends Node3D

signal building_placed(anchor: Vector2i, resource: BuildingResource)
signal building_removed(anchor: Vector2i)
signal building_clicked(anchor: Vector2i)

const BUILDING_DIR := "res://data/buildings/"
const SLOPE_MAX    := 0.18  # max elev01 spread across footprint cells
const NO_TILE      := Vector2i(-99999, -99999)
const CLICK_MAX_DRAG := 8.0  # px of mouse travel before a click counts as a camera drag
const FIT_MARGIN   := 0.92  # fraction of the footprint the model may fill
const GRID_MARGIN  := 4     # tiles of grid drawn around the footprint while placing
const GRID_Y_OFFSET := 0.06

@onready var _world_gen:    Node3D        = get_node("../World")
@onready var _camera:       Camera3D      = get_node("../Camera3D")
@onready var _btn_container: VBoxContainer = $BuildingUI/Panel/Scroll/VBox
@onready var _status_label:  Label         = $BuildingUI/StatusLabel

var available_buildings: Array[BuildingResource] = []

var _selected_res:  BuildingResource = null
var _current_tile:  Vector2i         = Vector2i(-99999, -99999)
var _preview_inst:  Node3D           = null  # wrapper holding the scene instance
var _preview_ind:   MeshInstance3D   = null  # flat footprint indicator
var _indicator_mat: StandardMaterial3D
var _preview_valid: bool             = false
var _rotation:      int              = 0  # 0..3, 90° steps around Y
var _invalid_reason: String          = ""
var _grid_mesh:     MeshInstance3D   = null
var _grid_tile:     Vector2i         = NO_TILE
var _grid_rot:      int              = -1
var _lmb_press_pos: Vector2          = Vector2(-1, -1)
var _rmb_press_pos: Vector2          = Vector2(-1, -1)
var _buttons:       Dictionary       = {}  # BuildingResource → Button

var placed_buildings: Dictionary = {}  # Vector2i anchor → {resource, node, rotation, footprint}
var cell_to_anchor:   Dictionary = {}  # Vector2i cell   → Vector2i anchor


func _ready() -> void:
	_load_buildings()
	_build_ui()
	Global.register_placement_manager(self)


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
		btn.text = _button_text(res)
		btn.custom_minimum_size = Vector2(130, 26)
		btn.pressed.connect(_select_building.bind(res))
		_btn_container.add_child(btn)
		_buttons[res] = btn
	ResourceManager.resources_changed.connect(_refresh_button_states)
	_refresh_button_states()


func _button_text(res: BuildingResource) -> String:
	var parts := PackedStringArray()
	for cost in res.costs:
		parts.append("%s %d" % [cost.item, cost.amount])
	if parts.is_empty():
		return res.name
	return res.name + "\n" + "  ".join(parts)


func _refresh_button_states() -> void:
	for res in _buttons:
		_buttons[res].disabled = not ResourceManager.can_afford(res.costs)


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
	_preview_inst.add_child(_instantiate_fitted(res))
	_update_preview_orientation()

	# Terrain-conforming tile grid around the cursor
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.mesh = ImmediateMesh.new()
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.28)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_mesh.material_override = grid_mat
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_mesh)
	_grid_tile = NO_TILE
	_grid_rot = -1

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
	if is_instance_valid(_grid_mesh):
		_grid_mesh.queue_free()
	_preview_inst  = null
	_preview_ind   = null
	_grid_mesh     = null
	_indicator_mat = null


# ── Model fitting ─────────────────────────────────────────────────────────────
# The kenney models neither match their footprints nor share a common origin
# (some are oversized, off-center, or sunk below y=0), so every instance is
# uniformly scaled into its footprint, centered on X/Z, and grounded at Y=0.

func _instantiate_fitted(res: BuildingResource) -> Node3D:
	var inst: Node3D = res.scene.instantiate()
	_fit_to_footprint(inst, res.footprint_size)
	return inst


static func _fit_to_footprint(inst: Node3D, fp: Vector2i) -> void:
	var result := _merge_mesh_aabb(inst, inst.transform, AABB(), false)
	if not result[1]:
		return
	var aabb: AABB = result[0]
	if aabb.size.x < 0.001 or aabb.size.z < 0.001:
		return
	var s: float = minf(fp.x * FIT_MARGIN / aabb.size.x, fp.y * FIT_MARGIN / aabb.size.z)
	var center := aabb.get_center()
	var t := inst.transform
	t.basis = t.basis.scaled(Vector3(s, s, s))
	t.origin = t.origin * s - Vector3(center.x * s, aabb.position.y * s, center.z * s)
	inst.transform = t


# Merged AABB of all MeshInstance3D under `node`, expressed in the space
# `base` maps into. Returns [AABB, found_any: bool].
static func _merge_mesh_aabb(node: Node3D, base: Transform3D, aabb: AABB, has: bool) -> Array:
	if node is MeshInstance3D and node.mesh != null:
		var local: AABB = base * node.mesh.get_aabb()
		aabb = local if not has else aabb.merge(local)
		has = true
	for child in node.get_children():
		if child is Node3D:
			var r := _merge_mesh_aabb(child, base * child.transform, aabb, has)
			aabb = r[0]
			has = r[1]
	return [aabb, has]


# ── Per-frame preview update ──────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _selected_res == null or not is_instance_valid(_preview_inst):
		return

	var mouse_pos  := get_viewport().get_mouse_position()
	_current_tile   = _tile_under_cursor(mouse_pos)
	var fp := _footprint_for_rotation(_selected_res.footprint_size, _rotation)
	_preview_valid  = _can_place(_current_tile, fp, _selected_res)

	var h  = _world_gen.get_height_at(_current_tile)
	var center := Vector3(_current_tile.x + fp.x * 0.5, h, _current_tile.y + fp.y * 0.5)

	_preview_inst.position = center
	_preview_ind.position  = center + Vector3(0, 0.05, 0)
	_update_grid_overlay(_current_tile, fp)
	if _indicator_mat != null:
		_indicator_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.45) if _preview_valid \
				else Color(1.0, 0.25, 0.25, 0.5)
	if _preview_valid:
		_status_label.text = "Placing: " + _selected_res.name + "   [A/D] rotate   [RMB] cancel"
	else:
		_status_label.text = "Placing: " + _selected_res.name + " — " + _invalid_reason
	_update_preview_orientation()


func _input(event: InputEvent) -> void:
	if _selected_res != null and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A:
			_rotate_selection(-1)
		elif event.keycode == KEY_D:
			_rotate_selection(1)
		return

	if not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _selected_res != null:
			if event.pressed:
				if _preview_valid:
					_place_building(_current_tile, _selected_res)
				get_viewport().set_input_as_handled()  # always consume; prevents orbit drag
		elif event.pressed:
			_lmb_press_pos = event.position
		elif _lmb_press_pos != Vector2(-1, -1):
			# Click (not a camera drag) on a placed building → inspect it
			if event.position.distance_to(_lmb_press_pos) <= CLICK_MAX_DRAG:
				var anchor := _anchor_under_cursor(event.position)
				if anchor != NO_TILE:
					building_clicked.emit(anchor)
			_lmb_press_pos = Vector2(-1, -1)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _selected_res != null:
			if event.pressed:
				_select_building(null)
				get_viewport().set_input_as_handled()
		elif event.pressed:
			_rmb_press_pos = event.position
		elif _rmb_press_pos != Vector2(-1, -1):
			# Click (not a camera pan) on a placed building → demolish it
			if event.position.distance_to(_rmb_press_pos) <= CLICK_MAX_DRAG:
				var anchor := _anchor_under_cursor(event.position)
				if anchor != NO_TILE:
					remove_building(anchor)
			_rmb_press_pos = Vector2(-1, -1)


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


func _anchor_under_cursor(screen_pos: Vector2) -> Vector2i:
	var tile := _tile_under_cursor(screen_pos)
	return cell_to_anchor.get(tile, NO_TILE)


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


# ── Grid overlay ──────────────────────────────────────────────────────────────
# Tile grid lines conforming to the terrain, drawn around the footprint while
# a building is selected. Rebuilt only when the cursor tile or rotation changes.

func _update_grid_overlay(anchor: Vector2i, fp: Vector2i) -> void:
	if not is_instance_valid(_grid_mesh):
		return
	if _grid_tile == anchor and _grid_rot == _rotation:
		return
	_grid_tile = anchor
	_grid_rot = _rotation

	var x0 := anchor.x - GRID_MARGIN
	var z0 := anchor.y - GRID_MARGIN
	var nx := fp.x + GRID_MARGIN * 2
	var nz := fp.y + GRID_MARGIN * 2

	# Sample heights once per grid corner
	var heights: PackedFloat32Array = []
	heights.resize((nx + 1) * (nz + 1))
	for ix in nx + 1:
		for iz in nz + 1:
			heights[ix * (nz + 1) + iz] = _world_gen.get_height_at(Vector2i(x0 + ix, z0 + iz)) + GRID_Y_OFFSET

	var im := _grid_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for ix in nx + 1:
		for iz in nz:
			im.surface_add_vertex(Vector3(x0 + ix, heights[ix * (nz + 1) + iz], z0 + iz))
			im.surface_add_vertex(Vector3(x0 + ix, heights[ix * (nz + 1) + iz + 1], z0 + iz + 1))
	for iz in nz + 1:
		for ix in nx:
			im.surface_add_vertex(Vector3(x0 + ix, heights[ix * (nz + 1) + iz], z0 + iz))
			im.surface_add_vertex(Vector3(x0 + ix + 1, heights[(ix + 1) * (nz + 1) + iz], z0 + iz))
	im.surface_end()


# ── Placement validation ──────────────────────────────────────────────────────

func _can_place(anchor: Vector2i, fp: Vector2i, res: BuildingResource) -> bool:
	_invalid_reason = ""
	if res != null and not ResourceManager.can_afford(res.costs):
		_invalid_reason = "Not enough resources"
		return false
	var elev_lo := INF
	var elev_hi := -INF
	for dx in range(fp.x):
		for dz in range(fp.y):
			var cell := anchor + Vector2i(dx, dz)
			if cell_to_anchor.has(cell):
				_invalid_reason = "Space occupied"
				return false
			var e = _world_gen.get_elev01_at(cell)
			if e < _world_gen.cfg.threshold_ocean:
				_invalid_reason = "Invalid terrain"
				return false
			if _world_gen.river_tile_set.has(cell):
				_invalid_reason = "Invalid terrain"
				return false
			if res != null and not res.allowed_tiles.is_empty() \
					and not (_world_gen.get_tile_name_at(cell) in res.allowed_tiles):
				_invalid_reason = "Needs: " + ", ".join(res.allowed_tiles)
				return false
			elev_lo = minf(elev_lo, e)
			elev_hi = maxf(elev_hi, e)
	if (elev_hi - elev_lo) > SLOPE_MAX:
		_invalid_reason = "Too steep"
		return false
	if res != null and not res.required_adjacent_tiles.is_empty():
		var found := false
		for cell in _border_cells(anchor, fp):
			if _world_gen.get_tile_name_at(cell) in res.required_adjacent_tiles:
				found = true
				break
		if not found:
			_invalid_reason = "Must border: " + ", ".join(res.required_adjacent_tiles)
			return false
	return true


# Cells in the one-tile ring around the footprint (4-neighborhood edges).
func _border_cells(anchor: Vector2i, fp: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(fp.x):
		cells.append(anchor + Vector2i(dx, -1))
		cells.append(anchor + Vector2i(dx, fp.y))
	for dz in range(fp.y):
		cells.append(anchor + Vector2i(-1, dz))
		cells.append(anchor + Vector2i(fp.x, dz))
	return cells


# ── Placement ─────────────────────────────────────────────────────────────────

func _place_building(anchor: Vector2i, res: BuildingResource) -> void:
	var fp := _footprint_for_rotation(res.footprint_size, _rotation)
	if not _can_place(anchor, fp, res):
		_status_label.text = "Cannot place " + res.name + ": " + _invalid_reason
		return

	ResourceManager.pay(res.costs)

	var h  = _world_gen.get_height_at(anchor)
	var wrapper := Node3D.new()
	wrapper.position = Vector3(anchor.x + fp.x * 0.5, h, anchor.y + fp.y * 0.5)
	wrapper.rotation_degrees = Vector3(0, _rotation * 90, 0)
	wrapper.add_child(_instantiate_fitted(res))
	add_child(wrapper)

	placed_buildings[anchor] = {"resource": res, "node": wrapper, "rotation": _rotation, "footprint": fp}
	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor[anchor + Vector2i(dx, dz)] = anchor

	building_placed.emit(anchor, res)


func remove_building(anchor: Vector2i) -> void:
	if not placed_buildings.has(anchor):
		return
	var data: Dictionary = placed_buildings[anchor]
	var res: BuildingResource = data["resource"]
	if is_instance_valid(data["node"]):
		data["node"].queue_free()
	var fp: Vector2i = data.get("footprint", res.footprint_size)
	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor.erase(anchor + Vector2i(dx, dz))
	placed_buildings.erase(anchor)
	ResourceManager.refund(res.costs, 0.5)
	_status_label.text = "Demolished " + res.name + " (50% refund)"
	building_removed.emit(anchor)
