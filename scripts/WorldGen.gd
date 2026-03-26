extends Node
class_name WorldGen

static var noise = FastNoiseLite.new()
static var warp_noise = FastNoiseLite.new()  # NEW: for domain warping
static var cell_pos = Vector3i(0,0,0)
static var grid: GridMap
static var LoadedTiles = []

static func generate_map(grid, offsetx, offsety, distribution_curve, renderDistance: int, PlayerPos: Vector3, HeigthModifier:int):
	var center = Vector2(PlayerPos.x, PlayerPos.z)  # fixed: was PlayerPos.y, should be .z for 3D
	var coords = cords_in_radius(renderDistance, center)
	noise.offset.x = offsetx
	noise.offset.y = offsety
	warp_noise.offset.x = offsetx + 1000  # offset so it's different from main noise
	warp_noise.offset.y = offsety + 1000
	for i in coords.size():
		LoadTile(grid, coords[i], distribution_curve, i, HeigthModifier)

static func cords_in_radius(radius: int, center: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var pos = Vector2i(x, y)
			if center.distance_to(pos) <= radius:
				results.append(pos)
	return results

static func remove_map(map: GridMap):
	map.clear()
	LoadedTiles.clear()  # NEW: was missing, caused LoadedTiles to grow forever

# NEW: fBm — samples noise at multiple frequencies and blends them
static func fbm(x: float, y: float) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 1.0
	for i in 4:  # 4 octaves
		value += noise.get_noise_2d(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	return (value + 1.0) * 0.5  # normalize to 0..1

# NEW: continent mask — returns 1.0 at center, 0.0 at edges, based on render radius
static func continent_mask(coord: Vector2i, center: Vector2, radius: float) -> float:
	var dist = center.distance_to(Vector2(coord.x, coord.y))
	var normalized = dist / radius
	return clamp(1.0 - smoothstep(0.3, 0.85, normalized), 0.0, 1.0)

static func LoadTile(grid, coordinate, distribution_curve, index, HeightModifier):
	# Domain warp: shift sample coordinates using a second noise value
	var warp_strength = 8.0
	var wx = warp_noise.get_noise_2d(coordinate.x * 0.05, coordinate.y * 0.05) * warp_strength
	var wy = warp_noise.get_noise_2d(coordinate.x * 0.05 + 100, coordinate.y * 0.05 + 100) * warp_strength

	# fBm on warped coordinates instead of plain noise
	var nNoise = fbm(coordinate.x + wx, coordinate.y + wy)
	nNoise = distribution_curve.sample(nNoise)

	# Continent mask: multiply noise by falloff so edges become ocean
	# You'll need to pass center/radius through or store them as static vars
	# For now, bias toward water at edges using a fixed world center
	var world_center = Vector2(0, 0)
	var mask = multi_island_mask(coordinate)
	nNoise = lerp(0.0, nNoise, mask)  # edges get pushed toward 0 (water)

	var height = int((nNoise - 0.2) * HeightModifier)
	var Tile = LibraryManager.Tiles
	LoadedTiles.append(coordinate)

	if nNoise < 0.2:
		grid.set_cell_item(Vector3i(coordinate.x, 0, coordinate.y), Tile["Water"])  # flat water
	elif nNoise < 0.4:
		grid.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), Tile["Sand"])
	elif nNoise < 0.6:
		grid.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), Tile["Grass"])
	elif nNoise < 0.8:
		grid.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), Tile["Forest"])
	else:
		grid.set_cell_item(Vector3i(coordinate.x, height, coordinate.y), Tile["Stone"])
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

static func multi_island_mask(coord: Vector2i) -> float:
	var best = 0.0
	for center in island_centers:
		var dist = center.distance_to(Vector2(coord.x, coord.y))
		var radius = 80.0  # per island radius, tune this
		var mask = clamp(1.0 - smoothstep(0.3, 0.85, dist / radius), 0.0, 1.0)
		best = max(best, mask)
	return best
