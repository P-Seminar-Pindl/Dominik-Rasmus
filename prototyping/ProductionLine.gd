extends GridMap

const HOUSE_INACTIVE := 0
const ROAD := 1
const WAREHOUSE := 2
const HOUSE_ACTIVE := 3
const ROAD_ACTIVE := 4

const NEIGHBORS := [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

func _ready() -> void:
	await rebuild_network()

func sleep(seconds):
	await get_tree().create_timer(seconds).timeout

## Call this after any road or warehouse is placed or removed.
func rebuild_network() -> void:
	# Reset all active roads and houses back to inactive
	for cell in get_used_cells_by_item(ROAD_ACTIVE):
		await sleep(0.5)
		set_cell_item(cell, ROAD)
	for cell in get_used_cells_by_item(HOUSE_ACTIVE):
		await sleep(0.5)
		set_cell_item(cell, HOUSE_INACTIVE)

	# BFS from every warehouse, spreading through adjacent roads
	var visited: Dictionary = {}
	var queue: Array = []

	for warehouse_cell in get_used_cells_by_item(WAREHOUSE):
		for offset in NEIGHBORS:
			var neighbor: Vector3i = warehouse_cell + offset
			if get_cell_item(neighbor) == ROAD and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	while not queue.is_empty():
		await sleep(0.5)
		var current: Vector3i = queue.pop_front()
		set_cell_item(current, ROAD_ACTIVE)

		for offset in NEIGHBORS:
			var neighbor: Vector3i = current + offset
			var item := get_cell_item(neighbor)
			if item == ROAD and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
			elif item == HOUSE_INACTIVE:
				set_cell_item(neighbor, HOUSE_ACTIVE)
