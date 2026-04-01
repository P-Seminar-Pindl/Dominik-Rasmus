extends Node

static var noise = FastNoiseLite.new()
static var warp_noise = FastNoiseLite.new()
static var loaded_tiles: Array[Vector2i] = []
static var island_centers: Array[Vector2] = []


static func generate_island_centers(count: int, spread: float, seed: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	island_centers.clear()
	for i in count:
		island_centers.append(Vector2(
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread, spread)
		))


static func generate_map(
		map: GridMap,
		offset_x: int,
		offset_y: int,
		distribution_curve: Curve,
		render_distance: int,
		player_pos: Vector3,
		height_modifier: int) -> void:

	var center = Vector2(player_pos.x, player_pos.z)
	var coords = coords_in_radius(render_distance, center)
	noise.offset.x = offset_x
	noise.offset.y = offset_y
	warp_noise.offset.x = offset_x + 1000
	warp_noise.offset.y = offset_y + 1000
	for coord in coords:
		_load_tile(map, coord, distribution_curve, height_modifier)


static func remove_map(map: GridMap) -> void:
	map.clear()
	loaded_tiles.clear()


static func coords_in_radius(radius: int, center: Vector2) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for x in range(int(center.x) - radius, int(center.x) + radius + 1):
		for y in range(int(center.y) - radius, int(center.y) + radius + 1):
			var pos = Vector2i(x, y)
			if center.distance_to(Vector2(pos)) <= radius:
				results.append(pos)
	return results


# fBm — samples noise at multiple frequencies and blends them
static func _fbm(x: float, y: float) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 1.0
	for i in 4:  # 4 octaves
		value += noise.get_noise_2d(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	return (value + 1.0) * 0.5  # normalize to 0..1


static func _multi_island_mask(coord: Vector2i) -> float:
	var best = 0.0
	for center in island_centers:
		var dist = center.distance_to(Vector2(coord.x, coord.y))
		var radius = 80.0
		var mask = clamp(1.0 - smoothstep(0.3, 0.85, dist / radius), 0.0, 1.0)
		best = max(best, mask)
	return best


static func _load_tile(map: GridMap, coordinate: Vector2i, distribution_curve: Curve, height_modifier: int) -> void:
	var warp_strength = 8.0
	var wx = warp_noise.get_noise_2d(coordinate.x * 0.05, coordinate.y * 0.05) * warp_strength
	var wy = warp_noise.get_noise_2d(coordinate.x * 0.05 + 100, coordinate.y * 0.05 + 100) * warp_strength

	var n = _fbm(coordinate.x + wx, coordinate.y + wy)
	n = distribution_curve.sample(n)

	var mask = _multi_island_mask(coordinate)
	n = lerp(0.0, n, mask)

	var height = int((n - 0.2) * height_modifier)
	var tile = LibraryManager.tiles
	loaded_tiles.append(coordinate)

	if n < 0.2:
		map.set_cell_item(Vector3i(coordinate.x, 0, coordinate.y), tile["Water"])
	elif n < 0.4:
		map.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), tile["Sand"])
	elif n < 0.6:
		map.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), tile["Grass"])
	elif n < 0.8:
		map.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), tile["Forest"])
	else:
		map.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), tile["Stone"])
