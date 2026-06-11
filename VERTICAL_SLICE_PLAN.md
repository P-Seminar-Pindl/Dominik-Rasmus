# Vertical Slice — Building Placement + Resource Economy

## Context

The game has a fully working terrain renderer (`world_gen.gd`) and a functional building placement preview (`placement_manager.gd`), but no economy — no resources, no production, no feedback loop. The full production + logistics system was prototyped in the old GridMap architecture (`.old/scripts/global.gd`, `.old/scripts/ResourceManager.gd`) but never ported to the new mesh-based renderer.

The goal is a self-contained playable loop: **place buildings → they produce resources over time → resources enable more buildings → settlement grows**. No combat, no save/load, no tech tree — just a working economy that feels alive.

---

## Architecture Overview

```
[Player clicks sidebar]
     ↓
placement_manager.gd     ← selection + preview + validation + cost deduction
     ↓ places building node + fires signal
Global.gd (autoload)     ← tracks placed_buildings dict, runs production tick
     ↓ reads/writes
ResourceManager.gd       ← city-wide stockpile (Wood, Stone, Food, Gold, Workers)
     ↓ emits resources_changed signal
HUD.gd                   ← top bar + building info panel
```

Key difference from old architecture: **Vector2i** tile coords throughout (not Vector3i GridMap cells). No GridMap dependency.

---

## Step 1 — Restore ResourceManager

**File:** `scripts/ResourceManager.gd` (restore from `.old/scripts/ResourceManager.gd`)

Copy verbatim, then extend:
- Add `"Population": 0` and `"Workers": 0` to `stockpile`
- Add `worker_capacity: int = 0` and `workers_used: int = 0` as vars
- Add `signal workers_changed`
- Keep `add()`, `remove()`, `has_enough()`, `get_amount()` unchanged

Register as autoload in `project.godot`: `ResourceManager = "res://scripts/ResourceManager.gd"`

---

## Step 2 — Create Global.gd (production state machine)

**File:** `scripts/Global.gd` (new, adapted from `.old/scripts/global.gd`)

This is the production tick engine. Adapt the old script for the mesh system:

### Key changes from the old version:
- Replace all `Vector3i` with `Vector2i` (anchor coords match `placement_manager.placed_buildings`)
- Remove all `grid.set_cell_item()` calls (no GridMap — visual swaps handled differently)
- Remove `_update_carriers()` / carrier animation entirely (deferred — see Phase 2 polish)
- Remove `LibraryManager` dependency — `placement_manager` already holds loaded resources
- `_cell_world(cell: Vector2i) → Vector3` uses `WorldGen.get_height_at(cell)` for Y

### State machine per production building (keep as-is from `.old/global.gd`):

```
placed_buildings[anchor] = {
  "resource":           ProductionBuildingResource,
  "prod_state":         "idle",          # idle | producing
  "timer":              0.0,
  "storage":            {},              # local output buffer
  "input_buffer":       {},              # local input buffer
  "warehouse_distance": -1,             # road hops; -1 = disconnected
  "workers_assigned":   0,
}
```

### `_process(delta)`:
- Iterate all `placement_manager.placed_buildings`
- Skip non-ProductionBuildingResource
- Skip if `workers_assigned < res.workforce`
- Run idle→producing→done cycle (port from `.old/global.gd` lines 128–143)
- On completion: `ResourceManager.remove(input)`, `ResourceManager.add(output)`
- Stall if output buffer full (use `storage_slots`) or input unavailable

### `rebuild_network()`:
Port the BFS from `.old/global.gd` lines 158–199 but adapted:
- "Road cells" = all `Vector2i` anchors in `placement_manager.placed_buildings` where resource is `RoadBuildingResource`
- "Warehouse cells" = all anchors where resource is `StorageBuildingResource`
- BFS seeds from warehouse footprint borders, walks through road cells, sets `warehouse_distance` on adjacent production buildings
- Call this whenever a building is placed or removed

### Worker update pass (new, simple):
After `rebuild_network()`:
```
total_workers = sum of all House.population_capacity in placed_buildings
workers_needed = sum of all ProductionBuildingResource.workforce in placed_buildings
```
Assign workers in priority order: Sawmill → StoneMine → Farm → Fisherhut → Mill

Register as autoload: `Global = "res://scripts/Global.gd"`

**Global needs a ref to PlacementManager.** Pass it via `_ready()` after `placement_manager` is in scene, or use `get_node("/root/Game/PlacementManager")`.

