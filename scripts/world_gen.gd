# world_gen.gd
extends GridMap

# ── Noise instances ───────────────────────────────────────────────────────────
static var elev_noise:   FastNoiseLite = FastNoiseLite.new()
static var warp_noise:   FastNoiseLite = FastNoiseLite.new()
static var temp_noise:   FastNoiseLite = FastNoiseLite.new()
static var humid_noise:  FastNoiseLite = FastNoiseLite.new()
static var detail_noise: FastNoiseLite = FastNoiseLite.new()

# ── Runtime state ─────────────────────────────────────────────────────────────
static var loaded_chunks:  Dictionary      = {}
static var chunk_tiles:    Dictionary      = {}
static var load_queue:     Array[Vector2i] = []
static var queued_set:     Dictionary      = {}

# Region layer — infinite island placement
static var region_data:    Dictionary      = {}  # Vector2i → RegionData
static var river_tile_set: Dictionary      = {}  # Vector2i → true
static var river_bank_set: Dictionary      = {}  # Vector2i → true (sand border)

static var cfg: WorldGenConfig = preload("res://data/world_gen_default.tres")
static var _last_cfg_hash: int = -1


# ── Inner classes ─────────────────────────────────────────────────────────────

class RegionData:
	var island_centers: Array[Vector2] = []
	var river_paths:    Array          = []  # Array of Array[Vector2i]


# ── Init ──────────────────────────────────────────────────────────────────────

static func init(config: WorldGenConfig) -> void:
	cfg = config

	elev_noise.noise_type  = cfg.noise_type
	elev_noise.frequency   = cfg.noise_freq
	elev_noise.seed        = cfg.seed

	# frequency = 1.0 here; manual scaling by cfg.warp_freq applied at call site
	warp_noise.noise_type  = cfg.noise_type
	warp_noise.frequency   = 1.0
	warp_noise.seed        = cfg.seed + 3

	temp_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency   = cfg.temp_freq
	temp_noise.seed        = cfg.seed + 1

	humid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	humid_noise.frequency  = cfg.humid_freq
	humid_noise.seed       = cfg.seed + 2

	detail_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	detail_noise.frequency  = 0.15
	detail_noise.seed       = cfg.seed + 4

	loaded_chunks.clear()
	chunk_tiles.clear()
	load_queue.clear()
	queued_set.clear()
	region_data.clear()
	river_tile_set.clear()
	river_bank_set.clear()


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var current_hash := cfg.get_rid().get_id() * 31 + inst_to_dict(cfg).hash()
	if current_hash != _last_cfg_hash:
		_last_cfg_hash = current_hash
		WorldGen.init(cfg)
		remove_map(Global.grid)
		stream_chunks(Global.grid, Global.distribution_curve, Global.anchor)

	var chunks_per_frame := cfg.chunks_per_frame
	for i in chunks_per_frame:
		if load_queue.is_empty():
			break
		var c: Vector2i = load_queue.pop_front()
		queued_set.erase(c)
		if not loaded_chunks.has(c):
			_load_chunk(Global.grid, c, Global.distribution_curve)


# ── Streaming ─────────────────────────────────────────────────────────────────

static func stream_chunks(map: GridMap, distribution_curve: Curve, anchor: Vector2) -> void:
	var player_chunk := _tile_to_chunk(Vector2i(int(anchor.x), int(anchor.y)))

	var desired: Dictionary = {}
	for cx in range(player_chunk.x - cfg.chunk_render_dist,
					player_chunk.x + cfg.chunk_render_dist + 1):
		for cy in range(player_chunk.y - cfg.chunk_render_dist,
						player_chunk.y + cfg.chunk_render_dist + 1):
			var c := Vector2i(cx, cy)
			if Vector2(player_chunk).distance_to(Vector2(c)) <= cfg.chunk_render_dist:
				desired[c] = true

	var added_new := false
	for c in desired:
		if not loaded_chunks.has(c) and not queued_set.has(c):
			load_queue.append(c)
			queued_set[c] = true
			added_new = true

	if added_new:
		load_queue.sort_custom(func(a, b):
			return Vector2(player_chunk).distance_to(Vector2(a)) \
				 < Vector2(player_chunk).distance_to(Vector2(b))
		)

	for c in loaded_chunks.keys():
		if not desired.has(c):
			_unload_chunk(map, c)

	load_queue = load_queue.filter(func(c):
		if not desired.has(c):
			queued_set.erase(c)
			return false
		return true
	)


