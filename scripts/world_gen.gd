extends Node
class_name WorldGen
@onready var map = $"."
var move = Vector2i(0,0)
var mapSize= Vector2i(100,100)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass # Replace with function body.
	
static func generate_map(grid: GridMap,with: int, height: int, offsetx,offsety, distribution_curve):
	#Variable Space
	var noise = FastNoiseLite.new()
	var cell_pos = Vector3i(0,0,0)
	noise.get_image(with,height)
	noise.offset.x = offsetx
	noise.offset.y = offsety
	for x in range(1,with):
		for y in range(1,height):
			var nNoise = (noise.get_noise_2d(x, y) + 1.0) * 0.5
			nNoise = distribution_curve.sample(nNoise)
			var Tile = LibraryManager.Tiles
			cell_pos = Vector3i(x,0,y)
			if nNoise < 0.2:
				grid.set_cell_item(cell_pos, Tile["Water"])
			elif nNoise < 0.4:
				grid.set_cell_item(cell_pos,Tile["Sand"])
			elif nNoise < 0.6:
				grid.set_cell_item(cell_pos,Tile["Grass"])
			elif nNoise < 0.8:
				grid.set_cell_item(cell_pos,Tile["Forest"])
			elif nNoise < 1:
				grid.set_cell_item(cell_pos,Tile["Stone"])

static func remove_map(map: GridMap):
	map.clear()
	
	
