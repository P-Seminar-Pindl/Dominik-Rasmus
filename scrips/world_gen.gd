extends Node
@onready var map = $GridMap
@onready var cell_pos = Vector3i(0,0,0)
@onready var noise = FastNoiseLite.new()
var move = Vector2i(0,0)
var mapSize= Vector2i(100,100)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	generate_map(mapSize.x,mapSize.y, move.x,move.y)
	pass # Replace with function body.
	
func generate_map(with: int, height: int, movx,movy):
	noise.get_image(with,height)
	noise.offset.x = movx
	noise.offset.y = movy
	for x in range(1,with):
		for i in range(1,height):
			cell_pos = Vector3i(x,0,i)
			if noise.get_noise_2d(x,i) < 0.5:
				map.set_cell_item(cell_pos,1)
			else:
				map.set_cell_item(cell_pos,2)

func remove_map():
	map.clear()
	
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var dirx = Input.get_axis("ui_left","ui_right")
	var diry = Input.get_axis("ui_up","ui_down")
	if dirx >= 0:
		move.x -=1
		
		remove_map()
		generate_map(mapSize.x,mapSize.y,move.x,move.y)
	if dirx <= 0:
		move.x +=1
		
		remove_map()
		generate_map(mapSize.x,mapSize.y,move.x,move.y)
	if diry >= 0:
		move.y -=1
		
		remove_map()
		generate_map(mapSize.x,mapSize.y,move.x,move.y)
	if diry <= 0:
		move.y +=1
		
		remove_map()
		generate_map(mapSize.x,mapSize.y,move.x,move.y)
	
	
	pass
