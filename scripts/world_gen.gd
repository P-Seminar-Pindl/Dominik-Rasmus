# world_gen.gd — mesh-based terrain, GPU compute shader driven
extends Node3D

const DEFAULT_PROTO_CFG_PATH := "res://data/world_gen_default.tres"

# ── Exports ───────────────────────────────────────────────────────────────────
@export var cfg: WorldGenConfig = preload("res://data/world_gen_default.tres")
@export var distribution_curve: Curve  # kept for hot-reload hash; not used by shader (shader uses FBM directly)
@export var max_chunk_build_ms_per_frame: float = 120
# The compute shader uses hash-based value noise and skips distribution_curve,
# so its terrain does not match the CPU sampling that placement, props and
# rivers rely on (get_height_at / get_elev01_at). Keep off until the shader
# reproduces the CPU pipeline.
@export var use_gpu_compute: bool = false

@export_group("Performance Debug")
@export var debug_perf: bool = false
## Only log individual chunks that take longer than this (ms). 0 = log all.
@export var debug_perf_slow_chunk_ms: float = 30.0

# ── Special-case tile colors (not driven by BiomeResource) ───────────────────
const COLOR_WATER:     Color = Color(0.05, 0.20, 0.55, 1)
const COLOR_SAND:      Color = Color(0.85, 0.80, 0.55, 1)
const COLOR_RIVER:     Color = Color(0.10, 0.45, 0.90, 1)
const COLOR_HEADWATER: Color = Color(0.18, 0.56, 0.66, 1)

const PROP_SCENE_GRASS_LARGE: PackedScene = preload("res://models/FBX format/grass_large.fbx")
const PROP_SCENE_GRASS_LEAFS: PackedScene = preload("res://models/FBX format/grass_leafs.fbx")
const PROP_SCENE_TREE_OAK: PackedScene = preload("res://models/FBX format/tree_oak.fbx")
const PROP_SCENE_TREE_CONE: PackedScene = preload("res://models/FBX format/tree_cone.fbx")
const PROP_SCENE_TREE_THIN: PackedScene = preload("res://models/FBX format/tree_thin.fbx")
const PROP_SCENE_TREE_TALL: PackedScene = preload("res://models/FBX format/tree_tall.fbx")
const PROP_SCENE_BUSH: PackedScene = preload("res://models/FBX format/plant_bush.fbx")

# ── CPU noise (used only for river tracing / region generation) ───────────────
var elev_noise:   FastNoiseLite = FastNoiseLite.new()
var warp_noise:   FastNoiseLite = FastNoiseLite.new()
var temp_noise:   FastNoiseLite = FastNoiseLite.new()
var humid_noise:  FastNoiseLite = FastNoiseLite.new()

# ── Runtime state ─────────────────────────────────────────────────────────────
var loaded_chunks: Dictionary      = {}
var load_queue:    Array[Vector2i] = []
var queued_set:    Dictionary      = {}

var region_data:    Dictionary = {}
var river_tile_set: Dictionary = {}
var river_bank_set: Dictionary = {}

var chunk_meshes:   Dictionary      = {}
var chunk_props:    Dictionary      = {}
var mesh_cache:     Dictionary      = {}
var mesh_cache_lru: Array[Vector2i] = []

var _mesh_cache_cap: int = 256
var _last_cfg_hash:  int = -1
var _shared_mat:     StandardMaterial3D
var _last_stream_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_render_dist: int = -1
var _chunk_offsets: Array[Vector2i] = []

# ── Perf-debug accumulators ───────────────────────────────────────────────────
var _dbg_frame:        int        = 0
var _dbg_chunks_built: int        = 0
var _dbg_acc:          Dictionary = {}   # fixed_label → total ms this 60-frame window
var _dbg_chunk_steps:  Dictionary = {}   # ordered: label → ms for the current chunk

# ── GPU / compute shader state ────────────────────────────────────────────────
var _rd:           RenderingDevice
var _shader_rid:   RID
var _pipeline_rid: RID
# Per-dispatch buffer RIDs are created/freed each call (small, ~17 KB each)

@onready var _camera: Node = get_node("../Camera3D")


# ── Inner classes ─────────────────────────────────────────────────────────────

class RegionData:
	var island_centers:  Array[Vector2] = []
	var island_climates: Array[Vector2] = []  # (temp_bias, humid_bias) per center, same index
	var river_paths:     Array          = []


# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if not _ensure_cfg_loaded():
		return
	_build_shared_material()
	_init_compute()
	init(cfg)


func init(config: WorldGenConfig) -> void:
	cfg = config

	elev_noise.noise_type = cfg.noise_type
	elev_noise.frequency  = cfg.noise_freq
	elev_noise.seed       = cfg.seed

	warp_noise.noise_type = cfg.noise_type
	warp_noise.frequency  = 1.0
	warp_noise.seed       = cfg.seed + 3

	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency  = cfg.temp_freq
	temp_noise.seed       = cfg.seed + 1

	humid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	humid_noise.frequency  = cfg.humid_freq
	humid_noise.seed       = cfg.seed + 2
	
	var area := PI * cfg.chunk_render_dist * cfg.chunk_render_dist
	_mesh_cache_cap = max(64, int(area) * 4)
	_rebuild_chunk_offsets()

	_clear_all()
	_last_stream_chunk = Vector2i(2147483647, 2147483647)


func _build_shared_material() -> void:
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.vertex_color_use_as_albedo = true
	_shared_mat.vertex_color_is_srgb       = true
	_shared_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_PER_PIXEL


func _init_compute() -> void:
	if not use_gpu_compute:
		return  # CPU mesh builder is the source of truth for now
	# Local device: submit()/sync() are not allowed on the main rendering device.
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("TerrainGen: no RenderingDevice available (need Forward+ or Vulkan)")
		return
	var glsl_path := "res://shaders/terrain_gen.glsl"
	var shader_file: RDShaderFile = load(glsl_path)
	if shader_file == null:
		push_error("TerrainGen: could not load " + glsl_path)
		return

	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(spirv)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	print("[WorldGen] _init_compute: shader_valid=%s  pipeline_valid=%s" % [
		str(_shader_rid.is_valid()), str(_pipeline_rid.is_valid())
	])


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _ensure_cfg_loaded():
		return

	var t0 := Time.get_ticks_usec()
	var current_hash := cfg.get_rid().get_id() * 31 + inst_to_dict(cfg).hash()
	if current_hash != _last_cfg_hash:
		_last_cfg_hash = current_hash
		init(cfg)
	if debug_perf:
		_dbg_acc_add("cfg_hash_check", float(Time.get_ticks_usec() - t0) / 1000.0)

	var ts := Time.get_ticks_usec()
	_stream_chunks()
	if debug_perf:
		_dbg_acc_add("stream_chunks", float(Time.get_ticks_usec() - ts) / 1000.0)

	var chunks_per_frame := cfg.chunks_per_frame
	var frame_start_usec := Time.get_ticks_usec()
	for _i in chunks_per_frame:
		if load_queue.is_empty():
			break
		if max_chunk_build_ms_per_frame > 0.0:
			var elapsed_ms := float(Time.get_ticks_usec() - frame_start_usec) / 1000.0
			if elapsed_ms >= max_chunk_build_ms_per_frame:
				break
		var c: Vector2i = load_queue.pop_front()
		queued_set.erase(c)
		if not loaded_chunks.has(c):
			_load_chunk(c)

	if debug_perf:
		_dbg_frame += 1
		if _dbg_frame >= 60:
			_dbg_flush_summary()
			_dbg_frame = 0


func _ensure_cfg_loaded() -> bool:
	if cfg != null:
		return true

	cfg = load(DEFAULT_PROTO_CFG_PATH) as WorldGenConfig
	if cfg == null:
		push_error("TerrainGen: cfg is null and fallback config failed to load: " + DEFAULT_PROTO_CFG_PATH)
		return false

	return true


# ── Streaming ─────────────────────────────────────────────────────────────────

func _rebuild_chunk_offsets() -> void:
	_cached_render_dist = cfg.chunk_render_dist
	_chunk_offsets.clear()
	var r := cfg.chunk_render_dist
	var r2 := r * r
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy <= r2:
				_chunk_offsets.append(Vector2i(dx, dy))


