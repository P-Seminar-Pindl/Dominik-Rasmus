extends Camera3D

@onready var camera = $"."
@onready var grid = $"../GridMap"
const RAY_LENGTH = 1000.0
var Anchor = Vector3.ZERO
func _process(delta: float) -> void:
	#LookAtAnchor()
	pass
var Tile = LibraryManager.Tiles

func LookAtAnchor():
	camera.look_at(Anchor)
func _ready():
	global_position = Vector3(0, 100, 0)  # or wherever your start position should be
	print("Camera world pos: ", global_position)
	print("Grid: ", grid)
var Buildings = LibraryManager.Buildings

func MousePointsAt() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = project_ray_origin(mouse_pos)
	var normal = project_ray_normal(mouse_pos)
		
	var ground_plane = Plane(Vector3.UP, 0.0)
	var intersection = ground_plane.intersects_ray(origin, normal)/2 #dividing by 2 because of offset issues, cause unknown
	return intersection


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		PlaceBuilding(1, MousePointsAt())


func PlaceBuilding(id, position: Vector3):
	var cell = Vector3i(floor(position.x), 0, floor(position.z))
	print("intersection: ", position)
	print("cell: ", cell)
	grid.set_cell_item(cell, Tile["Water"])
