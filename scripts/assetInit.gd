extends Node
class_name assetInit
static func addTileFromTexture(name: String,grid : GridMap, texture) -> int:
	#mesh
	var plane=PlaneMesh.new()
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
	var plane = PlaneMesh.new()

	# Material
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(texture)
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
	
	
