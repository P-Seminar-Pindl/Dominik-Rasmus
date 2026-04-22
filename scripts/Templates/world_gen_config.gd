class_name WorldGenConfig
extends Resource

const BiomeResource = preload("res://scripts/Templates/biome_resource.gd")

# ── Island layout ─────────────────────────────────────────────────────────────
@export_group("Island Layout")
@export var seed:                 int   = 137
@export var island_radius:        float = 180.0
@export var islands_per_region:   int   = 3
@export var region_island_spread: float = 180.0
@export var mask_inner:     float = 0.2
@export var mask_outer:     float = 0.75
@export var island_shape_rotation:      float = 0.0
@export var island_radial_wave_count:   float = 0.0
@export var island_radial_wave_strength: float = 0.0
@export var island_edge_noise_freq:     float = 0.0
@export var island_edge_noise_octaves:  int   = 1
@export var island_edge_noise_strength: float = 0.0

# ── Elevation noise ───────────────────────────────────────────────────────────
@export_group("Elevation Noise")
@export var noise_type:     FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export var noise_freq:     float = 0.007
@export var warp_strength:  float = 12.0
@export var warp_freq:      float = 0.025
@export var warp_octaves:   int   = 2
@export var fbm_octaves:    int   = 6

# ── Temperature noise ─────────────────────────────────────────────────────────
@export_group("Temperature Noise")
@export var temp_freq:          float = 0.008
@export var temp_octaves:       int   = 3
@export var temp_altitude_drop: float = 1.2

# ── Humidity noise ────────────────────────────────────────────────────────────
@export_group("Humidity Noise")
@export var humid_freq:    float = 0.011
@export var humid_octaves: int   = 3

# ── Elevation thresholds (0..1, ascending) ────────────────────────────────────
@export_group("Elevation Thresholds")
@export var threshold_ocean:    float = 0.30
@export var threshold_beach:    float = 0.36
@export var threshold_lowland:  float = 0.65
@export var threshold_highland: float = 0.80

# ── Height ────────────────────────────────────────────────────────────────────
@export_group("Height")
@export var height_modifier:  int   = 6
@export var height_sea_level: float = 0.30
@export var terrain_flatten_power:      float = 1.8
@export var mountain_start_floor:       float = 0.62
@export var mountain_end:               float = 0.92
@export var mountain_power:             float = 2.6
@export var mountain_strength:          float = 0.55
@export var terrace_steps:              float = 7.0
@export var terrace_blend_strength:     float = 0.33
@export var island_mask_exponent:       float = 1.0

@export_group("Biome Shaping")
@export var highland_temp_cooling:      float = 0.2

# ── Chunking ──────────────────────────────────────────────────────────────────
@export_group("Chunking")
@export var chunks_per_frame: int = 2
@export var chunk_size:        int = 16
@export var mesh_subdivisions: int = 1
@export var catmull_clark_subdivisions: int = 0
@export var normal_smoothing_radius: int = 2

@export var chunk_render_dist: int = 8

# ── Biomes ────────────────────────────────────────────────────────────────────
@export_group("Biomes")
@export var biomes: Array[BiomeResource] = []

# ── Region layer ──────────────────────────────────────────────────────────────
@export_group("Region Layer")
@export var region_size: int = 500

# ── Rivers ────────────────────────────────────────────────────────────────────
@export_group("Rivers")
@export var river_enabled:           bool  = true
@export var river_min_elevation:     float = 0.65
@export var river_mouth_elevation:   float = 0.36
@export var river_count_per_island:  int   = 2
@export var river_width:              int   = 2
@export var river_bank_width:         int   = 1
@export var river_min_path_length:    int   = 6
@export var river_max_steps:          int   = 1200
@export var river_search_radius_mult: float = 2.6
@export var river_forced_climb_steps: int   = 220
@export var river_max_uphill_step:    float = 0.03
@export var river_meander_scale:      float = 0.037
@export var river_meander_strength:   float = 0.6
@export var river_direction_inertia:  float = 0.45
@export var river_outward_bias:       float = 1.05
@export var river_center_pull_bias:   float = 1.35
@export var river_straight_penalty:   float = 0.22
@export var river_uphill_cost:        float = 105.0
@export var river_carve_coast_strength:    float = 0.78
@export var river_carve_headwater_strength: float = 0.36
@export var river_carve_ocean_offset:       float = 0.02
@export var river_carve_beach_offset:       float = 0.04
@export var river_bank_carve_offset:        float = 0.05
@export var river_bank_carve_strength:      float = 0.25
@export var threshold_ocean_offset: float = -0.25
