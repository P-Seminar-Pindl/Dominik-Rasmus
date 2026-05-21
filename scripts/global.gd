extends Node

const NEIGHBORS := [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const WAREHOUSE_SENTINEL := Vector3i(-32768, 0, 0)

@export var height_modifier: int = 10
var selected_building: String = ""
var distribution_curve : Curve
var cell_size : Vector3
var chunk_render_distance : int = 32
var grid : GridMap
var anchor := Vector2.ZERO

# Tracks every placed building instance.
# Key: Vector3i (anchor/origin cell — top-left of footprint)
# Value: Dictionary with building data and runtime state
var placed_buildings: Dictionary = {}

# Maps every occupied footprint cell → its anchor cell
var cell_to_anchor: Dictionary = {}


func place_building(origin: Vector3i, building_id: String) -> void:
	var entry: Dictionary = LibraryManager.buildings.get(building_id, {})
	if entry.is_empty():
		push_error("Tried to place unknown building: " + building_id)
		return

	var res: BuildingResource = entry["resource"]
	var fp: Vector2i = res.footprint_size

	placed_buildings[origin] = {
		"id":                 building_id,
		"grid_id":            entry["index"],
		"resource":           res,
		"footprint":          fp,
		"productivity":       1.0,
		"population":         0,
		"storage":            {},      # local output buffer: { "Planks": 3 }
		"timer":              0.0,     # seconds into current production cycle
		"warehouse_distance": -1,      # road hops to nearest warehouse; -1 = disconnected
		"warehouse_path":     [],      # Array[Vector3i] road cells, warehouse-border → building
		"prod_state":         "idle",  # idle | producing
		"carrier_state":      "idle",  # idle | fetching | delivering
		"logistics_progress": 0.0,     # seconds of carrier travel completed this trip
		"carrier":            null,    # MeshInstance3D carrier node, or null
		"input_buffer":       {},      # inputs held at building: { "Logs": 2 }
		"carrier_cargo":      {},      # items on carrier: { "Logs": 2 }
	}

	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor[origin + Vector3i(dx, 0, dz)] = origin

	rebuild_network()


func remove_building(origin: Vector3i) -> void:
	var data: Dictionary = placed_buildings.get(origin, {})
	if data.is_empty():
		return
	var carrier := data.get("carrier", null) as Node3D
	if is_instance_valid(carrier):
		carrier.queue_free()
	var fp: Vector2i = data.get("footprint", Vector2i(1, 1))
	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor.erase(origin + Vector3i(dx, 0, dz))
	placed_buildings.erase(origin)
	rebuild_network()


func is_cell_occupied(cell: Vector3i) -> bool:
	return cell_to_anchor.has(cell)


# Returns the building dict for any cell in its footprint (not just the anchor).
func get_building_at(cell: Vector3i) -> Dictionary:
	if not cell_to_anchor.has(cell):
		return {}
	return placed_buildings.get(cell_to_anchor[cell], {})


# Anchor-cell lookup (kept for backwards compatibility).
func get_building(grid_pos: Vector3i) -> Dictionary:
	return placed_buildings.get(grid_pos, {})


# ── Production tick ───────────────────────────────────────────────────────────
#
# Each production building runs a 4-state machine:
#
#   idle  ──────────────────────────────────────────────────────►  producing
#           (no inputs)                                             (no inputs)
#
#   idle  ──► fetching (carrier travels dist hops) ──► producing ──► delivering
#           (has inputs; consumed upfront, in transit)              (carrier
#                                                                    returns)
#
# "dist" = warehouse_distance (road hops). Progress advances 1 unit/second,
# so dist = 5 means a 5-second carrier trip each way.

func _process(delta: float) -> void:
	for origin in placed_buildings.keys():
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue

		var prod := res as ProductionBuildingResource
		var dist: int = data.get("warehouse_distance", -1)

		# ── Carrier track (fetching / delivering) ────────────────────────────────

		if prod.input.is_empty():
			# No inputs — carrier only needed for delivery
			data["carrier_state"] = "idle"
		else:
			# Inputs needed — manage fetch cycle
			match data.get("carrier_state", "idle"):
				"idle":
					# Start fetching if input_buffer is below stockpile target and we can afford it
					if dist < 0:
						continue  # can't fetch without warehouse connection

					# Check if any input is below its stockpile target
					var needs_fetch := false
					var fetch_amounts: Dictionary = {}  # item → amount to fetch
					for slot in prod.input_stockpile:
						var current: int = data["input_buffer"].get(slot.item, 0)
						var needed: int = slot.amount - current
						if needed > 0:
							needs_fetch = true
							fetch_amounts[slot.item] = needed

					if needs_fetch:
						# Check we can afford the full fetch
						var can_fetch := true
						for item in fetch_amounts.keys():
							if not ResourceManager.has_enough(item, fetch_amounts[item]):
								can_fetch = false
								break
						if can_fetch:
							# Deduct from warehouse and populate carrier_cargo
							for item in fetch_amounts.keys():
								var amount: int = fetch_amounts[item]
								ResourceManager.remove(item, amount)
								data["carrier_cargo"][item] = data["carrier_cargo"].get(item, 0) + amount
							data["carrier_state"] = "fetching"
							data["logistics_progress"] = 0.0

				"fetching":
					data["logistics_progress"] += delta
					if data["logistics_progress"] >= dist:
						# Carrier arrived — move cargo to input_buffer
						for item in data["carrier_cargo"].keys():
							data["input_buffer"][item] = data["carrier_cargo"][item]
						data["carrier_cargo"].clear()
						data["carrier_state"] = "idle"

		# ── Production track (idle / producing) ──────────────────────────────────

		match data.get("prod_state", "idle"):

			"idle":
				if prod.input.is_empty():
					# No inputs needed — start producing immediately
					data["prod_state"] = "producing"
					data["timer"] = 0.0
				else:
					# Inputs needed — check input_buffer has enough
					var has_inputs := true
					for slot in prod.input:
						if data["input_buffer"].get(slot.item, 0) < slot.amount:
							has_inputs = false
							break
					if has_inputs:
						data["prod_state"] = "producing"
						data["timer"] = 0.0

			"producing":
				data["timer"] += delta
				if data["timer"] >= prod.production_time:
					# Production complete — check if output buffer has space
					var can_store := true
					for slot in prod.output:
						var cap := _storage_cap(prod, slot.item)
						if data["storage"].get(slot.item, 0) + slot.amount > cap:
							can_store = false
							break
					if can_store:
						# Consume inputs from input_buffer
						for slot in prod.input:
							data["input_buffer"][slot.item] -= slot.amount
						# Add outputs to storage buffer
						for slot in prod.output:
							data["storage"][slot.item] = data["storage"].get(slot.item, 0) + slot.amount
						data["prod_state"] = "idle"
						data["timer"] = 0.0
					# else: stall, keep timer, try again next frame

		# ── Carrier delivery track ──────────────────────────────────────────────

		match data.get("carrier_state", "idle"):
			"delivering":
				data["logistics_progress"] += delta
				if data["logistics_progress"] >= dist:
					# Carrier arrived at warehouse — move cargo to ResourceManager
					for item in data["carrier_cargo"].keys():
						var amount: int = data["carrier_cargo"][item]
						if amount > 0:
							ResourceManager.add(item, amount)
					data["carrier_cargo"].clear()
					data["carrier_state"] = "idle"

			"idle":
				# Try to start delivery if storage has items
				if not data["storage"].is_empty() and dist >= 0:
					var has_output := false
					for item in data["storage"].keys():
						if data["storage"][item] > 0:
							has_output = true
							break
					if has_output:
						# Move storage to carrier_cargo
						for item in data["storage"].keys():
							var amount = data["storage"][item]
							if amount > 0:
								data["carrier_cargo"][item] = amount
						data["storage"].clear()
						data["carrier_state"] = "delivering"
						data["logistics_progress"] = 0.0

	_update_carriers()


func rebuild_network() -> void:
	if not is_instance_valid(grid):
		return

	var road_indices := _road_indices()
	var storage_indices := _storage_indices()

	for origin in placed_buildings:
		var data: Dictionary = placed_buildings[origin]
		var carrier := data.get("carrier", null) as Node3D
		if is_instance_valid(carrier):
			carrier.queue_free()
		data["carrier"] = null
		data["connected"] = false
		data["warehouse_distance"] = -1
		data["warehouse_path"] = []
		data["carrier_state"] = "idle"
		data["input_buffer"] = {}
		data["carrier_cargo"] = {}

		var res := data.get("resource", null) as BuildingResource
		if res and res.active_variant != "":
			var inactive_id: int = data.get("grid_id", -1)
			if inactive_id >= 0:
				grid.set_cell_item(origin, inactive_id)

	var visited: Dictionary = {}
	var parent_map: Dictionary = {}
	var queue: Array[Vector3i] = []

	for origin in placed_buildings:
		var data: Dictionary = placed_buildings[origin]
		var grid_id: int = data.get("grid_id", -1)
		if grid_id in storage_indices:
			data["warehouse_distance"] = 0
			var fp: Vector2i = data.get("footprint", Vector2i(1, 1))
			for cell: Vector3i in _footprint_border(origin, fp):
				if grid.get_cell_item(cell) in road_indices and not visited.has(cell):
					visited[cell] = 1
					parent_map[cell] = WAREHOUSE_SENTINEL
					queue.append(cell)

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		var dist: int = visited[current]
		for offset in NEIGHBORS:
			var neighbor: Vector3i = current + offset
			var item := grid.get_cell_item(neighbor)
			if item in road_indices and not visited.has(neighbor):
				visited[neighbor] = dist + 1
				parent_map[neighbor] = current
				queue.append(neighbor)
			elif cell_to_anchor.has(neighbor):
				var anchor_cell: Vector3i = cell_to_anchor[neighbor]
				placed_buildings[anchor_cell]["connected"] = true
				var cur_dist: int = placed_buildings[anchor_cell].get("warehouse_distance", -1)
				if cur_dist < 0 or dist < cur_dist:
					placed_buildings[anchor_cell]["warehouse_distance"] = dist

	for origin in placed_buildings:
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue
		if data.get("warehouse_distance", -1) < 0:
			continue

		var fp: Vector2i = data.get("footprint", Vector2i(1, 1))
		var entry_cell := WAREHOUSE_SENTINEL
		var best_dist := 999999
		for cell: Vector3i in _footprint_border(origin, fp):
			if visited.has(cell) and visited[cell] < best_dist:
				best_dist = visited[cell]
				entry_cell = cell

		if entry_cell == WAREHOUSE_SENTINEL:
			continue

		var path: Array[Vector3i] = []
		var cur := entry_cell
		while parent_map.has(cur) and cur != WAREHOUSE_SENTINEL:
			path.append(cur)
			var parent: Vector3i = parent_map[cur]
			if parent == WAREHOUSE_SENTINEL:
				break
			cur = parent
		path.reverse()
		path.append(origin)
		data["warehouse_path"] = path

	for origin in placed_buildings:
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if res == null or res.active_variant == "":
			continue
		if data.get("warehouse_distance", -1) < 0:
			continue
		var active_entry: Dictionary = LibraryManager.buildings.get(res.active_variant, {})
		if active_entry.is_empty():
			continue
		var active_id: int = active_entry.get("index", -1)
		if active_id >= 0:
			grid.set_cell_item(origin, active_id)

	for cell: Vector3i in visited:
		if not cell_to_anchor.has(cell):
			continue
		var anchor_cell: Vector3i = cell_to_anchor[cell]
		var data: Dictionary = placed_buildings.get(anchor_cell, {})
		if data.is_empty():
			continue
		var res := data.get("resource", null) as BuildingResource
		if res == null or res.active_variant == "":
			continue
		var active_entry: Dictionary = LibraryManager.buildings.get(res.active_variant, {})
		if active_entry.is_empty():
			continue
		var active_id: int = active_entry.get("index", -1)
		if active_id >= 0:
			grid.set_cell_item(cell, active_id)


func _update_carriers() -> void:
	if not is_instance_valid(grid):
		return

	for origin in placed_buildings.keys():
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue

		var carrier_state: String = data.get("carrier_state", "idle")
		var dist: int = data.get("warehouse_distance", -1)
		var path: Array = data.get("warehouse_path", [])
		var carrier: Node3D = data.get("carrier", null) as Node3D
		var progress: float = data.get("logistics_progress", 0.0)

		var needs_carrier := (carrier_state == "fetching" or carrier_state == "delivering") and dist > 0 and not path.is_empty()

		if needs_carrier:
			if not is_instance_valid(carrier):
				carrier = _spawn_carrier()
				data["carrier"] = carrier

			var t := clampf(progress / float(dist), 0.0, 1.0)
			var path_t := t if carrier_state == "fetching" else (1.0 - t)
			carrier.position = _path_position(path, path_t)
			carrier.visible = true
		else:
			if is_instance_valid(carrier):
				carrier.visible = false
			data["carrier"] = null


func _spawn_carrier() -> Node3D:
	if not is_instance_valid(grid):
		return null
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.4, 0.8, 0.4)
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	grid.add_child(node)
	return node


func _path_position(path: Array, t: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1:
		return _cell_world(path[0])
	var scaled := t * (path.size() - 1)
	var idx := clampi(int(scaled), 0, path.size() - 2)
	var frac := scaled - float(idx)
	return _cell_world(path[idx]).lerp(_cell_world(path[idx + 1]), frac)


func _cell_world(cell: Vector3i) -> Vector3:
	return grid.map_to_local(cell) + Vector3(0, 0.8, 0)


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


func _footprint_border(origin: Vector3i, fp: Vector2i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dx in range(fp.x):
		for dz in range(fp.y):
			var cell := origin + Vector3i(dx, 0, dz)
			for offset in NEIGHBORS:
				var neighbor = cell + offset
				if not cell_to_anchor.has(neighbor) or cell_to_anchor[neighbor] != origin:
					cells.append(neighbor)
	return cells


func _storage_cap(prod: ProductionBuildingResource, item: String) -> int:
	for slot in prod.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0  # item not listed → no local buffer for it
