extends Node

var Tiles = LibraryManager.Tiles

enum state {}

	AddSideBar("TilesMenu", Tiles, Vector2(1,1))

func AddSideBar(name: String, type: Dictionary , position: Vector2 ):
	var panel = Panel.new()
	var VBox = VBoxContainer.new()
	
	panel.add_child(VBox)
	PopulateSidebar("test", type)
	pass


func PopulateSidebar(name: String, type: Dictionary):
	for x in type: 
		var button = Button.new()
		button.text = "test"

	pass