func _chunk_dist2(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy

func _stream_chunks() -> void:
	if _cached_render_dist != cfg.chunk_render_dist:
		_rebuild_chunk_offsets()

	var anchor: Vector2 = _camera.anchor_2d()
	var player_chunk := _tile_to_chunk(Vector2i(int(anchor.x), int(anchor.y)))
	if player_chunk == _last_stream_chunk:
		return
	_last_stream_chunk = player_chunk

	var desired: Dictionary = {}
	for off in _chunk_offsets:
		desired[player_chunk + off] = true

	var added_new := false
	for c in desired:
		if not loaded_chunks.has(c) and not queued_set.has(c):
			load_queue.append(c)
			queued_set[c] = true
			added_new = true

	if added_new:
		load_queue.sort_custom(func(a, b):
			return _chunk_dist2(player_chunk, a) < _chunk_dist2(player_chunk, b)
		)

	for c in loaded_chunks.keys():
		if not desired.has(c):
			_unload_chunk(c)

	load_queue = load_queue.filter(func(c):
		if not desired.has(c):
			queued_set.erase(c)
			return false
		return true
	)


# ── Chunk load/unload ─────────────────────────────────────────────────────────

func _load_chunk(chunk: Vector2i) -> void:
	var chunk_t0 := Time.get_ticks_usec()
	if debug_perf:
		_dbg_chunk_steps.clear()

	var origin := _chunk_origin(chunk)

	var t := Time.get_ticks_usec()
	var new_region_a := not region_data.has(_tile_to_region(origin))
	_ensure_region(_tile_to_region(origin))
	var new_region_b := not region_data.has(_tile_to_region(Vector2i(origin.x + cfg.chunk_size - 1, origin.y + cfg.chunk_size - 1)))
	_ensure_region(_tile_to_region(Vector2i(
		origin.x + cfg.chunk_size - 1,
		origin.y + cfg.chunk_size - 1
	)))
	if debug_perf:
		var is_new := new_region_a or new_region_b
		_dbg_chunk_steps["ensure_region" + (" [NEW+rivers]" if is_new else "")] = \
				float(Time.get_ticks_usec() - t) / 1000.0

	t = Time.get_ticks_usec()
	var chunk_data := _gather_chunk_centers(origin)
	var chunk_centers:  Array[Vector2] = chunk_data["centers"]
	var chunk_climates: Array[Vector2] = chunk_data["climates"]
	if debug_perf:
		_dbg_chunk_steps["gather_centers [n=%d]" % chunk_centers.size()] = \
				float(Time.get_ticks_usec() - t) / 1000.0

	var mesh: ArrayMesh
	var cache_hit := mesh_cache.has(chunk)
	if cache_hit:
		mesh = mesh_cache[chunk]
		mesh_cache_lru.erase(chunk)
		mesh_cache_lru.append(chunk)
	else:
		if debug_perf:
			_dbg_chunk_steps["build_mesh_gpu"] = 0.0  # placeholder — sub-steps fill in below, value updated after
		t = Time.get_ticks_usec()
		mesh = _build_chunk_mesh_gpu(chunk, origin, chunk_centers, chunk_climates)
		if debug_perf:
			_dbg_chunk_steps["build_mesh_gpu"] = float(Time.get_ticks_usec() - t) / 1000.0
		mesh_cache[chunk] = mesh
		mesh_cache_lru.append(chunk)
		_evict_mesh_cache()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _shared_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	chunk_meshes[chunk] = mi
	loaded_chunks[chunk] = true

	t = Time.get_ticks_usec()
	var prop_root := _spawn_props_for_chunk(chunk, origin, chunk_centers, chunk_climates)
	add_child(prop_root)
	chunk_props[chunk] = prop_root
	if debug_perf:
		_dbg_chunk_steps["spawn_props"] = float(Time.get_ticks_usec() - t) / 1000.0

	if debug_perf:
		_dbg_chunks_built += 1
		var total_ms := float(Time.get_ticks_usec() - chunk_t0) / 1000.0
		_dbg_print_chunk(chunk, total_ms, cache_hit)
		for label in _dbg_chunk_steps:
			_dbg_acc_add(label.strip_edges(), _dbg_chunk_steps[label])
		_dbg_acc_add("TOTAL per chunk", total_ms)


func _unload_chunk(chunk: Vector2i) -> void:
	if chunk_meshes.has(chunk):
		chunk_meshes[chunk].queue_free()
		chunk_meshes.erase(chunk)
	if chunk_props.has(chunk):
		chunk_props[chunk].queue_free()
		chunk_props.erase(chunk)
	loaded_chunks.erase(chunk)


func _evict_mesh_cache() -> void:
	while mesh_cache_lru.size() > _mesh_cache_cap:
		var oldest: Vector2i = mesh_cache_lru[0]
		mesh_cache_lru.remove_at(0)
		if chunk_meshes.has(oldest):
			mesh_cache_lru.append(oldest)
			continue
		mesh_cache.erase(oldest)


func _clear_all() -> void:
	for mi in chunk_meshes.values():
		mi.queue_free()
	chunk_meshes.clear()
	for node in chunk_props.values():
		node.queue_free()
	chunk_props.clear()
	loaded_chunks.clear()
	load_queue.clear()
	queued_set.clear()
	mesh_cache.clear()
	mesh_cache_lru.clear()
	region_data.clear()
	river_tile_set.clear()
	river_bank_set.clear()


# ── GPU mesh building ─────────────────────────────────────────────────────────

func _gather_chunk_centers(origin: Vector2i) -> Dictionary:
	var centers:  Array[Vector2] = []
	var climates: Array[Vector2] = []
	var search_r: int = ceili(float(cfg.island_radius) / cfg.region_size) + 1
	var chunk_region := _tile_to_region(origin)
	for rx in range(chunk_region.x - search_r, chunk_region.x + search_r + 1):
		for ry in range(chunk_region.y - search_r, chunk_region.y + search_r + 1):
			var rd := _ensure_region(Vector2i(rx, ry))
			centers.append_array(rd.island_centers)
			climates.append_array(rd.island_climates)
	return {"centers": centers, "climates": climates}

func _build_chunk_mesh_gpu(chunk: Vector2i, origin: Vector2i, all_centers: Array[Vector2], all_climates: Array[Vector2]) -> ArrayMesh:
	# Fall back to CPU if compute not available
	if not _rd or not _pipeline_rid.is_valid():
		if debug_perf:
			_dbg_chunk_steps["  [!!! CPU FALLBACK — _rd=%s  pipeline_valid=%s]" % [
				str(_rd != null), str(_pipeline_rid.is_valid() if _rd else false)
			]] = 0.0
		return _build_chunk_mesh_cpu(chunk, origin, all_centers)
	if debug_perf:
		_dbg_chunk_steps["  [GPU path OK]"] = 0.0

	var mesh_subdivisions: int = maxi(1, cfg.mesh_subdivisions)
	var verts: int = cfg.chunk_size * mesh_subdivisions + 1
	var vertex_step := 1.0 / float(mesh_subdivisions)
	var vert_count: int = verts * verts
	var vec4_size  := 16

	# One vec4 per island: xy = center position, zw = (temp_bias, humid_bias)
	var center_count := all_centers.size()
	var center_bytes := PackedByteArray()
	center_bytes.resize(max(center_count, 1) * vec4_size)
	center_bytes.fill(0)
	for i in center_count:
		var base := i * vec4_size
		var climate: Vector2 = all_climates[i] if i < all_climates.size() else Vector2(0.5, 0.5)
		center_bytes.encode_float(base,      all_centers[i].x)
		center_bytes.encode_float(base + 4,  all_centers[i].y)
		center_bytes.encode_float(base + 8,  climate.x)
		center_bytes.encode_float(base + 12, climate.y)

	# ── Build biome buffer ────────────────────────────────────────────────────
	# 3 vec4s per biome: [temp_min,temp_max,humid_min,humid_max], [elev_min,elev_max,r,g], [b,0,0,0]
	var biome_count := cfg.biomes.size()
	var biome_bytes := PackedByteArray()
	biome_bytes.resize(max(biome_count, 1) * 3 * vec4_size)
	biome_bytes.fill(0)
	for i in biome_count:
		var bm = cfg.biomes[i]
		var col: Color = bm.color
		var base := i * 3 * vec4_size
		biome_bytes.encode_float(base +  0, bm.temp_min)
		biome_bytes.encode_float(base +  4, bm.temp_max)
		biome_bytes.encode_float(base +  8, bm.humid_min)
		biome_bytes.encode_float(base + 12, bm.humid_max)
		biome_bytes.encode_float(base + 16, bm.min_elevation)
		biome_bytes.encode_float(base + 20, bm.max_elevation)
		biome_bytes.encode_float(base + 24, col.r)
		biome_bytes.encode_float(base + 28, col.g)
		biome_bytes.encode_float(base + 32, col.b)
		biome_bytes.encode_float(base + 36, float(bm.texture_index))
		biome_bytes.encode_float(base + 40, bm.color_variation)

	# ── Build river / bank tile buffers ───────────────────────────────────────
	# Format: ivec4[0].x = count, then entries packed two per ivec4 (.xy / .zw)
	var t_pack := Time.get_ticks_usec()
	var river_bytes := _pack_tile_set(river_tile_set)
	var bank_bytes  := _pack_tile_set(river_bank_set)
	var settings_bytes := _pack_non_river_settings()
	if debug_perf:
		_dbg_chunk_steps["  pack_tile_sets [river=%d  bank=%d]" % [river_tile_set.size(), river_bank_set.size()]] = \
				float(Time.get_ticks_usec() - t_pack) / 1000.0

	# ── Output buffers ────────────────────────────────────────────────────────
	var pos_bytes   := PackedByteArray(); pos_bytes.resize(vert_count * vec4_size); pos_bytes.fill(0)
	var color_bytes := PackedByteArray(); color_bytes.resize(vert_count * vec4_size); color_bytes.fill(0)

	# ── Create RD buffers ─────────────────────────────────────────────────────
	var t_bufs := Time.get_ticks_usec()
	var buf_pos    := _rd.storage_buffer_create(pos_bytes.size(),   pos_bytes)
	var buf_color  := _rd.storage_buffer_create(color_bytes.size(), color_bytes)
	var buf_centers := _rd.storage_buffer_create(center_bytes.size(), center_bytes)
	var buf_biomes  := _rd.storage_buffer_create(biome_bytes.size(),  biome_bytes)
	var buf_river   := _rd.storage_buffer_create(river_bytes.size(),  river_bytes)
	var buf_bank    := _rd.storage_buffer_create(bank_bytes.size(),   bank_bytes)
	var buf_settings := _rd.storage_buffer_create(settings_bytes.size(), settings_bytes)
	if debug_perf:
		_dbg_chunk_steps["  rd_buffer_create"] = float(Time.get_ticks_usec() - t_bufs) / 1000.0

	# ── Uniform set ──────────────────────────────────────────────────────────
	var uniforms: Array[RDUniform] = []
	uniforms.append(_make_storage_uniform(buf_pos,     0))
	uniforms.append(_make_storage_uniform(buf_color,   1))
	uniforms.append(_make_storage_uniform(buf_centers, 2))
	uniforms.append(_make_storage_uniform(buf_biomes,  3))
	uniforms.append(_make_storage_uniform(buf_river,   4))
	uniforms.append(_make_storage_uniform(buf_bank,    5))
	uniforms.append(_make_storage_uniform(buf_settings, 6))
	var uniform_set := _rd.uniform_set_create(uniforms, _shader_rid, 0)

	# ── Push constants ────────────────────────────────────────────────────────
	# Must match the layout(push_constant) struct in the shader exactly.
	# 32 x float32 = 128 bytes (Vulkan minimum guaranteed push constant size)
	var pc := PackedByteArray()
	pc.resize(128)
	pc.fill(0)
	pc.encode_s32(  0, origin.x)
	pc.encode_s32(  4, origin.y)
	pc.encode_s32(  8, cfg.chunk_size * mesh_subdivisions)
	pc.encode_s32( 12, center_count)
	pc.encode_float(16, cfg.noise_freq)
	pc.encode_float(20, cfg.warp_freq)
	pc.encode_float(24, cfg.warp_strength)
	pc.encode_s32( 28, cfg.fbm_octaves)
	pc.encode_float(32, cfg.temp_freq)
	pc.encode_s32( 36, cfg.temp_octaves)
	pc.encode_float(40, cfg.temp_altitude_drop)
	pc.encode_float(44, cfg.humid_freq)
	pc.encode_s32( 48, cfg.humid_octaves)
	pc.encode_float(52, cfg.threshold_ocean)
	pc.encode_float(56, cfg.threshold_beach)
	pc.encode_float(60, cfg.threshold_lowland)
	pc.encode_float(64, cfg.height_sea_level)
	pc.encode_float(68, float(cfg.height_modifier))
	pc.encode_float(72, cfg.island_radius)
	pc.encode_float(76, cfg.mask_inner)
	pc.encode_float(80, cfg.mask_outer)
	pc.encode_s32( 84, cfg.seed)          # elev_seed
	pc.encode_s32( 88, cfg.seed + 3)      # warp_seed
	pc.encode_s32( 92, cfg.seed + 1)      # temp_seed
	pc.encode_s32( 96, cfg.seed + 2)      # humid_seed
	pc.encode_s32(100, 0)                 # river_override_count (unused)
	pc.encode_s32(104, biome_count)
	pc.encode_float(108, vertex_step)
	pc.encode_float(112, cfg.river_carve_coast_strength)
	pc.encode_float(116, cfg.river_carve_headwater_strength)
	pc.encode_float(120, cfg.river_carve_ocean_offset)
	pc.encode_float(124, cfg.river_carve_beach_offset)

	# ── Dispatch ──────────────────────────────────────────────────────────────
	var groups := ceili(float(verts) / 8.0)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_end()
	var t_gpu := Time.get_ticks_usec()
	_rd.submit()
	_rd.sync()
	if debug_perf:
		_dbg_chunk_steps["  submit+sync [groups=%dx%d  verts=%d]" % [groups, groups, verts]] = \
				float(Time.get_ticks_usec() - t_gpu) / 1000.0

	# ── Read back ─────────────────────────────────────────────────────────────
	var t_rb := Time.get_ticks_usec()
	var pos_result   := _rd.buffer_get_data(buf_pos)
	var color_result := _rd.buffer_get_data(buf_color)
	if debug_perf:
		_dbg_chunk_steps["  buffer_readback"] = float(Time.get_ticks_usec() - t_rb) / 1000.0

	# ── Free RD resources ─────────────────────────────────────────────────────
	_rd.free_rid(uniform_set)
	_rd.free_rid(buf_pos)
	_rd.free_rid(buf_color)
	_rd.free_rid(buf_centers)
	_rd.free_rid(buf_biomes)
	_rd.free_rid(buf_river)
	_rd.free_rid(buf_bank)
	_rd.free_rid(buf_settings)

	# ── Assemble ArrayMesh ────────────────────────────────────────────────────
	var t_asm := Time.get_ticks_usec()
	var assembled := _assemble_mesh(pos_result, color_result, verts, vertex_step)
	if debug_perf:
		_dbg_chunk_steps["  assemble_mesh [verts=%d  cc=%d]" % [verts, cfg.catmull_clark_subdivisions]] = \
				float(Time.get_ticks_usec() - t_asm) / 1000.0
	return assembled


func _assemble_mesh(pos_data: PackedByteArray, color_data: PackedByteArray, verts: int, vertex_step: float) -> ArrayMesh:
	var vert_count := verts * verts
	var vertices := PackedVector3Array()
	vertices.resize(vert_count)
	var colors := PackedColorArray()
	colors.resize(vert_count)

	for i in vert_count:
		var b := i * 16
		vertices[i] = Vector3(pos_data.decode_float(b), pos_data.decode_float(b + 4), pos_data.decode_float(b + 8))
		colors[i] = Color(color_data.decode_float(b), color_data.decode_float(b + 4), color_data.decode_float(b + 8), 1.0)

	return _build_mesh_from_grid(vertices, colors, verts, vertex_step)


func _build_mesh_from_grid(vertices: PackedVector3Array, colors: PackedColorArray, verts: int, vertex_step: float) -> ArrayMesh:
	var current_vertices := vertices
	var current_colors := colors
	var current_verts: int = verts
	var current_step: float = vertex_step

	var cc_subdivs: int = maxi(0, cfg.catmull_clark_subdivisions)
	var t_cc := Time.get_ticks_usec()
	for _i in cc_subdivs:
		var cc := _catmull_clark_subdivide_grid(current_vertices, current_colors, current_verts)
		current_vertices = cc["vertices"] as PackedVector3Array
		current_colors = cc["colors"] as PackedColorArray
		current_verts = cc["verts"] as int
		current_step *= 0.5
	if debug_perf and cc_subdivs > 0:
		_dbg_chunk_steps["    catmull_clark x%d [out_verts=%d]" % [cc_subdivs, current_verts]] = \
				float(Time.get_ticks_usec() - t_cc) / 1000.0

	var t_norm := Time.get_ticks_usec()
	var normals := _compute_smoothed_normals(current_vertices, current_verts, current_step)
	if debug_perf:
		_dbg_chunk_steps["    normals [verts=%d  radius=%d]" % [current_verts, cfg.normal_smoothing_radius]] = \
				float(Time.get_ticks_usec() - t_norm) / 1000.0

	var quads := current_verts - 1
	var index_count := quads * quads * 6
	var indices := PackedInt32Array()
	indices.resize(index_count)
	var idx := 0
	for qx in quads:
		for qz in quads:
			var i00 := qx * current_verts + qz
			var i10 := (qx + 1) * current_verts + qz
			var i01 := qx * current_verts + (qz + 1)
			var i11 := (qx + 1) * current_verts + (qz + 1)
			indices[idx + 0] = i00
			indices[idx + 1] = i10
			indices[idx + 2] = i11
			indices[idx + 3] = i00
			indices[idx + 4] = i11
			indices[idx + 5] = i01
			idx += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = current_vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = current_colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _catmull_clark_subdivide_grid(vertices: PackedVector3Array, colors: PackedColorArray, verts: int) -> Dictionary:
	var face_n: int = verts - 1
	var face_count: int = face_n * face_n

	var face_points := PackedVector3Array()
	face_points.resize(face_count)
	var face_colors := PackedColorArray()
	face_colors.resize(face_count)

	for x in face_n:
		for z in face_n:
			var i00: int = x * verts + z
			var i10: int = (x + 1) * verts + z
			var i01: int = x * verts + (z + 1)
			var i11: int = (x + 1) * verts + (z + 1)
			var fi: int = x * face_n + z
			face_points[fi] = (vertices[i00] + vertices[i10] + vertices[i01] + vertices[i11]) * 0.25
			face_colors[fi] = (colors[i00] + colors[i10] + colors[i01] + colors[i11]) * 0.25

	var new_verts: int = face_n * 2 + 1
	var new_count: int = new_verts * new_verts
	var new_vertices := PackedVector3Array()
	new_vertices.resize(new_count)
	var new_colors := PackedColorArray()
	new_colors.resize(new_count)

	for x in verts:
		for z in verts:
			var src_i: int = x * verts + z
			var dst_i: int = (x * 2) * new_verts + (z * 2)
			var p: Vector3 = vertices[src_i]
			var c: Color = colors[src_i]

			var is_boundary := (x == 0 or x == verts - 1 or z == 0 or z == verts - 1)
			if is_boundary:
				var n1 := Vector3.ZERO
				var n2 := Vector3.ZERO
				var c1 := Color(0, 0, 0, 1)
				var c2 := Color(0, 0, 0, 1)
				if x == 0:
					n1 = vertices[x * verts + maxi(z - 1, 0)]
					n2 = vertices[x * verts + mini(z + 1, verts - 1)]
					c1 = colors[x * verts + maxi(z - 1, 0)]
					c2 = colors[x * verts + mini(z + 1, verts - 1)]
				elif x == verts - 1:
					n1 = vertices[x * verts + maxi(z - 1, 0)]
					n2 = vertices[x * verts + mini(z + 1, verts - 1)]
					c1 = colors[x * verts + maxi(z - 1, 0)]
					c2 = colors[x * verts + mini(z + 1, verts - 1)]
				elif z == 0:
					n1 = vertices[maxi(x - 1, 0) * verts + z]
					n2 = vertices[mini(x + 1, verts - 1) * verts + z]
					c1 = colors[maxi(x - 1, 0) * verts + z]
					c2 = colors[mini(x + 1, verts - 1) * verts + z]
				else:
					n1 = vertices[maxi(x - 1, 0) * verts + z]
					n2 = vertices[mini(x + 1, verts - 1) * verts + z]
					c1 = colors[maxi(x - 1, 0) * verts + z]
					c2 = colors[mini(x + 1, verts - 1) * verts + z]

				new_vertices[dst_i] = (p * 4.0 + n1 * 2.0 + n2 * 2.0) * 0.125
				new_colors[dst_i] = (c * 4.0 + c1 * 2.0 + c2 * 2.0) * 0.125
			else:
				var f00_i: int = (x - 1) * face_n + (z - 1)
				var f10_i: int = x * face_n + (z - 1)
				var f01_i: int = (x - 1) * face_n + z
				var f11_i: int = x * face_n + z
				var f_avg: Vector3 = (face_points[f00_i] + face_points[f10_i] + face_points[f01_i] + face_points[f11_i]) * 0.25
				var cf_avg: Color = (face_colors[f00_i] + face_colors[f10_i] + face_colors[f01_i] + face_colors[f11_i]) * 0.25

				var r_avg: Vector3 = (
					(vertices[(x - 1) * verts + z] + p) * 0.5 +
					(vertices[(x + 1) * verts + z] + p) * 0.5 +
					(vertices[x * verts + (z - 1)] + p) * 0.5 +
					(vertices[x * verts + (z + 1)] + p) * 0.5
				) * 0.25
				var cr_avg: Color = (
					(colors[(x - 1) * verts + z] + c) * 0.5 +
					(colors[(x + 1) * verts + z] + c) * 0.5 +
					(colors[x * verts + (z - 1)] + c) * 0.5 +
					(colors[x * verts + (z + 1)] + c) * 0.5
				) * 0.25

				new_vertices[dst_i] = (f_avg + r_avg * 2.0 + p) * 0.25
				new_colors[dst_i] = (cf_avg + cr_avg * 2.0 + c) * 0.25

	for x in face_n:
		for z in verts:
			var dst_i: int = (x * 2 + 1) * new_verts + (z * 2)
			var a_i: int = x * verts + z
			var b_i: int = (x + 1) * verts + z
			var a: Vector3 = vertices[a_i]
			var b: Vector3 = vertices[b_i]
			var ca: Color = colors[a_i]
			var cb: Color = colors[b_i]
			if z > 0 and z < verts - 1:
				var f0_i: int = x * face_n + (z - 1)
				var f1_i: int = x * face_n + z
				new_vertices[dst_i] = (a + b + face_points[f0_i] + face_points[f1_i]) * 0.25
				new_colors[dst_i] = (ca + cb + face_colors[f0_i] + face_colors[f1_i]) * 0.25
			else:
				new_vertices[dst_i] = (a + b) * 0.5
				new_colors[dst_i] = (ca + cb) * 0.5

	for x in verts:
		for z in face_n:
			var dst_i: int = (x * 2) * new_verts + (z * 2 + 1)
			var a_i: int = x * verts + z
			var b_i: int = x * verts + (z + 1)
			var a: Vector3 = vertices[a_i]
			var b: Vector3 = vertices[b_i]
			var ca: Color = colors[a_i]
			var cb: Color = colors[b_i]
			if x > 0 and x < verts - 1:
				var f0_i: int = (x - 1) * face_n + z
				var f1_i: int = x * face_n + z
				new_vertices[dst_i] = (a + b + face_points[f0_i] + face_points[f1_i]) * 0.25
				new_colors[dst_i] = (ca + cb + face_colors[f0_i] + face_colors[f1_i]) * 0.25
			else:
				new_vertices[dst_i] = (a + b) * 0.5
				new_colors[dst_i] = (ca + cb) * 0.5

	for x in face_n:
		for z in face_n:
			var dst_i: int = (x * 2 + 1) * new_verts + (z * 2 + 1)
			var f_i: int = x * face_n + z
			new_vertices[dst_i] = face_points[f_i]
			new_colors[dst_i] = face_colors[f_i]

	return {
		"vertices": new_vertices,
		"colors": new_colors,
		"verts": new_verts,
	}


func _compute_smoothed_normals(vertices: PackedVector3Array, verts: int, vertex_step: float) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	var radius: int = maxi(1, cfg.normal_smoothing_radius)
	var step := vertex_step * float(radius)
	for x in verts:
		for z in verts:
			var i: int = x * verts + z
			var xl: int = maxi(x - radius, 0)
			var xr: int = mini(x + radius, verts - 1)
			var zd: int = maxi(z - radius, 0)
			var zu: int = mini(z + radius, verts - 1)
			var left: float = vertices[xl * verts + z].y
			var right: float = vertices[xr * verts + z].y
			var down: float = vertices[x * verts + zd].y
			var up: float = vertices[x * verts + zu].y
			var normal := Vector3((left - right) / (2.0 * step), 1.0, (down - up) / (2.0 * step)).normalized()
			normals[i] = normal
	return normals


func _make_storage_uniform(buf: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u


func _pack_tile_set(tile_set: Dictionary) -> PackedByteArray:
	# ivec4[0].x = count; entries packed two per subsequent ivec4 (.xy / .zw)
	var coords := tile_set.keys()
	var count  := coords.size()
	var ivec4s := 1 + ceili(float(count) / 2.0)
	var bytes  := PackedByteArray()
	bytes.resize(ivec4s * 16)
	bytes.fill(0)
	bytes.encode_s32(0, count)  # ivec4[0].x = count
	for i in count:
		var base := 16 + (i >> 1) * 16 + (i % 2) * 8
		bytes.encode_s32(base,     coords[i].x)
		bytes.encode_s32(base + 4, coords[i].y)
	return bytes


func _pack_non_river_settings() -> PackedByteArray:
	# 5 vec4s:
	# [0] flatten_power, mountain_start_floor, mountain_end, mountain_power
	# [1] mountain_strength, terrace_steps, terrace_blend_strength, highland_temp_cooling
	# [2] warp_octaves, island_mask_exponent, _, _
	# [3] island_shape_rotation, radial_wave_count, radial_wave_strength, edge_noise_freq
	# [4] edge_noise_octaves, edge_noise_strength, climate_falloff, climate_influence
	var bytes := PackedByteArray()
	bytes.resize(5 * 16)
	bytes.fill(0)
	bytes.encode_float(0,  cfg.terrain_flatten_power)
	bytes.encode_float(4,  cfg.mountain_start_floor)
	bytes.encode_float(8,  cfg.mountain_end)
	bytes.encode_float(12, cfg.mountain_power)
	bytes.encode_float(16, cfg.mountain_strength)
	bytes.encode_float(20, cfg.terrace_steps)
	bytes.encode_float(24, cfg.terrace_blend_strength)
	bytes.encode_float(28, cfg.highland_temp_cooling)
	bytes.encode_float(32, float(cfg.warp_octaves))
	bytes.encode_float(36, cfg.island_mask_exponent)
	bytes.encode_float(48, cfg.island_shape_rotation)
	bytes.encode_float(52, cfg.island_radial_wave_count)
	bytes.encode_float(56, cfg.island_radial_wave_strength)
	bytes.encode_float(60, cfg.island_edge_noise_freq)
	bytes.encode_float(64, float(cfg.island_edge_noise_octaves))
	bytes.encode_float(68, cfg.island_edge_noise_strength)
	bytes.encode_float(72, cfg.island_climate_falloff)
	bytes.encode_float(76, cfg.island_climate_influence)
	return bytes


# ── Prop distribution ─────────────────────────────────────────────────────────

func _get_biome(temp: float, humid: float, elev: float) -> BiomeResource:
	for biome in cfg.biomes:
		if temp  >= biome.temp_min  and temp  < biome.temp_max  and \
		   humid >= biome.humid_min and humid < biome.humid_max and \
		   elev  >= biome.min_elevation and elev < biome.max_elevation:
			return biome
	return null

func _make_prop_entry(scene: PackedScene, density: float, scale_min: float = 0.8, scale_max: float = 1.2, y_offset: float = 0.0, random_rotation: bool = true) -> PropEntry:
	var entry := PropEntry.new()
	entry.scene = scene
	entry.density = density
	entry.scale_min = scale_min
	entry.scale_max = scale_max
	entry.y_offset = y_offset
	entry.random_rotation = random_rotation
	return entry

func _default_green_props_for_biome(biome_name: String) -> Array[PropEntry]:
	match biome_name:
		"Forest":
			return [
				_make_prop_entry(PROP_SCENE_GRASS_LARGE, 0.35, 0.8, 1.4),
				_make_prop_entry(PROP_SCENE_GRASS_LEAFS, 0.45, 0.8, 1.3),
				_make_prop_entry(PROP_SCENE_BUSH, 0.15, 0.9, 1.2),
				_make_prop_entry(PROP_SCENE_TREE_OAK, 0.10, 1.0, 1.5),
				_make_prop_entry(PROP_SCENE_TREE_TALL, 0.08, 1.0, 1.5)
			]
		"Taiga", "Boreal":
			return [
				_make_prop_entry(PROP_SCENE_GRASS_LARGE, 0.25, 0.8, 1.3),
				_make_prop_entry(PROP_SCENE_TREE_CONE, 0.14, 1.0, 1.4),
				_make_prop_entry(PROP_SCENE_TREE_THIN, 0.08, 1.0, 1.4),
				_make_prop_entry(PROP_SCENE_BUSH, 0.08, 0.8, 1.1)
			]
		"Jungle", "Rainforest":
			return [
				_make_prop_entry(PROP_SCENE_GRASS_LARGE, 0.45, 0.8, 1.3),
				_make_prop_entry(PROP_SCENE_GRASS_LEAFS, 0.45, 0.8, 1.4),
				_make_prop_entry(PROP_SCENE_BUSH, 0.18, 0.9, 1.3),
				_make_prop_entry(PROP_SCENE_TREE_TALL, 0.12, 1.1, 1.7),
				_make_prop_entry(PROP_SCENE_TREE_OAK, 0.08, 1.0, 1.4)
			]
		"Wetland", "Shrubland":
			return [
				_make_prop_entry(PROP_SCENE_GRASS_LARGE, 0.45, 0.8, 1.2),
				_make_prop_entry(PROP_SCENE_GRASS_LEAFS, 0.35, 0.8, 1.2),
				_make_prop_entry(PROP_SCENE_BUSH, 0.20, 0.9, 1.1)
			]
		"Steppe":
			return [
				_make_prop_entry(PROP_SCENE_GRASS_LARGE, 0.50, 0.8, 1.2),
				_make_prop_entry(PROP_SCENE_GRASS_LEAFS, 0.35, 0.8, 1.2),
				_make_prop_entry(PROP_SCENE_BUSH, 0.10, 0.9, 1.1)
			]
		_:
			return []


func _spawn_props_for_chunk(
		chunk: Vector2i,
		origin: Vector2i,
		centers: Array[Vector2],
		climates: Array[Vector2]
	) -> Node3D:
	var root := Node3D.new()

	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed ^ (chunk.x * 198491317) ^ (chunk.y * 6542989)

	for tx in cfg.chunk_size:
		for tz in cfg.chunk_size:
			var tile := Vector2i(origin.x + tx, origin.y + tz)
			var coord := Vector2(tile)

			if river_tile_set.has(tile) or river_bank_set.has(tile):
				continue

			var elev01: float = _sample_elev01_from_centersf(coord, centers)
			if elev01 < cfg.threshold_beach:
				continue

			var temp: float  = clampf(_fbm(temp_noise,  coord.x, coord.y, cfg.temp_octaves)  - elev01 * cfg.temp_altitude_drop, 0.0, 1.0)
			var humid: float = _fbm(humid_noise, coord.x, coord.y, cfg.humid_octaves)
			if elev01 >= cfg.threshold_lowland:
				temp = clampf(temp - cfg.highland_temp_cooling, 0.0, 1.0)

			var biome: BiomeResource = _get_biome(temp, humid, elev01)
			if biome == null:
				continue

			var biome_props: Array[PropEntry] = biome.props
			if biome_props.is_empty():
				biome_props = _default_green_props_for_biome(biome.name)
			if biome_props.is_empty():
				continue

			var height: float = _height_from_elev01(elev01)

			for entry: PropEntry in biome_props:
				if entry.scene == null:
					continue
				if rng.randf() >= entry.density:
					continue

				var inst: Node3D = entry.scene.instantiate()
				inst.position = Vector3(
					coord.x + rng.randf_range(-0.4, 0.4),
					height + entry.y_offset,
					coord.y + rng.randf_range(-0.4, 0.4)
				)
				if entry.random_rotation:
					inst.rotation.y = rng.randf_range(0.0, TAU)
				var s: float = rng.randf_range(entry.scale_min, entry.scale_max)
				inst.scale = Vector3(s, s, s)
				root.add_child(inst)

	return root


# ── Public terrain queries (used by placement_manager) ───────────────────────

func get_height_at(tile: Vector2i) -> float:
	return _height_from_elev01(_sample_elev01(tile))


func get_elev01_at(tile: Vector2i) -> float:
	return _sample_elev01(tile)


# Returns the tile/biome name at this cell ("River", "Water", "Sand", or a
# BiomeResource name like "Forest"). Empty string if no biome matches.
func get_tile_name_at(tile: Vector2i) -> String:
	if cfg.river_enabled and river_tile_set.has(tile):
		return "River"
	var elev := _sample_elev01(tile)
	if elev < cfg.threshold_ocean:
		return "Water"
	if elev < cfg.threshold_beach:
		return "Sand"
	var temp := clampf(_fbm(temp_noise, tile.x, tile.y, cfg.temp_octaves) - elev * cfg.temp_altitude_drop, 0.0, 1.0)
	var humid := _fbm(humid_noise, tile.x, tile.y, cfg.humid_octaves)
	if elev >= cfg.threshold_lowland:
		temp = clampf(temp - cfg.highland_temp_cooling, 0.0, 1.0)
	var biome := _get_biome(temp, humid, elev)
	return biome.name if biome != null else ""


# ── CPU fallback mesh builder (used when compute unavailable) ─────────────────

func _build_chunk_mesh_cpu(_chunk: Vector2i, origin: Vector2i, all_centers: Array[Vector2]) -> ArrayMesh:
	var mesh_subdivisions: int = maxi(1, cfg.mesh_subdivisions)
	var quads_per_side: int = cfg.chunk_size * mesh_subdivisions
	var verts: int = quads_per_side + 1
	var vertex_step := 1.0 / float(mesh_subdivisions)
	var elev01s: PackedFloat32Array; elev01s.resize(verts * verts)
	var heights: PackedFloat32Array; heights.resize(verts * verts)
	var cols:   PackedColorArray;   cols.resize(verts * verts)
	var vertices := PackedVector3Array()
	vertices.resize(verts * verts)

	for vx in verts:
		for vz in verts:
			var idx: int = vx * verts + vz
			var coord := Vector2(origin.x + float(vx) * vertex_step, origin.y + float(vz) * vertex_step)
			var elev01 := _sample_elev01_from_centersf(coord, all_centers)
			elev01 = _apply_river_erosion_elev01(Vector2i(floori(coord.x), floori(coord.y)), elev01)
			elev01s[idx] = elev01
			heights[idx] = _height_from_elev01(elev01)
			vertices[idx] = Vector3(coord.x, heights[idx], coord.y)
			cols[idx] = _biome_color_from_elev01f(coord, elev01)

	return _build_mesh_from_grid(vertices, cols, verts, vertex_step)


func _height_from_elev01(elev01: float) -> float:
	if elev01 < cfg.threshold_ocean:
		return 0.0
	return _shape_elevation_for_height(elev01) * cfg.height_modifier


func _shape_elevation_for_height(elev01: float) -> float:
	var land := clampf((elev01 - cfg.height_sea_level) / maxf(1.0 - cfg.height_sea_level, 0.0001), 0.0, 1.0)

	# Compress low/mid elevations into broader buildable terrain.
	var flattened := pow(land, cfg.terrain_flatten_power)

	# Keep rare high elevations dramatic so we still get mountain ranges.
	var mountain_start := maxf(cfg.threshold_lowland, cfg.mountain_start_floor)
	var mountain_mask := smoothstep(mountain_start, cfg.mountain_end, land)
	var mountain_boost := mountain_mask * pow(land, cfg.mountain_power) * cfg.mountain_strength

	var shaped := clampf(flattened + mountain_boost, 0.0, 1.0)

	# Gentle terrace quantization helps the world feel layered instead of uniformly hilly.
	var terrace_steps := maxf(1.0, cfg.terrace_steps)
	var terraced: float = floor(shaped * terrace_steps) / terrace_steps
	var terrace_blend := cfg.terrace_blend_strength * (1.0 - mountain_mask)
	return lerpf(shaped, terraced, terrace_blend)


func _sample_elev01(coord: Vector2i) -> float:
	var wx := _warp_offset(coord.x, coord.y, 0.0) * cfg.warp_strength
	var wy := _warp_offset(coord.x, coord.y, 100.0) * cfg.warp_strength
	var elev := _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)
	if distribution_curve:
		elev = distribution_curve.sample(elev)
	elev = lerp(0.0, elev, _multi_island_mask(coord))
	return elev


func _sample_elev01_from_centers(coord: Vector2i, centers: Array[Vector2]) -> float:
	var wx := _warp_offset(coord.x, coord.y, 0.0) * cfg.warp_strength
	var wy := _warp_offset(coord.x, coord.y, 100.0) * cfg.warp_strength
	var elev := _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)
	if distribution_curve:
		elev = distribution_curve.sample(elev)
	elev = lerp(0.0, elev, _mask_from_centers(coord, centers))
	return elev


