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
| `scripts/world_gen.gd` | extends GridMap, autoload | Static world gen engine — noise, chunk streaming, region layer, rivers, tile computation |
| `scripts/global.gd` | extends Node, autoload | Singleton state: grid ref, distribution_curve, anchor, placed_buildings |
| `scripts/game_manager.gd` | extends Node3D | Scene init — loads tiles+buildings via LibraryManager, first gen pass, wires UI |
| `scripts/library_manager.gd` | class_name LibraryManager, extends Node | Loads .tres assets into GridMap MeshLibrary; static dicts `tiles{}`, `buildings{}` |
| `scripts/camera.gd` | extends Camera3D | Orbit + pan camera; calls `WorldGen.stream_chunks()` every frame |
| `scripts/asset_init.gd` | class_name AssetInit, all static | Mesh/texture utility helpers used by LibraryManager |
| `scripts/ResourceManager.gd` | extends Node | City-wide resource stockpile API (`add`, `remove`, `has_enough`, `get_amount`) |

### Resource Templates (`scripts/Templates/`)
| Class | File | Key exports |
|---|---|---|
| `WorldGenConfig` | `world_gen_config.gd` | All gen parameters — see Config section below |
| `BiomeResource` | `biome_resource.gd` | `name`, `temp_min/max`, `humid_min/max`, `min/max_elevation` |
| `TileResource` | `tile_resource.gd` | `name`, `mesh`, `texture`, `size`, `collision_size` |
| `BuildingResource` | `building_resource.gd` | `name`, `texture`, `mesh`, `footprint_size`, `costs`, `workforce`, `active_variant` |
| `HouseBuildingResource` | `house_building_resource.gd` | House-specific building type |
| `RoadBuildingResource` | `road_building_resource.gd` | Road/infrastructure building type |
| `StorageBuildingResource` | `storage_building_resource.gd` | Storage/warehouse building type |
| `ProductionBuildingResource` | `production_building_resource.gd` | `input`, `output`, `production_time`, `storage_slots` |

---

## World Generation Pipeline

```
WorldGen.init(config)
  └─ Configure 5 noise generators: elev, warp (freq=1.0), temp, humid, detail
  └─ Clear region_data, river_tile_set, loaded_chunks

Per frame (_process):
  └─ Hash config for hot-reload detection
  └─ Dequeue up to chunks_per_frame → _load_chunk()

Camera (_update_chunks_if_moved):
  └─ WorldGen.stream_chunks(grid, distribution_curve, tile_anchor)

_load_chunk(chunk):
  └─ _ensure_region() for both chunk corners (lazy island + river generation)
  └─ For each tile → _compute_tile()

Per tile (_compute_tile):
  wx,wy = warp_noise(coord * warp_freq) * warp_strength   ← domain warp offset
  elev  = FBM(elev_noise, coord+warp, fbm_octaves)
  elev  = distribution_curve.sample(elev)
  elev  = lerp(0, elev, _multi_island_mask(coord))        ← fades to 0 outside all islands

  if coord in river_tile_set → "River"
  if elev < threshold_ocean  → "Water" (y=0)
  if elev < threshold_beach  → "Sand"
  else → _biome_tile(temp, humid, elev, detail)           ← data-driven via cfg.biomes
```

**`_multi_island_mask(coord)`** — queries `_ensure_region()` for all nearby regions (search_r = ceil(island_radius / region_size) + 1), accumulates smoothstep mask from every island center in those regions, returns max value.

**`_biome_tile(temp, humid, elev, detail, tile)`** — iterates `cfg.biomes` array in order, returns first `BiomeResource` whose temp/humid/elevation ranges contain the sample. No hardcoded biome names.

**`_fbm(noise, x, y, octaves)`** — FBM loop, returns `[0, 1]`

---

## Region Layer (Infinite World)

Islands are placed lazily per region, not globally at init. Each region is 500×500 tiles.

```
_ensure_region(rcoord: Vector2i) → RegionData:
  seed = cfg.seed XOR (rcoord.x * 1000003) XOR (rcoord.y * 999983)
  count = randi_range(0, islands_per_region)
  place island_centers within ±region_island_spread of region center
  → call _generate_rivers_for_region()

_generate_rivers_for_region(rd, rng):
  for each island: sample candidate start points near highlands
  → _trace_river(start): gradient descent until beach/ocean level
  → store path tiles in river_tile_set (global Dict for O(1) lookup)
```

**Static vars added to `world_gen.gd`:**
- `region_data: Dictionary` — `Vector2i → RegionData`
- `river_tile_set: Dictionary` — `Vector2i → true`

**Inner class `RegionData`:** `island_centers: Array[Vector2]`, `river_paths: Array`

