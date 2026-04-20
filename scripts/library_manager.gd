extends Node
class_name LibraryManager

static var tiles: Dictionary = {}
static var buildings: Dictionary = {}
static var tile_id_to_name: Dictionary = {}  # mesh_library item id → tile name

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
				tile_id_to_name[index] = res.name
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
				res.setup_mesh()

				var index = grid.mesh_library.get_last_unused_item_id()
				grid.mesh_library.create_item(index)
				grid.mesh_library.set_item_name(index, res.name)
				grid.mesh_library.set_item_mesh(index, res.mesh)

				# Offset mesh so it is centred on the full footprint, not just the anchor cell.
				# GridMap places the mesh origin at the anchor cell centre, so we shift by
				# half of the extra tiles: (fp - 1) * cell_size * 0.5
				var fp := res.footprint_size
				var cell := grid.cell_size
				var mesh_offset := Vector3((fp.x - 1) * cell.x * 0.5, 0.0, (fp.y - 1) * cell.z * 0.5)
				grid.mesh_library.set_item_mesh_transform(index, Transform3D(Basis(), mesh_offset))

				# Collision spans full footprint, also centred on the footprint
				var shape = BoxShape3D.new()
				shape.size = Vector3(fp.x * cell.x, cell.y, fp.y * cell.z)
				var col_offset := Transform3D(Basis(), mesh_offset)
				grid.mesh_library.set_item_shapes(index, [shape, col_offset])

				buildings[res.name] = {"index": index, "resource": res}
		file_name = dir.get_next()
	dir.list_dir_end()
