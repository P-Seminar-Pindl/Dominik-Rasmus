extends Camera3D

@onready var camera = $"."
const RAY_LENGTH = 1000.0
var Anchor = Vector3.ZERO
func LookAtAnchor():
	camera.look_at(Anchor)
	
var Buildings = LibraryManager.Buildings
func _input(event):
	LookAtAnchor()
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		var camPos = camera.position
		var normal = camera.project_ray_normal(event.position)
		var origin = camera.project_ray_origin(event.position)
		var to = origin + normal * -camPos.y/normal.y
		
func PlaceBuilding(id, position: Vector3i):
	pass
