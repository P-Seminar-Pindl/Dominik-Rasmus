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
		"id":           building_id,
		"grid_id":      entry["index"],
		"resource":     res,
		"footprint":    fp,
		"productivity": 1.0,
		"population":   0,
		"storage":      {},   # local buffer: { "Planks": 3 }
		"timer":        0.0,  # seconds elapsed toward next production cycle
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

func _process(delta: float) -> void:
	for origin in placed_buildings.keys():
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue

		var prod := res as ProductionBuildingResource
		data["timer"] += delta
		if data["timer"] < prod.production_time:
			continue
		data["timer"] = 0.0

		# Check all inputs are available in the global stockpile.
		for slot in prod.input:
			if not ResourceManager.has_enough(slot.item, slot.amount):
				continue  # skip this building this cycle

		# Consume inputs.
		for slot in prod.input:
			ResourceManager.remove(slot.item, slot.amount)

		# Produce outputs into local buffer, respecting per-slot caps.
		for slot in prod.output:
			var cap: int = _storage_cap(prod, slot.item)
			var current: int = data["storage"].get(slot.item, 0)
			var space: int = cap - current
			if space <= 0:
				continue
			var produced: int = min(slot.amount, space)
			data["storage"][slot.item] = current + produced

		# Flush local buffer to the global stockpile.
		for item in data["storage"].keys():
			var amount: int = data["storage"][item]
			if amount > 0:
				ResourceManager.add(item, amount)
				data["storage"][item] = 0


func _storage_cap(prod: ProductionBuildingResource, item: String) -> int:
	for slot in prod.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0  # item not listed → no local buffer for it