func _sample_elev01_from_centersf(coord: Vector2, centers: Array[Vector2]) -> float:
	var wx := _warp_offset(coord.x, coord.y, 0.0) * cfg.warp_strength
	var wy := _warp_offset(coord.x, coord.y, 100.0) * cfg.warp_strength
	var elev := _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)
	if distribution_curve:
		elev = distribution_curve.sample(elev)
	elev = lerp(0.0, elev, _mask_from_centersf(coord, centers))
	return elev


func _mask_from_centers(coord: Vector2i, centers: Array[Vector2]) -> float:
	var best := 0.0
	for center in centers:
		var dist := center.distance_to(Vector2(coord.x, coord.y))
		var mask: float = _shape_island_mask(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer,
								  dist / cfg.island_radius))
		best = max(best, mask)
	return best


func _mask_from_centersf(coord: Vector2, centers: Array[Vector2]) -> float:
	var best := 0.0
	for center in centers:
		var dist := center.distance_to(coord)
		var mask: float = _shape_island_mask(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer,
								  dist / cfg.island_radius))
		best = max(best, mask)
	return best


func _sample_elev(coord: Vector2i) -> float:
	return _height_from_elev01(_sample_elev01(coord))


func _biome_color_from_elev01(coord: Vector2i, elev: float) -> Color:
	if cfg.river_enabled and river_tile_set.has(coord):
		var mask := clampf(_multi_island_mask(coord), 0.0, 1.0)
		return COLOR_RIVER.lerp(COLOR_HEADWATER, mask * 0.65)
	if cfg.river_enabled and river_bank_set.has(coord) and elev >= cfg.threshold_beach:
		return COLOR_SAND.lerp(Color(0.36, 0.67, 0.22, 1), 0.22)
	if elev < cfg.threshold_ocean:
		return COLOR_WATER
	if elev < cfg.threshold_beach:
		return COLOR_SAND

	var temp  := _fbm(temp_noise,  coord.x, coord.y, cfg.temp_octaves)
	temp  = clampf(temp - (elev * cfg.temp_altitude_drop), 0.0, 1.0)
	var humid := _fbm(humid_noise, coord.x, coord.y, cfg.humid_octaves)
	var t := temp
	if elev >= cfg.threshold_lowland:
		t = clampf(t - cfg.highland_temp_cooling, 0.0, 1.0)
	return _biome_tile_color(t, humid, elev)


