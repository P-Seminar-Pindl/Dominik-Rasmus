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

func _ready() -> void:
	BuildingNetwork.register(self)
	await rebuild_network()


## Call this after any building is placed or removed.
func rebuild_network() -> void:
	var road_indices    := _road_indices()
	var storage_indices := _storage_indices()

	# Reset all roads to their inactive variant first
	for origin in Global.placed_buildings:
		
		Global.placed_buildings[origin]["connected"] = false
		var res := Global.placed_buildings[origin].get("resource") as BuildingResource
		if res == null:
			continue
		if res is RoadBuildingResource:
			var inactive_id: int = Global.placed_buildings[origin].get("grid_id", -1)
			set_cell_item(Global.cell_to_anchor.get(origin, origin), inactive_id)

	var visited: Dictionary = {}
	var queue: Array[Vector3i] = []

	for origin in Global.placed_buildings:
		var grid_id: int = Global.placed_buildings[origin].get("grid_id", -1)
		if grid_id in storage_indices:
			var fp: Vector2i = Global.placed_buildings[origin].get("footprint", Vector2i(1, 1))
			for cell: Vector3i in _footprint_border(origin, fp):
				var item := get_cell_item(cell)
				if item in road_indices and not visited.has(cell):
					visited[cell] = true
					queue.append(cell)

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for offset in NEIGHBORS:
			var neighbor: Vector3i = current + offset
			var item := get_cell_item(neighbor)
			if item in road_indices and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
			elif Global.cell_to_anchor.has(neighbor):
				var anchor: Vector3i = Global.cell_to_anchor[neighbor]
				Global.placed_buildings[anchor]["connected"] = true

	# Swap visited roads to their active variant
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