static func remove_map(map: GridMap) -> void:
	map.clear()
	loaded_chunks.clear()
	chunk_tiles.clear()
	load_queue.clear()
	queued_set.clear()
	region_data.clear()
	river_tile_set.clear()
	river_bank_set.clear()


# ── Coordinates ───────────────────────────────────────────────────────────────

static func _tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / cfg.chunk_size),
		floori(float(tile.y) / cfg.chunk_size)
	)

static func _chunk_origin(chunk: Vector2i) -> Vector2i:
	return Vector2i(chunk.x * cfg.chunk_size, chunk.y * cfg.chunk_size)

static func _tile_to_region(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / cfg.region_size),
		floori(float(tile.y) / cfg.region_size)
	)

static func _region_seed(rcoord: Vector2i) -> int:
	return cfg.seed ^ (rcoord.x * 1000003) ^ (rcoord.y * 999983)


# ── Region generation ─────────────────────────────────────────────────────────

static func _ensure_region(rcoord: Vector2i) -> RegionData:
	if region_data.has(rcoord):
		return region_data[rcoord]

	var rd  := RegionData.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = _region_seed(rcoord)

	var count: int = rng.randi_range(0, cfg.islands_per_region)
	var region_center := Vector2(
		(rcoord.x + 0.5) * cfg.region_size,
		(rcoord.y + 0.5) * cfg.region_size
	)
	for _i in count:
		rd.island_centers.append(Vector2(
			region_center.x + rng.randf_range(-cfg.region_island_spread, cfg.region_island_spread),
			region_center.y + rng.randf_range(-cfg.region_island_spread, cfg.region_island_spread)
		))

	# Store before river generation so recursive _ensure_region calls don't re-enter
	region_data[rcoord] = rd

	if cfg.river_enabled:
		_generate_rivers_for_region(rd, rng)

	return rd


# ── Chunk load/unload ─────────────────────────────────────────────────────────

static func _load_chunk(map: GridMap, chunk: Vector2i, curve: Curve) -> void:
	var origin := _chunk_origin(chunk)

	# Pre-generate regions for both corners of this chunk so island/river data
	# is ready before any tile in this chunk calls _multi_island_mask
	_ensure_region(_tile_to_region(origin))
	_ensure_region(_tile_to_region(Vector2i(
		origin.x + cfg.chunk_size - 1,
		origin.y + cfg.chunk_size - 1
	)))

	var tiles_placed: Array[Vector3i] = []
	for lx in cfg.chunk_size:
		for ly in cfg.chunk_size:
			var coord := Vector2i(origin.x + lx, origin.y + ly)
			var cell  := _compute_tile(coord, curve)
			map.set_cell_item(cell.pos, cell.mesh_id)
			tiles_placed.append(cell.pos)
	loaded_chunks[chunk] = true
	chunk_tiles[chunk]   = tiles_placed

static func _unload_chunk(map: GridMap, chunk: Vector2i) -> void:
	if chunk_tiles.has(chunk):
		for cell_pos in chunk_tiles[chunk]:
			map.set_cell_item(cell_pos, GridMap.INVALID_CELL_ITEM)
		chunk_tiles.erase(chunk)
	loaded_chunks.erase(chunk)


# ── Tile computation ──────────────────────────────────────────────────────────

class TileResult:
	var pos:     Vector3i
	var mesh_id: int