func _biome_color_from_elev01f(coord: Vector2, elev: float) -> Color:
	var tile_coord := Vector2i(floori(coord.x), floori(coord.y))
	if cfg.river_enabled and river_tile_set.has(tile_coord):
		var mask := clampf(_multi_island_mask(tile_coord), 0.0, 1.0)
		return COLOR_RIVER.lerp(COLOR_HEADWATER, mask * 0.65)
	if cfg.river_enabled and river_bank_set.has(tile_coord) and elev >= cfg.threshold_beach:
		return COLOR_SAND.lerp(Color(0.36, 0.67, 0.22, 1), 0.22)
	if elev < cfg.threshold_ocean:
		return COLOR_WATER
	if elev < cfg.threshold_beach:
		return COLOR_SAND

	var temp  := _fbm(temp_noise,  coord.x, coord.y, cfg.temp_octaves)
	temp  = clampf(temp - (elev * cfg.temp_altitude_drop), 0.0, 1.0)
	var humid := _fbm(humid_noise, coord.x, coord.y, cfg.humid_octaves)
	var t := temp
	if elev >= cfg.threshold_lowland:
		t = clampf(t - cfg.highland_temp_cooling, 0.0, 1.0)
	return _biome_tile_color(t, humid, elev)


func _biome_color(coord: Vector2i, _y: float) -> Color:
	return _biome_color_from_elev01(coord, _sample_elev01(coord))


