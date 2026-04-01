extends Node3D

var library_manager = LibraryManager.new()
var map_size = Vector2i(10000, 10000)
var offset = Vector2i(0, 0)

@onready var sidebar = $CanvasLayer/ColorRect/Sidebar
@onready var render_distance = $Camera3D/RenderDistance
@onready var grid = $GridMap

@export var height_modifier: int
@export var distribution_curve: Curve
@export var height_multiplier: int = 0


func _ready() -> void:
	add_to_group("game_manager")
	library_manager.populate_library(grid)
	library_manager.populate_buildings(grid)

	WorldGen.generate_island_centers(5, 400.0, randi())
	WorldGen.generate_map(grid, offset.x, offset.y, distribution_curve, 300, Vector3(100, 0, 100), height_modifier)

	sidebar.populate(library_manager.buildings)
	sidebar.item_selected.connect(func(name: String) -> void:
		Global.selected_building = name
	)


func _on_render_distance_value_changed(_value: float) -> void:
	WorldGen.remove_map(grid)
	WorldGen.generate_map(grid, 0, 0, distribution_curve, render_distance.value, Vector3(100, 0, 100), height_modifier)