---

## Step 3 — Extend placement_manager.gd

**File:** `scripts/placement_manager.gd` (extend existing)

### 3a. Cost validation
In `_can_place()`, add a cost check:
```gdscript
for cost in res.costs:
    if not ResourceManager.has_enough(cost.item, cost.amount):
        return false
```

### 3b. Terrain enforcement
Add per-building terrain rules in `_can_place()`. Check via `_world_gen.get_tile_name_at(cell)` (add this method to `world_gen.gd` — returns the biome/tile name string for a cell):

| Building class / name | Required terrain |
|---|---|
| `Sawmill` | ≥1 adjacent `Forest` tile |
| `Farm` | all footprint cells are `Grass` or `Savanna` |
| `Fisherhut` | ≥1 adjacent `Water` tile |
| `StoneMine` | ≥1 adjacent or on-footprint `Stone` tile |
| All others | any non-ocean, non-river tile |

### 3c. Building removal
In `_input()`, add: if RMB with no building selected, raycast to find placed building at cursor tile, call `_remove_building(anchor)`.

```gdscript
func _remove_building(anchor: Vector2i) -> void:
    if not placed_buildings.has(anchor): return
    var data = placed_buildings[anchor]
    data["node"].queue_free()
    var fp = data["resource"].footprint_size
    for dx in range(fp.x):
        for dz in range(fp.y):
            cell_to_anchor.erase(anchor + Vector2i(dx, dz))
    placed_buildings.erase(anchor)
    # Refund 50%
    for cost in data["resource"].costs:
        ResourceManager.add(cost.item, cost.amount / 2)
    building_removed.emit(anchor)
```

### 3d. Cost deduction on place
In `_place_building()`, before placing:
```gdscript
for cost in res.costs:
    ResourceManager.remove(cost.item, cost.amount)
```

### 3e. Signals
Add two signals:
```gdscript
signal building_placed(anchor: Vector2i, resource: BuildingResource)
signal building_removed(anchor: Vector2i)
```
Emit them at end of `_place_building()` and `_remove_building()`. `Global.gd` connects to these to call `rebuild_network()`.

### 3f. Sidebar cost display
In `_build_ui()`, add cost text under each button: e.g. "Wood 10  Stone 5". Color red if ResourceManager can't afford.
Connect `ResourceManager.resources_changed` to refresh button colors every time stockpile changes.

---

## Step 4 — Resource HUD

**File:** `scripts/HUD.gd` (new)  
**Scene:** `scenes/HUD.tscn` (new CanvasLayer)

### Top bar (HBoxContainer, anchored top-center):
One label per resource: `[icon] amount`. Resources: Wood / Stone / Food / Gold / Workers.

On `ResourceManager.resources_changed`:
```gdscript
func _on_resources_changed() -> void:
    for key in _labels:
        _labels[key].text = str(ResourceManager.get_amount(key))
        _labels[key].modulate = Color.RED if ResourceManager.get_amount(key) == 0 else Color.WHITE
```

### Building info panel (Panel, anchored bottom-right, hidden by default):
Show on click on placed building. Contents:
- Building name + description
- Production: input → output, timer progress bar (0–`production_time` seconds)
- Status string: "Producing", "Stalled (no inputs)", "Disconnected", "No workers"
- Demolish button (calls `_remove_building`)

### Settlement tier label (Label, anchored top-left):
```
house_count = count of HouseBuildingResource in placed_buildings
tier = "Outpost" if < 3, "Village" if < 8, "Town" if < 15, "City" if >= 15
```
Update on `building_placed`/`building_removed`.