func _biome_tile_color(temp: float, humid: float, elev: float) -> Color:
	for biome in cfg.biomes:
		if temp  >= biome.temp_min  and temp  < biome.temp_max  and \
		   humid >= biome.humid_min and humid < biome.humid_max and \
		   elev  >= biome.min_elevation and elev < biome.max_elevation:
			return biome.color
	return Color.MAGENTA


# ── Coordinates ───────────────────────────────────────────────────────────────

func _tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / cfg.chunk_size), floori(float(tile.y) / cfg.chunk_size))

func _chunk_origin(chunk: Vector2i) -> Vector2i:
	return Vector2i(chunk.x * cfg.chunk_size, chunk.y * cfg.chunk_size)

func _tile_to_region(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / cfg.region_size), floori(float(tile.y) / cfg.region_size))

func _region_seed(rcoord: Vector2i) -> int:
	return cfg.seed ^ (rcoord.x * 1000003) ^ (rcoord.y * 999983)


# ── Region generation ─────────────────────────────────────────────────────────

func _ensure_region(rcoord: Vector2i) -> RegionData:
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
	var t_var: float = cfg.island_climate_temp_variance
	var h_var: float = cfg.island_climate_humid_variance
	for _i in count:
		rd.island_centers.append(Vector2(
			region_center.x + rng.randf_range(-cfg.region_island_spread, cfg.region_island_spread),
			region_center.y + rng.randf_range(-cfg.region_island_spread, cfg.region_island_spread)
		))
		var t_bias: float = clampf(cfg.island_climate_temp_center + rng.randf_range(-t_var, t_var), 0.0, 1.0)
		var h_bias: float = clampf(cfg.island_climate_humid_center + rng.randf_range(-h_var, h_var), 0.0, 1.0)
		rd.island_climates.append(Vector2(t_bias, h_bias))

	region_data[rcoord] = rd

	if cfg.river_enabled:
		_generate_rivers_for_region(rd, rng)

	return rd


