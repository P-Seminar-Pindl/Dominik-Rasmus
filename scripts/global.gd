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
		"storage":            {},      # local item buffer (inputs + outputs): { "Planks": 3 }
		"prod_timer":         0.0,     # seconds into current production cycle
		"prod_state":         "idle",  # idle | producing
		"carrier_cargo":      {},      # items the carrier is currently transporting
		"logistics_state":    "idle",  # idle | fetching | delivering
		"logistics_progress": 0.0,     # seconds of carrier travel completed this trip
		"carrier":            null,    # MeshInstance3D carrier node, or null
		"warehouse_distance": -1,      # road hops to nearest warehouse; -1 = disconnected
		"warehouse_path":     [],      # Array[Vector3i] road cells, warehouse-border → building
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
# Production and logistics run independently per building:
#
#   Production loop (prod_state):
#     idle → producing (repeats, fills storage buffer)
#     Consumes inputs from local storage; stalls if buffer full or inputs missing.
#
#   Logistics loop (logistics_state):
#     idle → delivering (output trip) or fetching (input trip)
#     Carrier physically takes items from storage, delivers to warehouse or back.
#
# "dist" = warehouse_distance (road hops). Progress advances 1 unit/second.

func _process(delta: float) -> void:
	for origin in placed_buildings.keys():
		var data: Dictionary = placed_buildings[origin]
		var res := data.get("resource", null) as BuildingResource
		if not res is ProductionBuildingResource:
			continue

		var prod := res as ProductionBuildingResource
		var dist: int = data.get("warehouse_distance", -1)

		# ── 1. Production (runs independently of logistics) ──
		_tick_production(data, prod, delta)

		# ── 2. Dispatch check (send carrier if idle and there's work) ──
		_tick_dispatch(data, prod, dist)

		# ── 3. Logistics (carrier travel, runs independently of production) ──
		_tick_logistics(data, dist, delta)


func _tick_production(data: Dictionary, prod: ProductionBuildingResource, delta: float) -> void:
	var state: String = data.get("prod_state", "idle")

	if state == "idle":
		if prod.input.is_empty():
			data["prod_state"] = "producing"
			data["prod_timer"] = 0.0
		else:
			# Check if local storage has enough of each input to start a cycle.
			var can_produce := true
			for slot in prod.input:
				if data["storage"].get(slot.item, 0) < slot.amount:
					can_produce = false
					break
			if can_produce:
				data["prod_state"] = "producing"
				data["prod_timer"] = 0.0

	if data.get("prod_state", "idle") == "producing":
		data["prod_timer"] += delta
		if data["prod_timer"] >= prod.production_time:
			# Check output buffer has room.
			var can_store := true
			for slot in prod.output:
				var cap := _storage_cap(prod, slot.item)
				if data["storage"].get(slot.item, 0) + slot.amount > cap:
					can_store = false
					break
			if not can_store:
				return  # stall — buffer full, wait for carrier to clear it

			# Consume inputs from local storage (skip for input-free buildings).
			for slot in prod.input:
				data["storage"][slot.item] = data["storage"].get(slot.item, 0) - slot.amount

			# Add outputs to local storage.
			for slot in prod.output:
				data["storage"][slot.item] = data["storage"].get(slot.item, 0) + slot.amount

			data["prod_timer"] = 0.0  # reset for next cycle, stay in "producing"


func _tick_dispatch(data: Dictionary, prod: ProductionBuildingResource, dist: int) -> void:
	if data.get("logistics_state", "idle") != "idle":
		return  # carrier already in transit

	# Priority 1: deliver output if we have any.
	var has_output := false
	for slot in prod.output:
		if data["storage"].get(slot.item, 0) > 0:
			has_output = true
			break

	if has_output and dist >= 0:
		# Move output items from storage onto the carrier.
		var cargo: Dictionary = {}
		for slot in prod.output:
			var amount: int = data["storage"].get(slot.item, 0)
			if amount > 0:
				cargo[slot.item] = amount
				data["storage"][slot.item] = 0
		data["carrier_cargo"] = cargo
		data["logistics_state"] = "delivering"
		data["logistics_progress"] = 0.0
		return

	# Priority 2: fetch inputs if we're running low.
	if prod.input.is_empty() or dist < 0:
		return
	var needs_input := false
	for slot in prod.input:
		if data["storage"].get(slot.item, 0) < slot.amount:
			needs_input = true
			break
	if not needs_input:
		return

	# Calculate how much to fetch (fill up to storage cap, don't overfill).
	var fetch_cargo: Dictionary = {}
	var can_fetch := true
	for slot in prod.input:
		var cap := _storage_cap(prod, slot.item)
		var current: int = data["storage"].get(slot.item, 0)
		var need: int = cap - current
		if need <= 0:
			continue
		if not ResourceManager.has_enough(slot.item, need):
			can_fetch = false
			break
		fetch_cargo[slot.item] = need

	if can_fetch and not fetch_cargo.is_empty():
		for item in fetch_cargo.keys():
			ResourceManager.remove(item, fetch_cargo[item])
		data["carrier_cargo"] = fetch_cargo
		data["logistics_state"] = "fetching"
		data["logistics_progress"] = 0.0


func _tick_logistics(data: Dictionary, dist: int, delta: float) -> void:
	var state: String = data.get("logistics_state", "idle")
	if state == "idle":
		return

	if dist < 0:
		return  # stall — no warehouse connection

	data["logistics_progress"] += delta

	if state == "fetching":
		if data["logistics_progress"] >= dist:
			# Carrier arrived at building — unload inputs into storage.
			for item in data["carrier_cargo"].keys():
				data["storage"][item] = data["storage"].get(item, 0) + int(data["carrier_cargo"][item])
			data["carrier_cargo"].clear()
			data["logistics_state"] = "idle"

	elif state == "delivering":
		if data["logistics_progress"] >= dist:
			# Carrier arrived at warehouse — flush cargo to global stockpile.
			for item in data["carrier_cargo"].keys():
				var amount: int = data["carrier_cargo"][item]
				if amount > 0:
					ResourceManager.add(item, amount)
			data["carrier_cargo"].clear()
			data["logistics_state"] = "idle"


func _storage_cap(prod: ProductionBuildingResource, item: String) -> int:
	for slot in prod.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0  # item not listed → no local buffer for it