---

## Tile System

### Registered Tiles (data/tiles/)

| File | name (lookup key) | Texture |
|---|---|---|
| `Water.tres` | `"Water"` | blue_concrete.png |
| `Sand.tres` | `"Sand"` | sand.png |
| `Grass.tres` | `"Grass"` | lime_concrete.png |
| `Forest.tres` | `"Forest"` | green_concrete_powder.png |
| `Stone.tres` | `"Stone"` | stone.png |
| `Tundra.tres` | `"Tundra"` | stone.png (placeholder) |
| `Taiga.tres` | `"Taiga"` | dirt.png (placeholder) |
| `Savanna.tres` | `"Savanna"` | sand.png (placeholder) |
| `Jungle.tres` | `"Jungle"` | green_concrete_powder.png (placeholder) |
| `Desert.tres` | `"Desert"` | sand.png (placeholder) |
| `River.tres` | `"River"` | blue_concrete.png (placeholder) |

### CRITICAL — Naming Rule
`LibraryManager.tiles` is keyed by `TileResource.name` exactly.  
`BiomeResource.name` must match a registered tile name.  
**Tile `name` must match the `BiomeResource.name` used in `cfg.biomes` exactly.**

---

## Biome System

Biomes are defined as `.tres` files in `data/biomes/` using `BiomeResource`. The array `cfg.biomes` in `world_gen_default.tres` controls which biomes are active and in what priority order (first match wins).

### Registered Biomes (data/biomes/)

| File | name | temp range | humid range | elev range | Notes |
|---|---|---|---|---|---|
| `Tundra_highland.tres` | `"Tundra"` | 0.0–0.35 | 0.0–1.0 | 0.8–1.0 | cold peaks |
| `Stone_highland.tres` | `"Stone"` | 0.35–1.0 | 0.0–1.0 | 0.8–1.0 | warm peaks |
| `Tundra.tres` | `"Tundra"` | 0.0–0.2 | 0.0–0.5 | 0.0–1.0 | cold dry lowland |
| `Taiga.tres` | `"Taiga"` | 0.0–0.2 | 0.5–1.0 | 0.0–1.0 | cold wet |
| `Savanna.tres` | `"Savanna"` | 0.2–0.5 | 0.0–0.3 | 0.0–1.0 | temperate dry |
| `Grass.tres` | `"Grass"` | 0.2–0.5 | 0.3–0.6 | 0.0–1.0 | temperate moderate |
| `Forest.tres` | `"Forest"` | 0.2–0.5 | 0.6–1.0 | 0.0–1.0 | temperate wet |
| `Desert.tres` | `"Desert"` | 0.5–1.0 | 0.0–0.35 | 0.0–1.0 | hot dry |
| `Savanna_hot.tres` | `"Savanna"` | 0.5–1.0 | 0.35–0.65 | 0.0–1.0 | hot moderate |
| `Jungle.tres` | `"Jungle"` | 0.5–1.0 | 0.65–1.0 | 0.0–1.0 | hot wet |

Highland biomes (Tundra_highland, Stone_highland) come first in the array because `min_elevation = 0.8` restricts them; they won't match low-elevation tiles regardless of order.

---

## Config (`WorldGenConfig`)

All parameters — defaults from `world_gen_config.gd`, overrides from `data/world_gen_default.tres`:

| Parameter | Default | Active Override | Notes |
|---|---|---|---|
| seed | 137 | 139 | Deterministic |
| island_count | 4 | 5 | Legacy — unused by region system |
| island_spread | 300.0 | — | Legacy — unused by region system |
| island_radius | 180.0 | 150.0 | Mask radius per island (still used) |
| mask_inner | 0.2 | 0.215 | Smoothstep inner edge |
| mask_outer | 0.75 | — | Smoothstep outer edge |
| noise_freq | 0.018 | — | Base elevation frequency |
| warp_strength | 12.0 | — | |
| warp_freq | 0.025 | 0.075 | Manual scaling; warp_noise.frequency = 1.0 |
| fbm_octaves | 6 | 3 | Elevation octaves |
| **temp_altitude_drop** | **1.2** | **0.29** | **Default too high — override is critical** |
| threshold_ocean | 0.30 | — | Below → flat water at y=0 |
| threshold_beach | 0.36 | — | Ocean–Beach boundary |
| threshold_lowland | 0.65 | 0.7 | Lowland–Highland boundary |
| threshold_highland | 0.80 | 0.97 | Used as min_elevation in highland biomes |
| height_modifier | 6 | 12 | Vertical scale |
| chunk_size | 16 | 16 | Tiles per chunk side |
| chunk_render_dist | 8 | 64 | Chunks in each direction |
| chunks_per_frame | 2 | 30 | Load budget per frame |
| **biomes** | `[]` | 10 biomes | **Array[BiomeResource] — must be assigned** |
| region_size | 500 | 500 | Tiles per region side |
| islands_per_region | 5 | 5 | Max islands per region |
| region_island_spread | 180.0 | 180.0 | Max offset from region center |
| river_enabled | true | true | |
| river_min_elevation | 0.65 | 0.65 | River start height (raw FBM) |
| river_mouth_elevation | 0.36 | 0.36 | River stops at beach level |
| river_count_per_island | 2 | 2 | Rivers attempted per island |

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
`Global.place_building()` / `remove_building()` / `get_building()` manage `placed_buildings` and `cell_to_anchor` occupancy maps.  
Building assets are now present in `data/buildings/` and loaded at startup.

