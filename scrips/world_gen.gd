extends Node
@onready var map = $GridMap
@onready var cell_pos = Vector3i(0,0,0)
@onready var noise = FastNoiseLite.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	generate_map(1000,1000)

	pass # Replace with function body.
func generate_map(with: int, height: int):
	noise.get_image(with,height,)
	for x in range(1,with):
		for i in range(1,height):
			cell_pos = Vector3i(x,0,i)
			if noise.get_noise_2d(x,i) < 0.2:
				map.set_cell_item(cell_pos,0)
			else:
				map.set_cell_item(cell_pos,1)
	
# func remove_map():
	
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	pass
