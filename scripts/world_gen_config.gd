class_name WorldGenConfig
extends Resource

# ── Island layout ─────────────────────────────────────────────────────────────
@export var seed:           int   = 42
@export var island_count:   int   = 5
@export var island_spread:  float = 500.0
@export var island_radius:  float = 200.0

# ── Island shape ──────────────────────────────────────────────────────────────
@export var mask_inner:     float = 0.3   # smoothstep low edge
@export var mask_outer:     float = 0.85  # smoothstep high edge

# ── Noise ─────────────────────────────────────────────────────────────────────
@export var noise_type:     FastNoiseLite.NoiseType    = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export var noise_freq:     float = 1.0
@export var warp_strength:  float = 8.0
@export var warp_freq:      float = 0.05
@export var fbm_octaves:    int   = 4

# ── Biome thresholds (must be ascending 0..1) ─────────────────────────────────
@export var threshold_water:  float = 0.2
@export var threshold_sand:   float = 0.4
@export var threshold_grass:  float = 0.6
@export var threshold_forest: float = 0.8
# anything above forest_threshold → Stone

# ── Height ────────────────────────────────────────────────────────────────────
@export var height_modifier:    int   = 10
@export var height_sea_level:   float = 0.2  # tiles below this sit at y=0

# ── Chunking ──────────────────────────────────────────────────────────────────
@export var chunk_size:         int = 16
@export var chunk_render_dist:  int = 8
