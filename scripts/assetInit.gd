extends Node
class_name assetInit


static func addTileFromTexture(name: String,grid : GridMap, texture) -> int:
	#mesh
	var plane=BoxMesh.new()
	plane.size = Vector3(2,2,2)
	#material
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(texture)
	plane.surface_set_material(0,mat)
	
	#library
	var library = grid.mesh_library
	var index = library.get_last_unused_item_id() 
	library.create_item(index)
	library.set_item_name(index,name)
	library.set_item_mesh(index,plane)
	return index
static func addTileFromMesh(name: String,grid : GridMap, mesh: Mesh, texture):
	#material
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(texture)
	mesh.surface_set_material(0,mat)
	
	#library
	var library = grid.mesh_library
	var index = library.get_last_unused_item_id() 
	library.create_item(index)
	library.set_item_name(index,name)
	library.set_item_mesh(index,mesh)
	return
static func addBuildingFromTexture(
	name: String,
	grid: GridMap,
	texture: String,
	data: Dictionary) -> Dictionary:
	
	# Mesh
	var plane = BoxMesh.new()
	plane.size = Vector3(2,2,2)
	# Material
	var mat = StandardMaterial3D.new()
	var tex = load(texture)
	print(tex)
	if tex == null:
		push_error("Failed to load texture: " + texture)
		return data
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # optional, good for pixel art icons
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	plane.surface_set_material(0, mat)

	# Library
	var library = grid.mesh_library
	var index = library.get_last_unused_item_id()
	library.create_item(index)
	library.set_item_name(index, name)
	library.set_item_mesh(index, plane)

	# ID in Dictionary speichern
	data["id"] = index
	

	return data
	
	
