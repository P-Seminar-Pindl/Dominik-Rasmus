extends Node3D

var LibraryManager = load("res://scripts/LibraryManager.gd").new()
var mapSize = Vector2i(1000,1000)
var offset = Vector2i(0,0)
@onready var RD = $Camera3D/RenderDistance
@onready var grid = $GridMap
@export var distribution_curve : Curve
var frame= 0
func _ready() -> void:
#Variable Space
	
	
	LibraryManager.PopulateLibrary(grid)
	var testSideBar = SideBar.AddSideBar("test", LibraryManager.Tiles, Vector2(1,1))
	get_tree().root.add_child(testSideBar) 
	LibraryManager.PopulateBuildings(grid)
#World Generation
	
	WorldGen.generate_map(grid,offset.x,offset.y,distribution_curve,300,Vector3(100,0,100))

#HudManager
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func LoadScene():
	
	pass
func UnloadScene():
	pass


func _on_render_distance_value_changed(value: float) -> void:
	WorldGen.remove_map(grid)
	WorldGen.generate_map(grid,0,0,distribution_curve,RD.value,Vector3(100,0,100))
	pass # Replace with function body.
