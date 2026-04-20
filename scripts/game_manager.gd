extends Node3D

var library_manager = LibraryManager.new()
var map_size = Vector2i(10000, 10000)
var offset = Vector2i(0, 0)

@onready var sidebar = $CanvasLayer/ColorRect/Sidebar
@onready var render_distance = $Camera3D/RenderDistance
@onready var grid = $GridMap
@onready var prop_grid = $PropGrid
@export var height_modifier: int
@export var distribution_curve: Curve


func _ready() -> void:
	Global.distribution_curve = distribution_curve
	Global.cell_size = grid.cell_size
	Global.grid = grid
	Global.prop_grid = prop_grid


	add_to_group("game_manager")

	#Library Manager
	library_manager.populate_tiles_from_folder(grid,"res://data/tiles/")
	library_manager.populate_buildings_from_folder(grid,"res://data/buildings/")
	library_manager.populate_props_from_folder(prop_grid,"res://data/props/")
	print(LibraryManager.tiles)
	# First generation pass
	WorldGen.init(WorldGen.cfg)
	WorldGen.stream_chunks(grid, Global.distribution_curve, Vector2(0, 0))
	
	
	# Add UI-elements
	sidebar.populate(library_manager.buildings)
	sidebar.item_selected.connect(func(name: String) -> void:
		Global.selected_building = name
	)
