# ProductionLine.gd
# Attached to the GridMap node in the scene.
# BuildingNetwork autoload delegates rebuild_network() here.
extends GridMap
class_name ProductionLine

const NEIGHBORS := [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

# Sentinel used as the "parent" of warehouse-border road cells during BFS.
const WAREHOUSE_SENTINEL := Vector3i(-32768, 0, 0)


func _ready() -> void:
	BuildingNetwork.register(self)
	rebuild_network()


func _process(_delta: float) -> void:
	_update_carriers()


# ── Network rebuild ────────────────────────────────────────────────────────────

## Call this after any building is placed or removed.
func rebuild_network() -> void:
	var road_indices    := _road_indices()
	var storage_indices := _storage_indices()

	# Despawn all active carriers; paths are about to change.
	for origin in Global.placed_buildings:
		var carrier := Global.placed_buildings[origin].get("carrier", null) as Node3D
		if is_instance_valid(carrier):
			carrier.queue_free()
		Global.placed_buildings[origin]["carrier"]            = null
		Global.placed_buildings[origin]["connected"]          = false
		Global.placed_buildings[origin]["warehouse_distance"] = -1
		Global.placed_buildings[origin]["warehouse_path"]     = []

		var res := Global.placed_buildings[origin].get("resource") as BuildingResource
		if res is RoadBuildingResource:
			var inactive_id: int = Global.placed_buildings[origin].get("grid_id", -1)
			set_cell_item(Global.cell_to_anchor.get(origin, origin), inactive_id)

	# BFS from warehouse borders.
	# visited   : road-cell → hop distance
	# parent_map: road-cell → parent road-cell (WAREHOUSE_SENTINEL for the first hop)
	var visited:    Dictionary = {}
	var parent_map: Dictionary = {}
	var queue: Array[Vector3i] = []

	for origin in Global.placed_buildings:
		var grid_id: int = Global.placed_buildings[origin].get("grid_id", -1)
		if grid_id in storage_indices:
			Global.placed_buildings[origin]["warehouse_distance"] = 0
			var fp: Vector2i = Global.placed_buildings[origin].get("footprint", Vector2i(1, 1))
			for cell: Vector3i in _footprint_border(origin, fp):
				if get_cell_item(cell) in road_indices and not visited.has(cell):
					visited[cell]    = 1
					parent_map[cell] = WAREHOUSE_SENTINEL
					queue.append(cell)

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		var dist: int = visited[current]
		for offset in NEIGHBORS:
			var neighbor: Vector3i = current + offset
			var item := get_cell_item(neighbor)
			if item in road_indices and not visited.has(neighbor):
				visited[neighbor]    = dist + 1
				parent_map[neighbor] = current
				queue.append(neighbor)
			elif Global.cell_to_anchor.has(neighbor):
				var anchor: Vector3i = Global.cell_to_anchor[neighbor]
				Global.placed_buildings[anchor]["connected"] = true
				var cur: int = Global.placed_buildings[anchor].get("warehouse_distance", -1)
				if cur < 0 or dist < cur:
					Global.placed_buildings[anchor]["warehouse_distance"] = dist

	# Build warehouse→building paths for every connected production building.
	for origin in Global.placed_buildings:
		var res := Global.placed_buildings[origin].get("resource") as BuildingResource
		if not res is ProductionBuildingResource:
			continue
		if Global.placed_buildings[origin].get("warehouse_distance", -1) < 0:
			continue

		var fp: Vector2i = Global.placed_buildings[origin].get("footprint", Vector2i(1, 1))

		# Find the adjacent road cell with the lowest distance (entry point).
		var entry_cell := WAREHOUSE_SENTINEL
		var best_dist  := 999999
		for cell: Vector3i in _footprint_border(origin, fp):
			if visited.has(cell) and visited[cell] < best_dist:
				best_dist  = visited[cell]
				entry_cell = cell

		if entry_cell == WAREHOUSE_SENTINEL:
			continue

		# Backtrack from entry_cell to the warehouse border via parent_map.
		var path: Array[Vector3i] = []
		var cur := entry_cell
		while parent_map.has(cur) and cur != WAREHOUSE_SENTINEL:
			path.append(cur)
			var p: Vector3i = parent_map[cur]
			if p == WAREHOUSE_SENTINEL:
				break
			cur = p
		path.reverse()            # now: warehouse-side → building-side
		path.append(origin)       # building anchor as final waypoint
		Global.placed_buildings[origin]["warehouse_path"] = path

	# Swap visited roads to their active variant.
	for cell: Vector3i in visited:
		if not Global.cell_to_anchor.has(cell):
			continue
		var anchor: Vector3i = Global.cell_to_anchor[cell]
		var res := Global.placed_buildings[anchor].get("resource") as BuildingResource
		if res == null or res.active_variant == "":
			continue
		var active_entry: Dictionary = LibraryManager.buildings.get(res.active_variant, {})
		if active_entry.is_empty():
			continue
		set_cell_item(cell, active_entry["index"])


# ── Carrier management ─────────────────────────────────────────────────────────

func _update_carriers() -> void:
	for origin in Global.placed_buildings.keys():
		var data: Dictionary = Global.placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue

		var state:    String  = data.get("logistics_state", "idle")
		var dist:     int     = data.get("warehouse_distance", -1)
		var path:     Array   = data.get("warehouse_path", [])
		var carrier:  Node3D  = data.get("carrier", null) as Node3D
		var progress: float   = data.get("logistics_progress", 0.0)

		var needs_carrier := (state == "fetching" or state == "delivering") \
				and dist > 0 and not path.is_empty()

		if needs_carrier:
			if not is_instance_valid(carrier):
				carrier = _spawn_carrier()
				data["carrier"] = carrier

			# t goes 0→1 as the carrier completes its trip.
			var t := clampf(progress / float(dist), 0.0, 1.0)
			# fetching  : warehouse → building  (path forward)
			# delivering: building  → warehouse (path reversed)
			var path_t := t if state == "fetching" else (1.0 - t)
			carrier.position = _path_position(path, path_t)
		else:
			if is_instance_valid(carrier):
				carrier.queue_free()
			data["carrier"] = null


func _spawn_carrier() -> Node3D:
	var node  := MeshInstance3D.new()
	var mesh  := BoxMesh.new()
	mesh.size  = Vector3(0.4, 0.8, 0.4)
	node.mesh  = mesh
	var mat   := StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.85, 0.1)   # bright yellow
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	add_child(node)
	return node


