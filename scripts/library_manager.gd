extends Node
class_name LibraryManager

# Each biome maps to an Array[int] of mesh library IDs (one per variant).
# Single-texture biomes just have an array of one entry.
static var tiles: Dictionary = {}
static var buildings: Dictionary = {}


func populate_library(grid: GridMap) -> void:
	# ── Single-variant tiles ──────────────────────────────────────────────────
	tiles["Water"]  = [AssetInit.add_tile_from_texture("Water",  grid, "res://textures/blue_concrete.png")]
	tiles["Sand"]   = [AssetInit.add_tile_from_texture("Sand",   grid, "res://textures/sand.png")]
	tiles["Stone"]  = [AssetInit.add_tile_from_texture("Stone",  grid, "res://textures/stone.png")]

	# ── Multi-variant tiles ───────────────────────────────────────────────────
	# Each array entry is a texture path. Add more paths to get more variety.
	# Right now all biomes share the placeholder textures you already have —
	# replace paths here when you have proper art.

	tiles["Grass"] = AssetInit.add_tile_variants("Grass", grid, [
		"res://textures/lime_concrete.png",       # plain grass
		"res://textures/lime_concrete.png",       # TODO: replace with grassland_flowers.png
		"res://textures/lime_concrete.png",       # TODO: replace with grassland_rocky.png
	])

	tiles["Forest"] = AssetInit.add_tile_variants("Forest", grid, [
		"res://textures/green_concrete_powder.png",   # dense forest floor
		"res://textures/green_concrete_powder.png",   # TODO: forest_sparse.png
	])

	tiles["Desert"] = AssetInit.add_tile_variants("Desert", grid, [
		"res://textures/sand.png",                # flat sand
		"res://textures/sand.png",                # TODO: desert_dunes.png
		"res://textures/stone.png",               # TODO: desert_rock.png
	])

	tiles["Savanna"] = AssetInit.add_tile_variants("Savanna", grid, [
		"res://textures/sand.png",                # dry grass
		"res://textures/lime_concrete.png",       # TODO: savanna_grass.png
	])

	tiles["Jungle"] = AssetInit.add_tile_variants("Jungle", grid, [
		"res://textures/green_concrete_powder.png",   # jungle floor
		"res://textures/green_concrete_powder.png",   # TODO: jungle_dense.png
	])

	tiles["Taiga"] = AssetInit.add_tile_variants("Taiga", grid, [
		"res://textures/stone.png",               # taiga ground
		"res://textures/lime_concrete.png",       # TODO: taiga_snow_grass.png
	])

	tiles["Tundra"] = AssetInit.add_tile_variants("Tundra", grid, [
		"res://textures/stone.png",       # frozen ground
		"res://textures/stone.png",               # TODO: tundra_rock.png
	])


func populate_buildings(grid: GridMap, folder: String = "res://json/Flaticons/") -> void:
	var dir = DirAccess.open(folder)
	if dir == null:
		push_error("Could not open buildings folder: " + folder)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = folder + file_name
			var file = FileAccess.open(full_path, FileAccess.READ)
			if file == null:
				push_error("Could not open file: " + full_path)
				file_name = dir.get_next()
				continue

			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			file.close()

			if parse_result != OK:
				push_error("JSON parse error in " + full_path + ": " + json.get_error_message())
				file_name = dir.get_next()
				continue

			var data: Dictionary = json.get_data()
			var id: String = data.get("id", file_name.get_basename())
			var texture: String = data["assets"]["texture"]

			var building_data = {
				"workforce": data.get("workforce", 0),
				"costs":     data.get("costs", {}),
				"input":     data.get("input", {}),
				"output":    data.get("output", {}),
			}

			buildings[id] = AssetInit.add_building_from_texture(id, grid, texture, building_data)

		file_name = dir.get_next()

	dir.list_dir_end()
