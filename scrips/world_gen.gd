extends Node
#@onready var map = $GridMap
#@onready var cell_pos = Vector3i(0,0,0)
#@onready var noise = FastNoiseLite.new()
#var move = Vector2i(0,0)
#var mapSize= Vector2i(100,100)
#var circlepos = Vector2i(0,0)
#var Renderdistance = 10
#var circle = Geometry2D
#
#
## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#generate_map(mapSize.x,mapSize.y, move.x,move.y,"A")
	#pass # Replace with function body.
#
#func generate_map(with: int, height: int, movx,movy,type: String):
	#noise.get_image(with,height)
	#noise.offset.x = movx
	#noise.offset.y = movy
	#for x in range(1,with):
		#for i in range(1,height):
			#cell_pos = Vector3i(x,0,i)
			#if type == "1":
				#if circle.is_point_in_circle(Vector2(x,i),circlepos,Renderdistance) == true:
					#if noise.get_noise_2d(x,i) < 0.3:
						#map.set_cell_item(cell_pos,1)
					#else:
						#map.set_cell_item(cell_pos,2)
			#else:
				#if noise.get_noise_2d(x,i) < 0.3:
					#map.set_cell_item(cell_pos,1)
				#else:
					#map.set_cell_item(cell_pos,2)
#
#func remove_map():
	#map.clear()
	#
	#
#
## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#var dirx = Input.get_axis("ui_left","ui_right")
	#var diry = Input.get_axis("ui_up","ui_down")
	#if dirx >= 0:
		#move.x -=1
		#remove_map()
		#generate_map(mapSize.x,mapSize.y,move.x,move.y,"A")
	#if dirx <= 0:
		#move.x +=1
		#remove_map()
		#generate_map(mapSize.x,mapSize.y,move.x,move.y,"A")
	#if diry >= 0:
		#move.y -=1
		#remove_map()
		#generate_map(mapSize.x,mapSize.y,move.x,move.y,"A")
	#if diry <= 0:
		#move.y +=1
		#
		#remove_map()
		#generate_map(mapSize.x,mapSize.y,move.x,move.y,"A")
	#
	#
	#pass
