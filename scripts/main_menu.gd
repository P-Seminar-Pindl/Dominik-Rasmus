extends Node


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _on_quit_button_button_down() -> void:
	get_tree().quit()


func _on_options_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Options.tscn")
