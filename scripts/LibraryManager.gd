extends Node
class_name LibraryManager
static var Tiles = {}
static var Buildings = {}
func PopulateLibrary(grid): 
	Tiles.Dirt =assetInit.addTileFromTexture("Dirt",grid,"res://textures/dirt.png")
	Tiles.Water =assetInit.addTileFromTexture("Water",grid,"res://textures/blue_concrete.png")
	Tiles.Grass =assetInit.addTileFromTexture("Grass",grid,"res://textures/lime_concrete.png")
	Tiles.Forest =assetInit.addTileFromTexture("Forest",grid,"res://textures/green_concrete_powder.png")
	Tiles.Sand =assetInit.addTileFromTexture("Sand",grid,"res://textures/sand.png")
	Tiles.Stone =assetInit.addTileFromTexture("Stone",grid,"res://textures/stone.png")
func PopulateBuildings(grid: GridMap, folder: String = "res://buildings/") -> void:
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

			# Build a clean data dict to pass through
			var building_data = {
				"workforce": data.get("workforce", 0),
				"costs":     data.get("costs", {}),
				"input":     data.get("input", {}),
				"output":    data.get("output", {}),
			}

			Buildings[id] = assetInit.addBuildingFromTexture(id, grid, texture, building_data)

		file_name = dir.get_next()

	dir.list_dir_end()
