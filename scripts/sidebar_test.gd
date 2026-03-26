extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	var LibraryManager = LibraryManager.new()
	var SidebarTiles = $Sidebar2
	var Sidebar = $Sidebar
	var grid = $GridMap
	add_to_group("game_manager")
#Variable Space
	LibraryManager.PopulateLibrary(grid)
	LibraryManager.PopulateBuildings(grid,"res://Json/Flaticons/")
#UIManager
	SidebarTiles.populate(LibraryManager.Tiles)
	SidebarTiles.item_selected.connect(func(name):
		Global.selected_building = name
		print(Global.selected_building)
	)
	Sidebar.populate(LibraryManager.Buildings)
	Sidebar.item_selected.connect(func(name):
		Global.selected_building = name
		print(Global.selected_building)
	)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
