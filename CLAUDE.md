# Game — Godot 4.6 Procedural World Generation

## Project Overview
3D tile-based sandbox game on Godot 4.6 (Forward Plus). Infinite procedural world via layered FastNoiseLite noise, rendered with GridMap chunk streaming. Direction: exploration + building/city management.

**Main scene:** `res://scenes/Game.tscn`  
**Autoloads:** `Global` (`scripts/global.gd`), `WorldGen` (`scripts/world_gen.gd`)  
**Entry point:** `scripts/game_manager.gd` — loads assets, calls WorldGen.init(), wires UI

---

## Architecture

### Key Scripts
| File | Class / Extends | Role |
|---|---|---|
| `scripts/world_gen.gd` | extends GridMap, autoload | Static world gen engine — noise, chunk streaming, tile computation |
| `scripts/global.gd` | extends Node, autoload | Singleton state: grid ref, distribution_curve, anchor, placed_buildings |
| `scripts/game_manager.gd` | extends Node3D | Scene init — loads tiles+buildings via LibraryManager, first gen pass, wires UI |
| `scripts/library_manager.gd` | class_name LibraryManager, extends Node | Loads .tres assets into GridMap MeshLibrary; static dicts `tiles{}`, `buildings{}` |
| `scripts/camera.gd` | extends Camera3D | Orbit + pan camera; calls `WorldGen.stream_chunks()` every frame |
| `scripts/asset_init.gd` | class_name AssetInit, all static | Mesh/texture utility helpers used by LibraryManager |

### Resource Templates (`scripts/Templates/`)
| Class | File | Key exports |
|---|---|---|
| `WorldGenConfig` | `world_gen_config.gd` | All gen parameters — see Config section below |
| `TileResource` | `tile_resource.gd` | `name`, `mesh`, `texture`, `size`, `collision_size` |
| `BuildingResource` | `building_resource.gd` | `name`, `texture`, `mesh`, `costs`, `input`, `output`, `workforce` |

---

## World Generation Pipeline

```
WorldGen.init(config)
  └─ Configure 5 noise generators: elev, warp, temp, humid, detail
  └─ generate_island_centers() — seeded RNG, N island positions

Per frame (_process):
  └─ Hash config for hot-reload detection
  └─ Dequeue up to chunks_per_frame → _load_chunk()

Camera (_update_chunks_if_moved):
  └─ WorldGen.stream_chunks(grid, distribution_curve, tile_anchor)

Per tile (_compute_tile):
  wx,wy = warp_noise(coord * warp_freq) * warp_strength   ← domain warp offset
  elev  = FBM(elev_noise, coord+warp, fbm_octaves)
  elev  = distribution_curve.sample(elev)                 ← Curve in Game.tscn
  elev  = lerp(0, elev, island_mask)                      ← fades to 0 outside islands
  temp  = FBM(temp_noise, octaves) − elev × altitude_drop
  humid = FBM(humid_noise, octaves)
  detail = (detail_noise + 1) * 0.5                       ← CELLULAR noise, picks variant

  if   elev < threshold_ocean    → "Water" (flat at y=0)
  elif elev < threshold_beach    → "Sand"
  elif elev ≥ threshold_highland → "Tundra" (cold) or "Stone" (warm)
  else                           → _biome_tile(t, humid, detail)
       [if elev ≥ threshold_lowland, t = clamp(temp−0.2, 0, 1)]
```

**`_biome_tile` hardcoded logic:**
```
temp < 0.2:  humid > 0.5 → "Taiga"   else → "Tundra"
temp < 0.5:  humid > 0.6 → "Forest"  humid > 0.3 → "Grass"  else → "Savanna"
temp ≥ 0.5:  humid > 0.65 → "Jungle"  humid > 0.35 → "Savanna"  else → "Desert"
```

**`_pick_variant(tile_dict, biome_name, detail)`** — looks up `LibraryManager.tiles[biome_name]`, picks index via `detail`. Returns `0` + push_error if not found.

**`_fbm(noise, x, y, octaves)`** — FBM loop, returns `[0, 1]`  
**`_multi_island_mask(coord)`** — smoothstep falloff from each island center, blended with `max()`

---

## Tile System

### Registered Tiles (data/tiles/)
Only 5 tiles currently exist:

| File | name (lookup key) | Texture |
|---|---|---|
| `Water.tres` | `"Water"` | blue_concrete.png |
| `Sand.tres` | `"Sand"` | sand.png |
| `Grass.tres` | `"Grass"` | lime_concrete.png |
| `Forest.tres` | `"Forest"` | green_concrete_powder.png |
| `Stone.tres` | `"Stone"` | stone.png |

### CRITICAL — Naming Rule
`LibraryManager.tiles` is keyed by `TileResource.name` exactly.  
`_pick_variant` looks up biome names directly: `"Water"`, `"Sand"`, `"Grass"`, etc.  
**Tile `name` must match the string used in `_compute_tile` / `_biome_tile` exactly.**

### Missing Tiles (biomes with no registered tile → push_error → mesh 0)
`_biome_tile` can return these names, but NO tile exists for them yet:
- `"Taiga"`, `"Tundra"`, `"Savanna"`, `"Jungle"`, `"Desert"`