### Registered Buildings (data/buildings/)
| File | name | Notes |
|---|---|---|
| `House.tres` | `House` | residential building resource |
| `Road.tres` | `Road` | road infrastructure |
| `Road_Active.tres` | `Road_Active` | active variant for connected roads |
| `Sawmill.tres` | `Sawmill` | production building resource |
| `Warehouse.tres` | `Warehouse` | storage / logistics hub |
| `Farm.tres` | `Farm` | food production |
| `Fisherhut.tres` | `Fisherhut` | coastal food production |
| `StoneMine.tres` | `StoneMine` | stone extraction |
| `Mill.tres` | `Mill` | grain → flour processing |

### Building systems
- Building placement is selected through the sidebar and placed via camera input.  
- `Global.selected_building` tracks the current building choice.  
- Building footprints are enforced using `footprint_size`, and every occupied cell maps back to the anchor origin cell.
- Production buildings use `ProductionBuildingResource` and run per-frame logic in `Global._process()`.
- The production loop consumes local inputs, fills local output buffers, and stalls if buffers are full.
- The logistics loop dispatches carriers to fetch inputs or deliver outputs via warehouse-connected road networks.

---

## Economy & Logistics

`ResourceManager.gd` maintains a city-wide resource stockpile with starting amounts for `Gold`, `Wood`, `Planks`, `Stone`, and `Food`.  
`Global` integrates production and logistics so placed `ProductionBuildingResource` instances can:
- consume inputs from local storage,  
- produce outputs over `production_time`,  
- store outputs in local buffers defined by `storage_slots`,  
- dispatch carriers for delivery/fetching when connected to a warehouse.

The system tracks `prod_state` and `logistics_state` per building, and uses `warehouse_distance` to determine whether a building is connected to a warehouse.

---

## Prototyping

`prototyping/ProductionLine.gd` (extends GridMap) — prototype BFS logistics network:
- `rebuild_network()` — async BFS from warehouses, marks connected roads and houses active
- Not connected to main game yet

---

## Known Issues

| Issue | Location | Notes |
|---|---|---|
| Dead `render_distance` onready | `game_manager.gd:8` | `$Camera3D/RenderDistance` doesn't exist in scene |
| `Global.anchor` never updates | `global.gd` | Camera passes its own anchor directly to `stream_chunks`; `Global.anchor` stays Vector2.ZERO |
| Biome tile placeholders | `data/tiles/` | Tundra/Taiga/Savanna/Jungle/Desert/River reuse existing textures — need dedicated art |
| `world_gen_default.tres` biome array | `data/world_gen_default.tres` | Hand-written .tres typed array syntax may need Godot editor re-save on first open |

---

## Adding New Content

### New tile type
1. Create `.tres` in `data/tiles/`, class `TileResource`
2. Set `name` = exactly the string used in any `BiomeResource.name` (e.g. `"Jungle"`)
3. Set `texture` — LibraryManager calls `setup_mesh()` which applies triplanar nearest-filter material
4. `game_manager.gd` loads from `"res://data/tiles/"` on startup — no code changes needed

### New biome
1. Create `.tres` in `data/biomes/`, class `BiomeResource`
2. Set `name` to match a registered tile name, set temp/humid/elevation ranges
3. Add the `.tres` to `cfg.biomes` array in `data/world_gen_default.tres` (order matters — first match wins)
4. No code changes needed

### New building
1. Create `.tres` in `data/buildings/`, class `BuildingResource` or a subclass
2. Set `name`, `mesh`, `texture`, `costs`, `footprint_size`, and `workforce` as needed
3. For production buildings, also set `input`, `output`, `production_time`, and `storage_slots`
4. Optionally set `active_variant` for alternate connected states
5. `game_manager.gd` loads from `"res://data/buildings/"` automatically
