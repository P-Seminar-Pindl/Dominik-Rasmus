extends Node
class_name LibraryManager
static var Tiles = {}
func PopulateLibrary(grid): 
	Tiles.Dirt =assetInit.addTileFromTexture("Dirt",grid,"res://textures/dirt.png")
	Tiles.Water =assetInit.addTileFromTexture("Water",grid,"res://textures/blue_concrete.png")
	Tiles.Grass =assetInit.addTileFromTexture("Grass",grid,"res://textures/lime_concrete.png")
	Tiles.Forest =assetInit.addTileFromTexture("Forest",grid,"res://textures/green_concrete_powder.png")
	Tiles.Sand =assetInit.addTileFromTexture("Sand",grid,"res://textures/sand.png")
	Tiles.Stone =assetInit.addTileFromTexture("Stone",grid,"res://textures/stone.png")