Add `HUD.tscn` to `Game.tscn` as a child of the root Node3D (it's a CanvasLayer, renders on top).

---

## Step 5 — Building Data (.tres files)

**Directory:** `data/buildings/`

All five core buildings need their `scene` field set to a valid `PackedScene`. Use simple placeholder geometry (colored BoxMesh in a scene) if final models aren't ready. The `placement_manager` already filters `res.scene != null`.

### Required .tres field values for vertical slice:

| File | `scene` | `costs` | `workforce` | `footprint_size` |
|---|---|---|---|---|
| `House.tres` | `scenes/buildings/House.tscn` | Gold×20, Wood×10 | 0 | 2×2 |
| `Sawmill.tres` | `scenes/buildings/Sawmill.tscn` | Gold×30, Wood×5 | 2 | 2×2 |
| `Farm.tres` | `scenes/buildings/Farm.tscn` | Gold×25, Wood×5 | 1 | 3×3 |
| `Warehouse.tres` | `scenes/buildings/Warehouse.tscn` | Gold×40, Stone×10 | 0 | 2×2 |
| `Road.tres` | `scenes/buildings/Road.tscn` | Gold×5 | 0 | 1×1 |

### Production values for ProductionBuildingResource:

| Building | input | output | production_time | storage_slots |
|---|---|---|---|---|
| `Sawmill` | — | Wood×2 | 8s | Wood×10 |
| `Farm` | — | Food×3 | 12s | Food×15 |
| `Fisherhut` | — | Food×2 | 10s | Food×10 |
| `StoneMine` | — | Stone×1 | 15s | Stone×8 |
| `Mill` | Food×2 | Food×3 | 6s | Food×10 |

### HouseBuildingResource:
- `House.tres`: `population_capacity = 4` (adds 4 to worker pool)

---

## Step 6 — world_gen.gd helper method

**File:** `scripts/world_gen.gd`

Add one public method:
```gdscript
func get_tile_name_at(cell: Vector2i) -> String:
    # Returns the biome/tile name at this cell ("Forest", "Water", "Stone", etc.)
    # Reuse existing _compute_tile() logic but return only the name, no visual update.
```
This is needed by `placement_manager._can_place()` for terrain checks. The existing `get_elev01_at()` and `get_height_at()` already exist — this follows the same pattern.

---

## Step 7 — project.godot Autoloads

Add to `[autoload]` section in `project.godot`:
```ini
ResourceManager="*res://scripts/ResourceManager.gd"
Global="*res://scripts/Global.gd"
```

`*` prefix = enabled autoload.

---

## Critical Files Modified

| File | Change |
|---|---|
| `scripts/ResourceManager.gd` | New (restored + extended) |
| `scripts/Global.gd` | New (adapted from `.old/scripts/global.gd`) |
| `scripts/placement_manager.gd` | Extended: cost checks, terrain rules, removal, signals |
| `scripts/world_gen.gd` | Add `get_tile_name_at()` |
| `scripts/HUD.gd` | New |
| `scenes/HUD.tscn` | New |
| `scenes/Game.tscn` | Add HUD as child |
| `data/buildings/*.tres` | Set `scene`, `costs`, production fields |
| `scenes/buildings/*.tscn` | New placeholder building scenes (5 files) |
| `project.godot` | Register autoloads |

---

## Implementation Order

1. `ResourceManager.gd` + autoload registration → stockpile exists
2. Placeholder building scenes (`scenes/buildings/`) + `.tres` `scene` fields → buildings are placeable
3. Cost deduction in `placement_manager._place_building()` → placement costs something
4. `HUD.gd` + `HUD.tscn` → player can see resources
5. `get_tile_name_at()` in `world_gen.gd` → terrain checks possible
6. Terrain rules in `placement_manager._can_place()` → placement is strategic
7. Building removal (RMB, refund) → player can correct mistakes
8. `Global.gd` production state machine → buildings produce resources
9. `Global.gd` BFS network → warehouse connectivity gates delivery
10. Worker system in `Global.gd` → Houses gate production speed
11. Settlement tier label in HUD → visible progression goal

Steps 1–4 give a loop you can demo. Steps 5–8 make it strategic. Steps 9–11 make it a vertical slice.

---

## Deferred (not in this slice)

- Carrier animation (walking figures on roads) — state machine slots exist, just no visual
- Road auto-tiling (active/inactive visual variant swap) — `active_variant` field is ready, wire later
- Building rotation
- Save/load
- Tech tree or upgrades

---

## Verification

1. **Placement works:** Open game, select Sawmill from sidebar, hover — preview turns red over water/ocean tiles, green over forest-adjacent land tiles. Place it — cost deducted from HUD.
2. **Production ticks:** Place Sawmill near no warehouse → status shows "Disconnected". Place Warehouse → `rebuild_network()` fires → Sawmill status shows "Producing". Wait 8s → Wood increases in HUD.
3. **Workers gate production:** Place Sawmill (needs 2 workers), no Houses → "No workers" status. Place House → worker pool +4 → Sawmill starts producing.
4. **Removal refunds:** RMB on placed building → it disappears, 50% cost returns to stockpile.
5. **Settlement tier:** Place 3 houses → label reads "Village".
6. **Terrain rules:** Fisherhut can only be placed adjacent to Water tiles. Farm only on Grass/Savanna.
