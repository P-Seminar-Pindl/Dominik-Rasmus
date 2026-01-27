extends Node
@onready var grid = $"../GridMap"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
		addTileFromTexture("test",grid,"res://textures/sand.png")
		for x in range(1,200):
			for i in range(1,200):
				var cell_pos = Vector3i(x,0,i)
				grid.set_cell_item(cell_pos, 3)
				print(grid.get_cell_item(cell_pos))

static func addTileFromTexture(name: String,grid : GridMap, texture):
	#mesh
	var plane=PlaneMesh.new()
	#material
	var mat = StandardMaterial3D.new()
	print(plane.material)
	plane.surface_set_material(0,mat)
	mat.albedo_texture = load(texture)
	print(mat)
	print(plane.material)
	#library
	var library = grid.mesh_library
	var index = library.get_last_unused_item_id() 
	library.create_item(index)
	
	library.set_item_mesh(index,plane)
	print(library.get_item_list())
	print(plane.material)
	print(index)
	
func addTileFromMesh():
	return

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
