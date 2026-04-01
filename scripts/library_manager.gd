extends Node
class_name LibraryManager

static var tiles: Dictionary = {}
static var buildings: Dictionary = {}

func populate_tiles_from_folder(grid: GridMap, folder: String = "res://tiles/") -> void:
	var dir = DirAccess.open(folder)
	if dir == null:
		push_error("Could not open tiles folder: " + folder)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: TileResource = load(folder + file_name)
			if res:
				# WICHTIG: Mesh vorbereiten (Größe + Material)
				res.setup_mesh()

				var index = grid.mesh_library.get_last_unused_item_id()
				grid.mesh_library.create_item(index)
				grid.mesh_library.set_item_name(index, res.name)
				grid.mesh_library.set_item_mesh(index, res.mesh)
				
				# Box Collision
				var shape = BoxShape3D.new()
				shape.size = res.collision_size
				grid.mesh_library.set_item_shapes(index, [shape, Transform3D.IDENTITY])
				
				# Multi-Variant Support vorbereiten
				if tiles.has(res.name):
					tiles[res.name].append(index)
				else:
					tiles[res.name] = [index]
		file_name = dir.get_next()
	dir.list_dir_end()

func populate_buildings_from_folder(grid: GridMap, folder: String = "res://buildings/") -> void:
	var dir = DirAccess.open(folder)
	if dir == null:
		push_error("Could not open buildings folder: " + folder)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: BuildingResource = load(folder + file_name)
			if res:
				var index = grid.mesh_library.get_last_unused_item_id()
				grid.mesh_library.create_item(index)
				grid.mesh_library.set_item_name(index, res.name)
				grid.mesh_library.set_item_mesh(index, res.mesh)
				
				# Box Collision
				var shape = BoxShape3D.new()
				shape.size = res.mesh.get_aabb().size
				grid.mesh_library.set_item_shapes(index, [shape, Transform3D.IDENTITY])
				
				buildings[res.name] = {"index": index, "data": res.data}
		file_name = dir.get_next()
	dir.list_dir_end()
