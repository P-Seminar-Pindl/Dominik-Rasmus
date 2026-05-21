extends Node
class_name AssetInit


static func _add_box_collision(library: MeshLibrary, index: int, size: Vector3) -> void:
	var shape = BoxShape3D.new()
	shape.size = size
	library.set_item_shapes(index, [shape, Transform3D.IDENTITY])


static func add_tile_from_texture(name: String, grid: GridMap, texture: String) -> int:
	var cell_size := Vector3(2, 2, 2)
	var plane = BoxMesh.new()
	plane.size = cell_size
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(texture)
	plane.surface_set_material(0, mat)

	var library = grid.mesh_library
	var index = library.get_last_unused_item_id()
	library.create_item(index)
	library.set_item_name(index, name)
	library.set_item_mesh(index, plane)
	_add_box_collision(library, index, cell_size)
	return index


# Register multiple texture variants for one biome.
# Returns an Array[int] of mesh library indices.
static func add_tile_variants(biome: String, grid: GridMap, textures: Array[String]) -> Array[int]:
	var ids: Array[int] = []
	for i in textures.size():
		var variant_name := biome + "_" + str(i)
		ids.append(add_tile_from_texture(variant_name, grid, textures[i]))
	return ids


static func add_tile_from_mesh(name: String, grid: GridMap, mesh: Mesh, texture: String) -> int:
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(texture)
	mesh.surface_set_material(0, mat)

	var library = grid.mesh_library
	var index = library.get_last_unused_item_id()
	library.create_item(index)
	library.set_item_name(index, name)
	library.set_item_mesh(index, mesh)
	_add_box_collision(library, index, mesh.get_aabb().size)
	return index


static func add_building_from_texture(
		name: String,
		grid: GridMap,
		texture: String,
		data: Dictionary) -> Dictionary:

	var cell_size := Vector3(2, 2, 2)
	var plane = BoxMesh.new()
	plane.size = cell_size

	var mat = StandardMaterial3D.new()
	var tex = load(texture)
	if tex == null:
		push_error("Failed to load texture: " + texture)
		return data
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	plane.surface_set_material(0, mat)

	var library = grid.mesh_library
	var index = library.get_last_unused_item_id()
	library.create_item(index)
	library.set_item_name(index, name)
	library.set_item_mesh(index, plane)
	_add_box_collision(library, index, cell_size)

	data["id"] = index
	return data
