extends Node
class_name WorldGen
@onready var map = $"."
var move = Vector2i(0,0)
var mapSize= Vector2i(100,100)
static var RequiredTiles = []
static var LoadedTiles = []
# Called when the node enters the scene tree for the first time.
static var noise = FastNoiseLite.new()
static var cell_pos = Vector3i(0,0,0)
static var grid: GridMap
func _ready() -> void:
	
	pass # Replace with function body.
	
static func generate_map(grid,offsetx,offsety,distribution_curve, renderDistance :int, PlayerPos: Vector3):
	#Variable Space
	var center = Vector2(PlayerPos.x,PlayerPos.y)
	var coords = cords_in_radius(renderDistance,center)
	noise.offset.x = offsetx
	noise.offset.y = offsety
	for i in coords.size():
		LoadTile(grid,coords[i],distribution_curve,i)
		
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

static func MapStream(RenderDistance, Center, distribution_curve):
	var MissingTiles = GetTilesToLoad(RenderDistance, Center)
	for coords in MissingTiles.size():
		LoadTile(grid, MissingTiles[coords], distribution_curve,coords)
		
	pass
static func GetTilesToLoad(RenderDistance, Center) -> Array:
	var RequiredTiles = cords_in_radius(RenderDistance, Center)
	var TilesToLoad = []
	for tile in RequiredTiles:
		if not tile in LoadedTiles:
			TilesToLoad.append(tile)
	return TilesToLoad
	
static func LoadTile(grid,coordinate,distribution_curve,index):
	var nNoise = (noise.get_noise_2d(coordinate.x, coordinate.y) + 1.0) * 0.5
	nNoise = distribution_curve.sample(nNoise)
	var Tile = LibraryManager.Tiles
	cell_pos = Vector3i(coordinate.x,0,coordinate.y)
	LoadedTiles.append(coordinate)
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
	pass
static func UnloadChunks():
	pass
	
	
