extends Node
class_name HudManager
static func MenuActive(Name: String, State: bool):
	var path = "res://scenes/" + Name + ".tscn" 
	var Menu = load(path)
	var MenuInstance = Menu.instantiate()
