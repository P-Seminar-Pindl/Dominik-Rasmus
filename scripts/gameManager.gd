extends Node3D

var LibraryManager = load("res://scripts/LibraryManager.gd").new()
var mapSize = Vector2i(1000,1000)
var offset = Vector2i(0,0)
@export var distribution_curve : Curve
var frame= 0
func _ready() -> void:
#Variable Space
	var grid = $GridMap
	LibraryManager.PopulateLibrary(grid)
#World Generation
	
	WorldGen.generate_map(grid,mapSize.x,mapSize.y, offset.x,offset.y,distribution_curve)

#HudManager
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var grid = $GridMap
	if frame == 100:
		grid.clear()
		WorldGen.generate_map(grid,mapSize.x,mapSize.y, offset.x,offset.y,distribution_curve)

	else: frame + 1
	pass

func LoadScene():
	
	pass
func UnloadScene():
	pass
