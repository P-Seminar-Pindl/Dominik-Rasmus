# building_network.gd — autoload as BuildingNetwork
extends Node

var _grid: Node = null

func register(grid: Node) -> void:
	_grid = grid

func rebuild_network() -> void:
	if Global == null:
		push_error("BuildingNetwork: Global is not available")
		return
	Global.rebuild_network()
