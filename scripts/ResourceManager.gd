extends Node

signal resources_changed

# City-wide resource stockpile.
# Edit starting amounts here freely.
var stockpile: Dictionary = {
	"Gold":   50,
	"Wood":   20,
	"Planks": 10,
	"Stone":   5,
	"Food":   10,
}


func add(item: String, amount: int) -> void:
	stockpile[item] = stockpile.get(item, 0) + amount
	resources_changed.emit()


func remove(item: String, amount: int) -> bool:
	if not has_enough(item, amount):
		return false
	stockpile[item] -= amount
	resources_changed.emit()
	return true


func get_amount(item: String) -> int:
	return stockpile.get(item, 0)


func has_enough(item: String, amount: int) -> bool:
	return stockpile.get(item, 0) >= amount