# ── Noise helpers (CPU only — used by river tracing) ─────────────────────────

func _fbm(noise: FastNoiseLite, x: float, y: float, octaves: int) -> float:
	var value     := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	for _i in octaves:
		value     += noise.get_noise_2d(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	return (value + 1.0) * 0.5


func _raw_elevation(coord: Vector2i) -> float:
	var wx := _warp_offset(coord.x, coord.y, 0.0) * cfg.warp_strength
	var wy := _warp_offset(coord.x, coord.y, 100.0) * cfg.warp_strength
	return _fbm(elev_noise, coord.x + wx, coord.y + wy, cfg.fbm_octaves)


func _warp_offset(x: float, y: float, seed_offset: float) -> float:
	var octaves: int = maxi(1, cfg.warp_octaves)
	return _fbm(warp_noise, x * cfg.warp_freq + seed_offset, y * cfg.warp_freq + seed_offset, octaves) * 2.0 - 1.0


func _multi_island_mask(coord: Vector2i) -> float:
	var best := 0.0
	var coord_region := _tile_to_region(coord)
	var search_r: int = ceili(float(cfg.island_radius) / cfg.region_size) + 1
	for rx in range(coord_region.x - search_r, coord_region.x + search_r + 1):
		for ry in range(coord_region.y - search_r, coord_region.y + search_r + 1):
			var rd := _ensure_region(Vector2i(rx, ry))
			for center in rd.island_centers:
				var dist := center.distance_to(Vector2(coord.x, coord.y))
				var mask := _shape_island_mask(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer,
								  dist / cfg.island_radius))
				best = max(best, mask)
	return best


