extends Node3D

var LibraryManager = load("res://scripts/LibraryManager.gd").new()
var mapSize = Vector2i(10000,10000)
var offset = Vector2i(0,0)
#
@onready var Sidebar = $Sidebar
@onready var RD = $Camera3D/RenderDistance
@onready var grid = $GridMap
@export var HeightModifier = 0
@export var distribution_curve : Curve
var frame= 0
func _ready() -> void:
	add_to_group("game_manager")
#Variable Space
	LibraryManager.PopulateLibrary(grid)
	LibraryManager.PopulateBuildings(grid)
#World Generation
	WorldGen.generate_island_centers(5, 400.0, randi())
	WorldGen.generate_map(grid,offset.x,offset.y,distribution_curve,300,Vector3(100,0,100),HeightModifier)
#UIManager
	Sidebar.populate(LibraryManager.Tiles)
	Sidebar.item_selected.connect(func(name):
		Global.selected_building = name
		print(Global.selected_building)
	)
	
var x=0
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	
	pass

func LoadScene():
	
	pass
func UnloadScene():
	pass


func _on_render_distance_value_changed(value: float) -> void:
	WorldGen.remove_map(grid)
	WorldGen.generate_map(grid,0,0,distribution_curve,RD.value,Vector3(100,0,100),HeightModifier)
	pass # Replace with function body.
