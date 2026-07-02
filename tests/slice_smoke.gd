# slice_smoke.gd — headless smoke test for the vertical-slice economy.
# Run with:  godot --headless --path . res://tests/slice_smoke.tscn
# Instantiates the real Game scene, places buildings through PlacementManager,
# and asserts cost deduction, worker assignment, street/warehouse connectivity,
# production output, and demolish refunds. Prints PASS/FAIL lines and quits.
extends Node

const NO_TILE := Vector2i(-99999, -99999)

var _fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)


func _find_building(pm: Node3D, bname: String) -> BuildingResource:
	for res in pm.available_buildings:
		if res.name == bname:
			return res
	return null


# Scans around island centers for a clear, flat, buildable area of size fp.
func _find_area(pm: Node3D, world: Node3D, fp: Vector2i) -> Vector2i:
	var centers: Array[Vector2] = []
	for rx in range(-1, 2):
		for ry in range(-1, 2):
			var rd = world._ensure_region(Vector2i(rx, ry))
			centers.append_array(rd.island_centers)
	for center in centers:
		var cx := int(center.x)
		var cy := int(center.y)
		for r in range(0, 80, 4):
			for x in range(cx - r, cx + r + 1, 4):
				for y in range(cy - r, cy + r + 1, 4):
					var anchor := Vector2i(x, y)
					if pm._can_place(anchor, fp, null):
						return anchor
	return NO_TILE


func _ready() -> void:
	var game: Node = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var pm: Node3D = game.get_node("PlacementManager")
	var world: Node3D = game.get_node("World")

	_check(not pm.available_buildings.is_empty(),
			"buildings loaded (%d)" % pm.available_buildings.size())

	var windmill := _find_building(pm, "Windmill")
	var warehouse := _find_building(pm, "Warehouse")
	var cottage := _find_building(pm, "Cottage")
	var street := _find_building(pm, "Stone Street")
	_check(windmill != null and warehouse != null and cottage != null and street != null,
			"core buildings present")
	if windmill == null or warehouse == null or cottage == null or street == null:
		_finish()
		return
	_check(street is RoadBuildingResource, "street is RoadBuildingResource")
	_check(warehouse is StorageBuildingResource, "warehouse is StorageBuildingResource")

	# Layout inside one flat 12x12 area:
	#   windmill A (3x3) at +0,0 | warehouse (4x4) at +3,0 (touching A)
	#   street (1x4) at +7,0 | windmill B (3x3) at +8,0 | cottage (2x2) at +0,5
	var base := _find_area(pm, world, Vector2i(12, 12))
	_check(base != NO_TILE, "found flat buildable 12x12 area at %s" % str(base))
	if base == NO_TILE:
		_finish()
		return

	# 1. Placement + cost deduction
	var gold_before: int = ResourceManager.get_amount("Gold")
	pm._rotation = 0
	pm._place_building(base, windmill)
	_check(pm.placed_buildings.has(base), "windmill A placed")
	_check(ResourceManager.get_amount("Gold") == gold_before - 30, "gold deducted on placement")
	var data_a: Dictionary = pm.placed_buildings[base]

	# 2. No workers yet
	Global._process(0.1)
	_check(data_a.get("status", "") == "No workers",
			"windmill A 'No workers' before housing (got '%s')" % str(data_a.get("status")))

	# 3. Cottage provides 2 workers → windmill A staffed
	var cot_anchor := base + Vector2i(0, 5)
	pm._place_building(cot_anchor, cottage)
	_check(pm.placed_buildings.has(cot_anchor), "cottage placed")
	_check(ResourceManager.worker_capacity == 2 and ResourceManager.workers_used == 2,
			"workers 2/2 assigned (got %d/%d)" % [ResourceManager.workers_used, ResourceManager.worker_capacity])

	# 4. Disconnected → produces into local buffer
	Global._process(0.1)
	_check(data_a.get("prod_state", "") == "producing", "windmill A producing while disconnected")

	# 5. Warehouse touching windmill A → connected at distance 0
	var wh_anchor := base + Vector2i(3, 0)
	pm._place_building(wh_anchor, warehouse)
	_check(pm.placed_buildings.has(wh_anchor), "warehouse placed adjacent")
	_check(data_a.get("warehouse_distance", -1) == 0,
			"windmill A connected at distance 0 (got %d)" % data_a.get("warehouse_distance", -1))

	# 6. Street bridges warehouse → windmill B (1 road hop)
	var street_anchor := base + Vector2i(7, 0)
	pm._place_building(street_anchor, street)
	var b_anchor := base + Vector2i(8, 0)
	pm._place_building(b_anchor, windmill)
	_check(pm.placed_buildings.has(street_anchor) and pm.placed_buildings.has(b_anchor),
			"street + windmill B placed")
	var data_b: Dictionary = pm.placed_buildings[b_anchor]
	_check(data_b.get("warehouse_distance", -1) == 1,
			"windmill B connected via street at distance 1 (got %d)" % data_b.get("warehouse_distance", -1))

	# 7. Worker pool exhausted → windmill B unstaffed
	Global._process(0.1)
	_check(data_b.get("status", "") == "No workers", "windmill B 'No workers' (pool exhausted)")

	# 8. Production completes → output lands in city stockpile
	var planks_before: int = ResourceManager.get_amount("Planks")
	Global._process(9.0)  # finish current cycle (production_time = 8s)
	Global._process(0.1)
	_check(ResourceManager.get_amount("Planks") >= planks_before + 3,
			"windmill A delivered planks to stockpile (%d → %d)" % [planks_before, ResourceManager.get_amount("Planks")])

	# 9. Demolish street → 50% refund, windmill B disconnected again
	var gold_pre_refund: int = ResourceManager.get_amount("Gold")
	pm.remove_building(street_anchor)
	_check(not pm.placed_buildings.has(street_anchor), "street demolished")
	_check(ResourceManager.get_amount("Gold") == gold_pre_refund + 1, "50% refund granted")
	_check(data_b.get("warehouse_distance", -1) == -1, "windmill B disconnected after street removal")

	# 10. Terrain-name query sanity
	var tile_name: String = world.get_tile_name_at(base)
	_check(tile_name != "" and tile_name != "Water", "tile name at base is land ('%s')" % tile_name)

	_finish()


func _finish() -> void:
	if _fails == 0:
		print("SMOKE TEST: ALL PASSED")
	else:
		printerr("SMOKE TEST: %d FAILURE(S)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