static func _compute_tile(coord: Vector2i, curve: Curve) -> TileResult:
	var wx := warp_noise.get_noise_2d(coord.x * cfg.warp_freq,
									  coord.y * cfg.warp_freq) * cfg.warp_strength
	var wy := warp_noise.get_noise_2d(coord.x * cfg.warp_freq + 100,
									  coord.y * cfg.warp_freq + 100) * cfg.warp_strength

	var elev := _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)
	elev = curve.sample(elev)
	elev = lerp(0.0, elev, _multi_island_mask(coord))

	var height := int((elev - cfg.height_sea_level) * cfg.height_modifier)

	var result := TileResult.new()
	result.pos = Vector3i(coord.x, height, coord.y)

	var tile := LibraryManager.tiles

	# River override — checked before biome selection
	if cfg.river_enabled and river_tile_set.has(coord):
		result.pos.y = max(height, 1)
		result.mesh_id = _pick_variant(tile, "River", 0.0)
		return result

	# River bank — sand border around rivers, only on land
	if cfg.river_enabled and river_bank_set.has(coord) and elev >= cfg.threshold_beach:
		result.mesh_id = _pick_variant(tile, "Sand", 0.0)
		return result

	if elev < cfg.threshold_ocean:
		result.pos    = Vector3i(coord.x, 0, coord.y)
		result.mesh_id = _pick_variant(tile, "Water", 0.0)
		return result

	if elev < cfg.threshold_beach:
		result.mesh_id = _pick_variant(tile, "Sand", 0.0)
		return result

	var temp  := _fbm(temp_noise,  coord.x, coord.y, cfg.temp_octaves)
	temp  = clampf(temp  - (elev * cfg.temp_altitude_drop), 0.0, 1.0)
	var humid := _fbm(humid_noise, coord.x, coord.y, cfg.humid_octaves)
	var detail := (detail_noise.get_noise_2d(coord.x, coord.y) + 1.0) * 0.5

	var t := temp
	if elev >= cfg.threshold_lowland:
		t = clampf(t - 0.2, 0.0, 1.0)

	result.mesh_id = _biome_tile(t, humid, elev, detail, tile)
	return result


static func _pick_variant(tile: Dictionary, biome: String, detail: float) -> int:
	var variants: Array = tile.get(biome, [])
	if variants.is_empty():
		push_error("WorldGen: no tile registered for biome: " + biome)
		return 0
	var idx := int(detail * variants.size()) % variants.size()
	return variants[idx]


# Data-driven biome selection — iterates cfg.biomes in order, first match wins
static func _biome_tile(temp: float, humid: float, elev: float,
						detail: float, tile: Dictionary) -> int:
	for biome in cfg.biomes:
		if temp  >= biome.temp_min  and temp  < biome.temp_max  and \
		   humid >= biome.humid_min and humid < biome.humid_max and \
		   elev  >= biome.min_elevation and elev < biome.max_elevation:
			return _pick_variant(tile, biome.name, detail)
	push_error("WorldGen: no biome matched temp=%.2f humid=%.2f elev=%.2f" % [temp, humid, elev])
	return 0


# ── Noise helpers ─────────────────────────────────────────────────────────────

static func _fbm(noise: FastNoiseLite, x: float, y: float, octaves: int) -> float:
	var value     := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	for i in octaves:
		value     += noise.get_noise_2d(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	return (value + 1.0) * 0.5

# Raw elevation without island mask — used for river pathfinding to avoid
# circular dependency with _ensure_region
static func _raw_elevation(coord: Vector2i) -> float:
	var wx := warp_noise.get_noise_2d(coord.x * cfg.warp_freq,
									   coord.y * cfg.warp_freq) * cfg.warp_strength
	var wy := warp_noise.get_noise_2d(coord.x * cfg.warp_freq + 100,
									   coord.y * cfg.warp_freq + 100) * cfg.warp_strength
	return _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)

static func _multi_island_mask(coord: Vector2i) -> float:
	var best := 0.0
	var coord_region := _tile_to_region(coord)
	var search_r: int = ceili(float(cfg.island_radius) / cfg.region_size) + 1
	for rx in range(coord_region.x - search_r, coord_region.x + search_r + 1):
		for ry in range(coord_region.y - search_r, coord_region.y + search_r + 1):
			var rd := _ensure_region(Vector2i(rx, ry))
			for center in rd.island_centers:
				var dist := center.distance_to(Vector2(coord.x, coord.y))
				var mask = clamp(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer,
								  dist / cfg.island_radius), 0.0, 1.0)
				best = max(best, mask)
	return best


