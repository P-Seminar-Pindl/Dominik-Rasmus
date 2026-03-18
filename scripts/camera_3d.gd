extends Camera3D
@onready var grid = $"../GridMap"
@onready var camera = $"."
const RAY_LENGTH = 1000.0
var Anchor = Vector3.ZERO
@onready var game_manager = get_tree().get_first_node_in_group("game_manager")
func LookAtAnchor():
	camera.look_at(Anchor)
	
var Buildings = LibraryManager.Buildings
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		var origin = project_ray_origin(event.position)
		var normal = project_ray_normal(event.position)
		
		var ground_plane = Plane(Vector3.UP, 0.0)
		var intersection = ground_plane.intersects_ray(origin, normal)
		if intersection:
			PlaceBuilding(grid.local_to_map(intersection))
func PlaceBuilding(position: Vector3):
	if (Global.selected_building == null):
		return
	var grid_pos = grid.local_to_map(position)
	grid.set_cell_item(position, LibraryManager.Tiles.get(Global.selected_building))
	pass
