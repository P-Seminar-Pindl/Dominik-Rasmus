extends Node3D

var library_manager = LibraryManager.new()
var map_size = Vector2i(10000, 10000)
var offset = Vector2i(0, 0)
const SIDEBAR_SCENE := preload("res://scenes/Sidebar.tscn")

@onready var grid = $GridMap
@onready var canvas_layer = $CanvasLayer
@export var height_modifier: int
@export var distribution_curve: Curve
var sidebar: Sidebar = null


func _ready() -> void:
	Global.distribution_curve = distribution_curve
	Global.cell_size = grid.cell_size
	Global.grid = grid


	add_to_group("game_manager")
	
	#Library Manager
	library_manager.populate_tiles_from_folder(grid,"res://data/tiles/")
	library_manager.populate_buildings_from_folder(grid,"res://data/buildings/")
	print(LibraryManager.tiles)
	# First generation pass
	WorldGen.init(WorldGen.cfg)
	WorldGen.stream_chunks(grid, Global.distribution_curve, Vector2(0, 0))
	
	
	# Add UI-elements
	if sidebar == null:
		var existing_sidebar := canvas_layer.get_node_or_null("Sidebar")
		if existing_sidebar is Sidebar:
			sidebar = existing_sidebar as Sidebar
		else:
			sidebar = SIDEBAR_SCENE.instantiate() as Sidebar
			sidebar.name = "Sidebar"
			canvas_layer.add_child(sidebar)

	sidebar.populate(library_manager.buildings)
	sidebar.item_selected.connect(func(name: String) -> void:
		Global.selected_building = name
	)

	BuildingNetwork.rebuild_network()