# ── River generation ──────────────────────────────────────────────────────────

func _generate_rivers_for_region(rd: RegionData, rng: RandomNumberGenerator) -> void:
	for center in rd.island_centers:
		var starts_found := 0
		for _attempt in cfg.river_count_per_island * 14:
			if starts_found >= cfg.river_count_per_island:
				break
			var angle  := rng.randf() * TAU
			var radius := cfg.island_radius * rng.randf_range(0.05, 0.35)
			var candidate := Vector2i(
				int(center.x + cos(angle) * radius),
				int(center.y + sin(angle) * radius)
			)
			var masked_start: float = _masked_elev_local(candidate, center)
			if masked_start >= cfg.river_min_elevation:
				var path := _trace_river(candidate, center)
				if path.size() >= cfg.river_min_path_length:
					rd.river_paths.append(path)
					var r: int  = cfg.river_width
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


func _trace_river(start: Vector2i, island_center: Vector2) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var current := start
	var current_elev: float = _masked_elev_local(current, island_center)
	var stop_elev: float = _river_stop_elevation()
	var has_prev_step := false
	var prev_step_dir := Vector2.ZERO
	var max_uphill_step := 0.0
	var max_search_radius: float = cfg.island_radius * cfg.river_search_radius_mult
	var best_partial_path: Array[Vector2i] = path.duplicate()
	var best_partial_elev: float = current_elev
	var forced_climb_steps := 0
	var max_forced_climb_steps := cfg.river_forced_climb_steps

	for _step in cfg.river_max_steps:
		if current_elev <= stop_elev:
			return path
		if _is_ocean_mouth(current, island_center, current_elev):
			return path

		if current_elev < best_partial_elev:
			best_partial_elev = current_elev
			best_partial_path = path.duplicate()

		var found := false
		var best_coord := current
		var best_elev := INF
		var best_score := INF
		var emergency_coord := current
		var emergency_elev := INF
		var emergency_score := INF
		var has_emergency := false

		var outward_dir := (Vector2(current) - island_center).normalized()
		if outward_dir.length_squared() < 0.0001:
			outward_dir = Vector2(1.0, 0.0)
		var tangent_dir := Vector2(-outward_dir.y, outward_dir.x)
		var meander_noise := warp_noise.get_noise_2d(current.x * cfg.river_meander_scale + 913.0, current.y * cfg.river_meander_scale - 271.0)
		var meander_strength := cfg.river_meander_strength
		var desired_dir := (outward_dir + tangent_dir * meander_noise * meander_strength).normalized()
		if has_prev_step:
			desired_dir = desired_dir.lerp(prev_step_dir, clampf(cfg.river_direction_inertia, 0.0, 0.95)).normalized()

		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue

				var nb := Vector2i(current.x + dx, current.y + dy)
				if visited.has(nb):
					continue

				if Vector2(nb).distance_to(island_center) > max_search_radius:
					continue

				var nb_elev: float = _masked_elev_local(nb, island_center)
				var uphill := nb_elev - current_elev

				var current_dist := Vector2(current).distance_to(island_center)
				var nb_dist := Vector2(nb).distance_to(island_center)
				var outward := nb_dist - current_dist
				var center_pull := maxf(0.0, cfg.island_radius - nb_dist) / maxf(cfg.island_radius, 1.0)
				var step_vec := Vector2(nb.x - current.x, nb.y - current.y).normalized()
				var dir_align := step_vec.dot(desired_dir)
				var straight_penalty := 0.0
				if has_prev_step and prev_step_dir.dot(step_vec) > 0.94 and nb_elev > cfg.threshold_ocean:
					straight_penalty = cfg.river_straight_penalty

				# Outward bias remains, but meander alignment and straight-penalty avoid laser-straight rivers.
				var score := nb_elev * 4.5 + uphill * cfg.river_uphill_cost + center_pull * cfg.river_center_pull_bias - outward * cfg.river_outward_bias - dir_align * 0.42 + straight_penalty
				if nb_elev <= cfg.threshold_ocean:
					score -= 3.5

				if (score < emergency_score) or (is_equal_approx(score, emergency_score) and nb_elev < emergency_elev):
					emergency_score = score
					emergency_elev = nb_elev
					emergency_coord = nb
					has_emergency = true

				if uphill > max_uphill_step:
					continue

				if (score < best_score) or (is_equal_approx(score, best_score) and nb_elev < best_elev):
					best_score = score
					best_elev = nb_elev
					best_coord = nb
					found = true

		if not found:
			max_uphill_step = minf(max_uphill_step + 0.005, cfg.river_max_uphill_step)
			if is_equal_approx(max_uphill_step, cfg.river_max_uphill_step) and forced_climb_steps < max_forced_climb_steps:
				var forced_step := _pick_forced_outward_step(current, island_center, visited, max_search_radius)
				if forced_step != current:
					best_coord = forced_step
					best_elev = _masked_elev_local(best_coord, island_center)
					found = true
					forced_climb_steps += 1
				elif has_emergency:
					best_coord = emergency_coord
					best_elev = emergency_elev
					found = true
					forced_climb_steps += 1
			elif is_equal_approx(max_uphill_step, cfg.river_max_uphill_step):
				break
			continue

		current = best_coord
		current_elev = best_elev
		prev_step_dir = Vector2(best_coord.x - path[path.size() - 1].x, best_coord.y - path[path.size() - 1].y).normalized()
		has_prev_step = true
		visited[current] = true
		path.append(current)

	if best_partial_path.size() >= cfg.river_min_path_length:
		return best_partial_path
	return []


