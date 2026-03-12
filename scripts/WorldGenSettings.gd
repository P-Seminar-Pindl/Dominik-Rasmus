extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
var Resources = 0
func PopulateResourceSliders():
	var slider = HSlider.new()
	for resource_name in Resources.Generate:
		slider[resource_name] = slider
		
	