## Linearly interpolates a world position along the stored road path.
## t = 0 is the warehouse end; t = 1 is the building end.
func _path_position(path: Array, t: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1:
		return _cell_world(path[0])
	var scaled := t * (path.size() - 1)
	var idx    := clampi(int(scaled), 0, path.size() - 2)
	var frac   := scaled - float(idx)
	return _cell_world(path[idx]).lerp(_cell_world(path[idx + 1]), frac)


## Centre of a grid cell, raised slightly so the carrier sits above the road.
func _cell_world(cell: Vector3i) -> Vector3:
	return map_to_local(cell) + Vector3(0, 0.8, 0)


# ── Index helpers ──────────────────────────────────────────────────────────────

## Returns all GridMap item indices whose BuildingResource is (or extends) the given class.
func _road_indices() -> Array[int]:
	var result: Array[int] = []
	for entry in LibraryManager.buildings.values():
		if entry["resource"] is RoadBuildingResource:
			result.append(entry["index"])
	return result

func _storage_indices() -> Array[int]:
	var result: Array[int] = []
	for entry in LibraryManager.buildings.values():
		if entry["resource"] is StorageBuildingResource:
			result.append(entry["index"])
	return result


## Returns all cells on the outer border of a footprint (for seeding BFS from a storage hub).
func _footprint_border(origin: Vector3i, fp: Vector2i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dx in range(fp.x):
		for dz in range(fp.y):
			var cell := origin + Vector3i(dx, 0, dz)
			for offset in NEIGHBORS:
				var neighbor = cell + offset
				# Only include neighbours outside the footprint itself
				if not Global.cell_to_anchor.has(neighbor) \
						or Global.cell_to_anchor[neighbor] != origin:
					cells.append(neighbor)
	return cells