func _river_stop_elevation() -> float:
	# Rivers should never continue once they hit sea level.
	return maxf(cfg.river_mouth_elevation, cfg.threshold_ocean )


func _is_ocean_mouth(coord: Vector2i, island_center: Vector2, elev: float) -> bool:
	if elev > cfg.threshold_ocean:
		return false
	var dist_from_center := Vector2(coord).distance_to(island_center)
	if dist_from_center < cfg.island_radius * cfg.mask_outer:
		return false
	var local_mask := _island_mask_local(coord, island_center)
	return local_mask <= 0.2


func _pick_forced_outward_step(
		current: Vector2i,
		island_center: Vector2,
		visited: Dictionary,
		max_search_radius: float
	) -> Vector2i:
	var current_dist := Vector2(current).distance_to(island_center)
	var best := current
	var best_outward := -INF
	var best_elev := INF
	var best_edge_bias := INF

	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nb := Vector2i(current.x + dx, current.y + dy)
			if visited.has(nb):
				continue
			var nb_dist := Vector2(nb).distance_to(island_center)
			if nb_dist > max_search_radius:
				continue
			var outward := nb_dist - current_dist
			var nb_elev := _masked_elev_local(nb, island_center)
			var edge_bias := maxf(0.0, cfg.island_radius - nb_dist)
			if (outward > best_outward) \
				or (is_equal_approx(outward, best_outward) and edge_bias < best_edge_bias) \
				or (is_equal_approx(outward, best_outward) and is_equal_approx(edge_bias, best_edge_bias) and nb_elev < best_elev):
				best_outward = outward
				best_elev = nb_elev
				best_edge_bias = edge_bias
				best = nb

	return best


func _masked_elev_local(coord: Vector2i, island_center: Vector2) -> float:
	var mask: float = _island_mask_local(coord, island_center)
	return lerp(0.0, _raw_elevation(coord), mask)


func _island_mask_local(coord: Vector2i, island_center: Vector2) -> float:
	var dist: float = island_center.distance_to(Vector2(coord))
	return _shape_island_mask(1.0 - smoothstep(cfg.mask_inner, cfg.mask_outer, dist / cfg.island_radius))


func _shape_island_mask(raw_mask: float) -> float:
	var base := clampf(raw_mask, 0.0, 1.0)
	return pow(base, maxf(0.05, cfg.island_mask_exponent))


func _apply_river_erosion_elev01(tile_coord: Vector2i, elev: float) -> float:
	var eroded := elev
	if cfg.river_enabled and river_tile_set.has(tile_coord):
		# Softer carving: keep upstream channels shallow and only carve near river mouths.
		var mask := clampf(_multi_island_mask(tile_coord), 0.0, 1.0)
		var river_floor := lerpf(cfg.threshold_ocean + cfg.river_carve_ocean_offset, cfg.threshold_beach + cfg.river_carve_beach_offset, mask)
		var carve_target := minf(eroded, river_floor)
		var carve_strength := lerpf(cfg.river_carve_coast_strength, cfg.river_carve_headwater_strength, mask)
		eroded = lerpf(eroded, carve_target, carve_strength)
	elif cfg.river_enabled and river_bank_set.has(tile_coord) and eroded >= cfg.threshold_beach:
		# Blend banks gently so shorelines don't look like hard trenches.
		var bank_target := minf(eroded, cfg.threshold_beach + cfg.river_bank_carve_offset)
		eroded = lerpf(eroded, bank_target, cfg.river_bank_carve_strength)
	return eroded


# ── Perf-debug helpers ────────────────────────────────────────────────────────

func _dbg_acc_add(label: String, ms: float) -> void:
	_dbg_acc[label] = _dbg_acc.get(label, 0.0) + ms


func _dbg_print_chunk(chunk: Vector2i, total_ms: float, cache_hit: bool) -> void:
	var slow_tag := "  *** SLOW ***" if total_ms >= debug_perf_slow_chunk_ms else ""
	var lines := PackedStringArray()
	lines.append("[WorldGen] chunk %s  total=%.1f ms%s" % [chunk, total_ms, slow_tag])
	lines.append("  state: cache=%s  queue=%d  loaded=%d  river_tiles=%d  bank_tiles=%d  regions=%d" % [
		"HIT" if cache_hit else "MISS",
		load_queue.size(), loaded_chunks.size(),
		river_tile_set.size(), river_bank_set.size(), region_data.size()
	])
	for label in _dbg_chunk_steps:
		var ms: float = _dbg_chunk_steps[label]
		var bar := ""
		var filled := int(ms / 5.0)  # 1 char per 5 ms
		for _i in mini(filled, 20):
			bar += "█"
		lines.append("  %-50s %6.1f ms  %s" % [label, ms, bar])
	print("\n".join(lines))


func _dbg_flush_summary() -> void:
	if _dbg_acc.is_empty() and _dbg_chunks_built == 0:
		return
	var lines := PackedStringArray()
	lines.append("═══ WorldGen 60-frame summary  (%d chunks built) ═══" % _dbg_chunks_built)
	lines.append("  state: queue=%d  loaded=%d  river_tiles=%d  bank_tiles=%d  regions=%d" % [
		load_queue.size(), loaded_chunks.size(),
		river_tile_set.size(), river_bank_set.size(), region_data.size()
	])
	for label in _dbg_acc:
		lines.append("  %-52s %8.1f ms total  avg=%.1f ms" % [
			label, _dbg_acc[label],
			_dbg_acc[label] / maxf(1.0, float(_dbg_chunks_built))
		])
	print("\n".join(lines))
	_dbg_acc.clear()
	_dbg_chunks_built = 0
