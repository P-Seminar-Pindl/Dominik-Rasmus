extends Node
class_name WorldGen
@onready var map = $"."
var move = Vector2i(0,0)
var mapSize= Vector2i(100,100)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass # Replace with function body.
	
static func generate_map(grid: GridMap, offsetx,offsety, distribution_curve, renderDistance :int, PlayerPos: Vector3):
	#Variable Space
	var center = Vector2(PlayerPos.x,PlayerPos.y)
	var coords = cords_in_radius(renderDistance,center)
	var noise = FastNoiseLite.new()
	var cell_pos = Vector3i(0,0,0)
	noise.offset.x = offsetx
	noise.offset.y = offsety
	for i in coords.size():
		var coordinate = coords[i]
		var nNoise = (noise.get_noise_2d(coords[i].x, coords[i].y) + 1.0) * 0.5
		nNoise = distribution_curve.sample(nNoise)
		var Tile = LibraryManager.Tiles
		cell_pos = Vector3i(coords[i].x,0,coords[i].y)
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
static func cords_in_radius(radius: int, center: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []

	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var pos = Vector2i(x, y)
			if center.distance_to(pos) <= radius:
				results.append(pos)

	return results
static func remove_map(map: GridMap):
	map.clear()
static func LoadChunks():
	pass
static func UnloadChunks():
	pass
	
	
