extends Node
class_name SideBar

var Tiles = LibraryManager.Tiles  


enum state {}
func _ready() -> void:
	print(Tiles[1], "zrd")
static func AddSideBar(name: String, type: Dictionary, position: Vector2, on_select: Callable) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(200, 400)
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	PopulateSidebar(type, vbox, on_select)
	return panel

static func PopulateSidebar(type: Dictionary, parent: Node, on_select: Callable) -> void:
	print(get_stack())
	for x in type:
		var button = Button.new()
		button.text = x
		button.pressed.connect(func(): on_select.call(x))
		parent.add_child(button)

		
	
	pass

	
	pass
