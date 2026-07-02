# global.gd — autoload "Global"
# Economy engine for the vertical slice: production tick, warehouse/street BFS
# network, and worker assignment. Reads/writes runtime state directly into
# PlacementManager.placed_buildings entries (adapted from .old/scripts/global.gd,
# GridMap → Vector2i tile coords, carriers deferred).
extends Node

const NEIGHBORS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var placement: Node3D = null  # PlacementManager; registers itself in _ready


func register_placement_manager(pm: Node3D) -> void:
	placement = pm
	pm.building_placed.connect(_on_building_placed)
	pm.building_removed.connect(_on_building_removed)
	rebuild_network()


func _on_building_placed(_anchor: Vector2i, _res: BuildingResource) -> void:
	rebuild_network()


func _on_building_removed(_anchor: Vector2i) -> void:
	rebuild_network()


# ── Production tick ───────────────────────────────────────────────────────────
#
# Per production building: idle → producing → (outputs) → idle.
# Outputs go straight to the city stockpile while the building is connected to
# a warehouse via streets; otherwise they pile up in the local storage buffer
# and production stalls once it is full. Inputs are fetched from the stockpile
# and require a warehouse connection.

func _process(delta: float) -> void:
	if placement == null:
		return

	for anchor in placement.placed_buildings:
		var data: Dictionary = placement.placed_buildings[anchor]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue
		var prod := res as ProductionBuildingResource
		_ensure_state(data)

		if data.get("workers_assigned", 0) < prod.workforce:
			data["status"] = "No workers"
			continue

		var connected: bool = data.get("warehouse_distance", -1) >= 0

		# Flush local buffer into the city stockpile once connected
		if connected and not data["storage"].is_empty():
			for item in data["storage"]:
				var amount: int = data["storage"][item]
				if amount > 0:
					ResourceManager.add(item, amount)
			data["storage"].clear()

		match data["prod_state"]:
			"idle":
				var has_inputs := true
				for slot in prod.input:
					if not connected or not ResourceManager.has_enough(slot.item, slot.amount):
						has_inputs = false
						break
				if has_inputs:
					data["prod_state"] = "producing"
					data["timer"] = 0.0
					data["status"] = "Producing" if connected else "Producing (not connected)"
				else:
					data["status"] = "Stalled (no inputs)" if connected else "Disconnected"

			"producing":
				data["timer"] += delta
				data["status"] = "Producing" if connected else "Producing (not connected)"
				if data["timer"] >= prod.production_time:
					# When disconnected, outputs must fit in the local buffer
					var can_store := true
					if not connected:
						for slot in prod.output:
							if data["storage"].get(slot.item, 0) + slot.amount > _storage_cap(prod, slot.item):
								can_store = false
								break
					# Inputs are consumed on completion — re-check availability
					var can_consume := true
					for slot in prod.input:
						if not ResourceManager.has_enough(slot.item, slot.amount):
							can_consume = false
							break
					if can_store and can_consume:
						for slot in prod.input:
							ResourceManager.remove(slot.item, slot.amount)
						for slot in prod.output:
							if connected:
								ResourceManager.add(slot.item, slot.amount)
							else:
								data["storage"][slot.item] = data["storage"].get(slot.item, 0) + slot.amount
						data["prod_state"] = "idle"
						data["timer"] = 0.0
					else:
						# Stall: keep the finished cycle waiting for space/inputs
						data["timer"] = prod.production_time
						data["status"] = "Storage full" if not can_store else "Stalled (no inputs)"


func _ensure_state(data: Dictionary) -> void:
	if not data.has("prod_state"):
		data["prod_state"] = "idle"
		data["timer"] = 0.0
		data["storage"] = {}
		data["status"] = "Idle"
	if not data.has("warehouse_distance"):
		data["warehouse_distance"] = -1
	if not data.has("workers_assigned"):
		data["workers_assigned"] = 0


# ── Street network (BFS from warehouses) ─────────────────────────────────────

func rebuild_network() -> void:
	if placement == null:
		return
	var pb: Dictionary = placement.placed_buildings

	# Collect every cell covered by a street; reset connectivity
	var road_cells: Dictionary = {}
	for anchor in pb:
		var data: Dictionary = pb[anchor]
		_ensure_state(data)
		data["warehouse_distance"] = -1
		var res := data.get("resource", null) as BuildingResource
		if res is RoadBuildingResource:
			var fp: Vector2i = data.get("footprint", res.footprint_size)
			for dx in range(fp.x):
				for dz in range(fp.y):
					road_cells[anchor + Vector2i(dx, dz)] = true

	# Seed BFS from warehouse borders; buildings touching a warehouse connect at 0
	var visited: Dictionary = {}  # road cell → dist (in road hops)
	var queue: Array[Vector2i] = []
	for anchor in pb:
		var data: Dictionary = pb[anchor]
		var res := data.get("resource", null) as BuildingResource
		if not res is StorageBuildingResource:
			continue
		data["warehouse_distance"] = 0
		var fp: Vector2i = data.get("footprint", res.footprint_size)
		for cell in _border_cells(anchor, fp):
			if road_cells.has(cell):
				if not visited.has(cell):
					visited[cell] = 1
					queue.append(cell)
			elif placement.cell_to_anchor.has(cell):
				var other: Dictionary = pb[placement.cell_to_anchor[cell]]
				if other.get("warehouse_distance", -1) != 0:
					other["warehouse_distance"] = 0

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var dist: int = visited[current]
		for offset in NEIGHBORS:
			var neighbor: Vector2i = current + offset
			if road_cells.has(neighbor):
				if not visited.has(neighbor):
					visited[neighbor] = dist + 1
					queue.append(neighbor)
			elif placement.cell_to_anchor.has(neighbor):
				var data: Dictionary = pb[placement.cell_to_anchor[neighbor]]
				var cur: int = data.get("warehouse_distance", -1)
				if cur < 0 or dist < cur:
					data["warehouse_distance"] = dist

	_update_workers()


func _border_cells(anchor: Vector2i, fp: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(fp.x):
		cells.append(anchor + Vector2i(dx, -1))
		cells.append(anchor + Vector2i(dx, fp.y))
	for dz in range(fp.y):
		cells.append(anchor + Vector2i(-1, dz))
		cells.append(anchor + Vector2i(fp.x, dz))
	return cells


# ── Workers ───────────────────────────────────────────────────────────────────

func _update_workers() -> void:
	var pb: Dictionary = placement.placed_buildings
	var capacity := 0
	for anchor in pb:
		var res := pb[anchor].get("resource", null) as BuildingResource
		if res is HouseBuildingResource:
			capacity += (res as HouseBuildingResource).population_capacity

	# Assign in placement order until the pool runs dry
	var used := 0
	for anchor in pb:
		var data: Dictionary = pb[anchor]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue
		if used + res.workforce <= capacity:
			data["workers_assigned"] = res.workforce
			used += res.workforce
		else:
			data["workers_assigned"] = 0

	ResourceManager.set_workers(capacity, used)


func _storage_cap(prod: ProductionBuildingResource, item: String) -> int:
	for slot in prod.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0  # item not listed → no local buffer for it