Adding a tile for any of these requires only: create `.tres` in `data/tiles/` with matching `name`.

---

## Config (`WorldGenConfig`)

All parameters — defaults from `world_gen_config.gd`, overrides from `data/world_gen_default.tres`:

| Parameter | Default | Active Override | Notes |
|---|---|---|---|
| seed | 137 | 139 | Deterministic |
| island_count | 4 | 5 | |
| island_spread | 300.0 | — | Range for random island placement |
| island_radius | 180.0 | 150.0 | World units |
| mask_inner | 0.2 | 0.215 | Smoothstep inner edge |
| mask_outer | 0.75 | — | Smoothstep outer edge |
| noise_type | SIMPLEX_SMOOTH | — | |
| noise_freq | 0.018 | — | Base elevation frequency |
| warp_strength | 12.0 | — | |
| warp_freq | 0.025 | 0.075 | |
| fbm_octaves | 6 | 3 | Elevation octaves |
| temp_freq | 0.008 | — | |
| temp_octaves | 3 | 4 | |
| **temp_altitude_drop** | **1.2** | **0.29** | **Default is too high — override is critical** |
| humid_freq | 0.011 | — | |
| humid_octaves | 3 | — | |
| threshold_ocean | 0.30 | — | Below → flat water at y=0 |
| threshold_beach | 0.36 | — | Ocean–Beach boundary |
| threshold_lowland | 0.65 | 0.7 | Lowland–Highland boundary |
| threshold_highland | 0.80 | 0.97 | Highland→Stone/Tundra |
| height_modifier | 6 | 12 | Vertical scale |
| height_sea_level | 0.30 | — | y=0 reference elevation |
| chunk_size | ~~1616~~ (typo) | 16 | **Default has typo in source; .tres override fixes it** |
| chunk_render_dist | 8 | 16 | Chunks in each direction |
| chunks_per_frame | 2 | — | Load budget per frame |

---

## Scene Structure

### Game.tscn (main)
```
Game (Node3D) — game_manager.gd
  ├─ height_modifier = 40
  ├─ distribution_curve = Curve [(0,0), (0.818,1), (1,1)]
  ├─ GridMap — world_gen.gd (MeshLibrary populated at runtime)
  ├─ Gui (GUI.tscn — empty Node2D)
  ├─ DirectionalLight3D
  ├─ Camera3D (Camera.tscn) — camera.gd, SensitivityMulti=1.0
  ├─ WorldEnvironment — PanoramaSky (kloofendal_48d_partly_cloudy_puresky.jpg)
  └─ CanvasLayer
      └─ ColorRect (pixelate.gdshader)
          └─ Sidebar (Sidebar.tscn) — sidebar.gd
```

**Note:** `game_manager.gd` has `@onready var render_distance = $Camera3D/RenderDistance` — this node doesn't exist, will produce an error on startup.

---

## Buildings

`BuildingResource` class exists with cost/input/output/workforce exports.  
`LibraryManager.buildings` dict is populated via `populate_buildings_from_folder()`.  
`Global.place_building()` / `remove_building()` / `get_building()` manage `placed_buildings` dict.  
**No building .tres files currently exist** — `data/buildings/` folder does not exist yet.

---

## Prototyping

`prototyping/ProductionLine.gd` (extends GridMap) — prototype BFS logistics network:
- Tile types: `HOUSE_INACTIVE(0)`, `ROAD(1)`, `WAREHOUSE(2)`, `HOUSE_ACTIVE(3)`, `ROAD_ACTIVE(4)`
- `rebuild_network()` — async BFS from warehouses, marks connected roads and houses active
- Not connected to main game yet

---

## Known Issues

| Issue | Location | Notes |
|---|---|---|
| `chunk_size` typo | `world_gen_config.gd:47` | Default is `1616` instead of `16`; `.tres` override of `16` saves it |
| Warp double-scaling | `world_gen.gd:174-176` | Coord is multiplied by `warp_freq` AND `warp_noise.frequency` is set to `warp_freq` in init — applies frequency twice |
| Missing tiles for 5 biomes | `world_gen.gd:232-251` | Taiga, Tundra, Savanna, Jungle, Desert → push_error + mesh 0 |
| Dead `render_distance` onready | `game_manager.gd:8` | `$Camera3D/RenderDistance` doesn't exist in scene |
| `Global.anchor` never updates | `global.gd` | Camera passes its own anchor directly to `stream_chunks`; `Global.anchor` stays Vector2.ZERO |

---

## Adding New Content

### New tile type
1. Create `.tres` in `data/tiles/`, class `TileResource`
2. Set `name` = exactly the string used in `_compute_tile` or `_biome_tile` (e.g. `"Jungle"`)
3. Set `texture` — LibraryManager calls `setup_mesh()` which applies triplanar nearest-filter material
4. `game_manager.gd` loads from `"res://data/tiles/"` on startup — no code changes needed

### New biome region
Add a new string branch to `_biome_tile()` in `world_gen.gd` and create a matching tile.  
Or add new threshold parameters to `WorldGenConfig` for a new elevation band.

### New building
1. Create `.tres` in `data/buildings/`, class `BuildingResource`
2. Set name, mesh, texture, costs/input/output
3. `game_manager.gd` loads from `"res://data/buildings/"` automatically
