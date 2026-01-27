extends MeshInstance3D
@onready var cam = $"."
@onready var anchor = Vector3(position.x+5,0,position.z+5)
@onready var anchorDist = 1
@onready var camRot = 0
@onready var camPos = Vector3(0,position.y,0)


# Called when the node enters the scene tree for the first time.
func _ready():
	
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	camRot += 0.02
	camPos.x =sin(camRot) + camPos.x
	camPos.z =cos(camRot) + camPos.z
	position = camPos
	rotation.y = camRot
	pass
