extends Node

func _ready() -> void:
	var MainMenu = preload("res://scenes/Game.tscn")


func _on_start_button_pressed() :
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
	pass # Replace with function body.


func _on_quit_button_button_down() -> void:
	print("1")
	get_tree().quit()
	
	
	pass # Replace with function body.
	
	pass # Replace with function body.
	
	


func _on_options_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Options.tscn")
	
	pass # Replace with function body.
