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

# ── Elevation noise ───────────────────────────────────────────────────────────
@export_group("Elevation Noise")
@export var noise_type:     FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export var noise_freq:     float = 0.018
@export var warp_strength:  float = 12.0
@export var warp_freq:      float = 0.025
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

# ── Chunking ──────────────────────────────────────────────────────────────────
@export_group("Chunking")
@export var chunks_per_frame: int = 2
@export var chunk_size:        int = 16

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
