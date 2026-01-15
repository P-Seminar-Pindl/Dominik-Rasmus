extends Node
@onready var map = $GridMap
@onready var cell_pos = Vector3i(0,0,0)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for x in range(1,200):
		for i in range(1,200):
			cell_pos = Vector3i(x,0,i)
			map.set_cell_item(cell_pos,0)

	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	pass