# ── River generation ──────────────────────────────────────────────────────────

static func _generate_rivers_for_region(rd: RegionData, rng: RandomNumberGenerator) -> void:
	for center in rd.island_centers:
		var starts_found := 0
		var best_raw := 0.0
		var attempts_passing := 0
		var shortest_path := 9999
		var longest_path := 0
		var sample_path_end := Vector2i.ZERO
		var sample_path_end_elev := 0.0
		for _attempt in cfg.river_count_per_island * 8:
			if starts_found >= cfg.river_count_per_island:
				break
			var angle  := rng.randf() * TAU
			var radius := cfg.island_radius * rng.randf_range(0.05, 0.35)
			var candidate := Vector2i(
				int(center.x + cos(angle) * radius),
				int(center.y + sin(angle) * radius)
			)
			var raw: float = _raw_elevation(candidate)
			best_raw = max(best_raw, raw)
			if raw >= cfg.river_min_elevation:
				attempts_passing += 1
				var path := _trace_river(candidate, center)
				shortest_path = min(shortest_path, path.size())
				longest_path = max(longest_path, path.size())
				if path.size() >= 5:
					sample_path_end = path[path.size() - 1]
					sample_path_end_elev = _masked_elev_local(sample_path_end, center)
					rd.river_paths.append(path)
					var r: int = cfg.river_width
					var rb: int = r + cfg.river_bank_width
					for tile_coord in path:
						for dx in range(-rb, rb + 1):
							for dy in range(-rb, rb + 1):
								var d2: int = dx * dx + dy * dy
								var pos_i := Vector2i(tile_coord.x + dx, tile_coord.y + dy)
								if d2 <= r * r:
									river_tile_set[pos_i] = true
								elif d2 <= rb * rb:
									river_bank_set[pos_i] = true
					starts_found += 1
		print("River gen @", center, " rivers=", starts_found, "/", cfg.river_count_per_island,
			  " passed_threshold=", attempts_passing, " best_raw=", snapped(best_raw, 0.001),
			  " path_len=[", shortest_path if shortest_path != 9999 else 0, "..", longest_path, "]",
			  " end=", sample_path_end, " end_elev=", snapped(sample_path_end_elev, 0.001),
			  " mouth_thresh=", cfg.river_mouth_elevation)

static func _trace_river(start: Vector2i, island_center: Vector2) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var current := start
	for _step in 600:
		# Biased downhill: true FBM gradient + soft outward-from-center bias.
		# This ensures monotonic progress toward the coast even when FBM is locally flat.
		var best_coord := current
		var best_score := INF
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nb: Vector2i = Vector2i(current.x + dx, current.y + dy)
				if visited.has(nb):
					continue
				# Score = masked elevation, but penalise moving toward the island center
				var elev: float = _masked_elev_local(nb, island_center)
				var outward_bonus: float = Vector2(nb).distance_to(island_center) \
										   - Vector2(current).distance_to(island_center)
				# outward_bonus > 0 means nb is farther from center → subtract to make it attractive
				var score: float = elev - outward_bonus * 0.003
				if score < best_score:
					best_score = score
					best_coord = nb
		if best_coord == current:
			break
		current = best_coord
		visited[current] = true
		path.append(current)
		# Terminate when visible elevation drops into ocean/beach range.
		# Match _compute_tile's check: ocean if final elev < threshold_ocean.
		var visible_elev: float = _masked_elev_local(current, island_center)
		if visible_elev <= cfg.river_mouth_elevation:
			break
	return path

static func _masked_elev_local(coord: Vector2i, island_center: Vector2) -> float:
	var dist: float = island_center.distance_to(Vector2(coord))
	var mask: float = clampf(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer, dist / cfg.island_radius), 0.0, 1.0)
	return lerp(0.0, _raw_elevation(coord), mask)
