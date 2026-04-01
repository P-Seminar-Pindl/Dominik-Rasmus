extends Node
class_name LibraryManager

static var tiles: Dictionary = {}
static var buildings: Dictionary = {}


func populate_library(grid: GridMap) -> void:
	tiles.Dirt   = AssetInit.add_tile_from_texture("Dirt",   grid, "res://textures/dirt.png")
	tiles.Water  = AssetInit.add_tile_from_texture("Water",  grid, "res://textures/blue_concrete.png")
	tiles.Grass  = AssetInit.add_tile_from_texture("Grass",  grid, "res://textures/lime_concrete.png")
	tiles.Forest = AssetInit.add_tile_from_texture("Forest", grid, "res://textures/green_concrete_powder.png")
	tiles.Sand   = AssetInit.add_tile_from_texture("Sand",   grid, "res://textures/sand.png")
	tiles.Stone  = AssetInit.add_tile_from_texture("Stone",  grid, "res://textures/stone.png")


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
