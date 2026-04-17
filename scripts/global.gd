extends Node
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
		"prod_state":         "idle",  # idle | fetching | producing | delivering
		"logistics_progress": 0.0,     # seconds of carrier travel completed this trip
		"carrier":            null,    # MeshInstance3D carrier node, or null
	}

	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor[origin + Vector3i(dx, 0, dz)] = origin


func remove_building(origin: Vector3i) -> void:
	var data: Dictionary = placed_buildings.get(origin, {})
	if data.is_empty():
		return
	var fp: Vector2i = data.get("footprint", Vector2i(1, 1))
	for dx in range(fp.x):
		for dz in range(fp.y):
			cell_to_anchor.erase(origin + Vector3i(dx, 0, dz))
	placed_buildings.erase(origin)


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

		match data.get("prod_state", "idle"):

			"idle":
				if prod.input.is_empty():
					# No inputs needed — produce freely, warehouse only required for delivery.
					data["prod_state"] = "producing"
					data["timer"] = 0.0
				else:
					if dist < 0:
						continue  # needs warehouse to fetch inputs
					# Reserve inputs now — they leave the warehouse with the carrier.
					var can_fetch := true
					for slot in prod.input:
						if not ResourceManager.has_enough(slot.item, slot.amount):
							can_fetch = false
							break
					if can_fetch:
						for slot in prod.input:
							ResourceManager.remove(slot.item, slot.amount)
						data["prod_state"] = "fetching"
						data["logistics_progress"] = 0.0

			"fetching":
				# Carrier travels from warehouse to production building.
				data["logistics_progress"] += delta
				if data["logistics_progress"] >= dist:
					data["prod_state"] = "producing"
					data["timer"] = 0.0

			"producing":
				data["timer"] += delta
				if data["timer"] >= prod.production_time:
					# Fill local output buffer. Stall if full (wait for space).
					var can_store := true
					for slot in prod.output:
						var cap := _storage_cap(prod, slot.item)
						if data["storage"].get(slot.item, 0) + slot.amount > cap:
							can_store = false
							break
					if can_store:
						for slot in prod.output:
							data["storage"][slot.item] = data["storage"].get(slot.item, 0) + slot.amount
						data["prod_state"] = "delivering"
						data["logistics_progress"] = 0.0

			"delivering":
				# Carrier travels from production building back to warehouse.
				# Stall if disconnected — output stays in local buffer until a road is built.
				if dist < 0:
					continue
				data["logistics_progress"] += delta
				if data["logistics_progress"] >= dist:
					for item in data["storage"].keys():
						var amount: int = data["storage"][item]
						if amount > 0:
							ResourceManager.add(item, amount)
							data["storage"][item] = 0
					data["prod_state"] = "idle"


func _storage_cap(prod: ProductionBuildingResource, item: String) -> int:
	for slot in prod.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0  # item not listed → no local buffer for it
