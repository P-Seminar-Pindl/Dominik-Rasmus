# world_gen.gd
extends GridMap

# ── Noise instances ───────────────────────────────────────────────────────────
static var elev_noise:   FastNoiseLite = FastNoiseLite.new()
static var warp_noise:   FastNoiseLite = FastNoiseLite.new()
static var temp_noise:   FastNoiseLite = FastNoiseLite.new()
static var humid_noise:  FastNoiseLite = FastNoiseLite.new()
static var detail_noise: FastNoiseLite = FastNoiseLite.new()  # selects tile variant

# ── Runtime state ─────────────────────────────────────────────────────────────
static var loaded_chunks:  Dictionary      = {}
static var chunk_tiles:    Dictionary      = {}
static var load_queue:     Array[Vector2i] = []
static var queued_set:     Dictionary      = {}
static var island_centers: Array[Vector2]  = []

static var cfg: WorldGenConfig = preload("res://data/world_gen_default.tres")
static var _last_cfg_hash: int = -1


# ── Init ──────────────────────────────────────────────────────────────────────

static func init(config: WorldGenConfig) -> void:
	cfg = config

	elev_noise.noise_type  = cfg.noise_type
	elev_noise.frequency   = cfg.noise_freq
	elev_noise.seed        = cfg.seed

	warp_noise.noise_type  = cfg.noise_type
	warp_noise.frequency   = cfg.warp_freq
	warp_noise.seed        = cfg.seed + 3

	temp_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency   = cfg.temp_freq
	temp_noise.seed        = cfg.seed + 1

	humid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	humid_noise.frequency  = cfg.humid_freq
	humid_noise.seed       = cfg.seed + 2

	detail_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	detail_noise.frequency  = 0.15   # high freq — picks variants tile-by-tile
	detail_noise.seed       = cfg.seed + 4

	loaded_chunks.clear()
	chunk_tiles.clear()
	load_queue.clear()
	queued_set.clear()

	generate_island_centers()


static func generate_island_centers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed
	island_centers.clear()
	for i in cfg.island_count:
		island_centers.append(Vector2(
			rng.randf_range(-cfg.island_spread, cfg.island_spread),
			rng.randf_range(-cfg.island_spread, cfg.island_spread)
		))


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


# ── Coordinates ───────────────────────────────────────────────────────────────

static func _tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / cfg.chunk_size),
		floori(float(tile.y) / cfg.chunk_size)
	)

static func _chunk_origin(chunk: Vector2i) -> Vector2i:
	return Vector2i(chunk.x * cfg.chunk_size, chunk.y * cfg.chunk_size)


# ── Chunk load/unload ─────────────────────────────────────────────────────────

static func _load_chunk(map: GridMap, chunk: Vector2i, curve: Curve) -> void:
	var origin := _chunk_origin(chunk)
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

	var temp  := _fbm(temp_noise,  coord.x, coord.y, cfg.temp_octaves)
	temp  = clampf(temp  - (elev * cfg.temp_altitude_drop), 0.0, 1.0)

	var humid := _fbm(humid_noise, coord.x, coord.y, cfg.humid_octaves)

	# Detail noise → [0..1], used to pick a variant from the biome's tile array
	var detail := (detail_noise.get_noise_2d(coord.x, coord.y) + 1.0) * 0.5

	var height := int((elev - cfg.height_sea_level) * cfg.height_modifier)

	var result := TileResult.new()
	result.pos = Vector3i(coord.x, height, coord.y)

	var tile := LibraryManager.tiles

	if elev < cfg.threshold_ocean:
		result.pos    = Vector3i(coord.x, 0, coord.y)
		result.mesh_id = _pick_variant(tile, "Water", detail)
		return result

	if elev < cfg.threshold_beach:
		result.mesh_id = _pick_variant(tile, "Sand", detail)
		return result

	if elev >= cfg.threshold_highland:
		if temp < 0.35:
			result.mesh_id = _pick_variant(tile, "Tundra", detail)
		else:
			result.mesh_id = _pick_variant(tile, "Stone", detail)
		return result

	var t := temp
	if elev >= cfg.threshold_lowland:
		t = clampf(t - 0.2, 0.0, 1.0)

	result.mesh_id = _biome_tile(t, humid, detail, tile)
	return result


# Pick a variant from a biome's tile array using the detail value [0..1]
static func _pick_variant(tile: Dictionary, biome: String, detail: float) -> int:
	var variants: Array = tile.get(biome, [])
	if variants.is_empty():
		push_error("WorldGen: no tile registered for biome: " + biome)
		return 0
	var idx := int(detail * variants.size()) % variants.size()
	return variants[idx]


static func _biome_tile(temp: float, humid: float, detail: float, tile: Dictionary) -> int:
	var biome: String
	if temp < 0.2:
		biome = "Taiga" if humid > 0.5 else "Tundra"
	elif temp < 0.5:
		if humid > 0.6:
			biome = "Forest"
		elif humid > 0.3:
			biome = "Grass"
		else:
			biome = "Savanna"
	else:
		if humid > 0.65:
			biome = "Jungle"
		elif humid > 0.35:
			biome = "Savanna"
		else:
			biome = "Desert"

	return _pick_variant(tile, biome, detail)


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

static func _multi_island_mask(coord: Vector2i) -> float:
	var best := 0.0
	for center in island_centers:
		var dist := center.distance_to(Vector2(coord.x, coord.y))
		var mask  = clamp(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer,
						  dist / cfg.island_radius), 0.0, 1.0)
		best = max(best, mask)
	return best
