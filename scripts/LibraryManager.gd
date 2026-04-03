extends Node
class_name LibraryManager
static var Tiles = {}
static var Buildings = {}
func PopulateLibrary(grid): 
	Tiles.Dirt =assetInit.addTileFromTexture("Dirt",grid,"res://textures/dirt.png")
	Tiles.Water =assetInit.addTileFromTexture("Water",grid,"res://textures/blue_concrete.png")
	Tiles.Grass =assetInit.addTileFromTexture("Grass",grid,"res://textures/lime_concrete.png")
	Tiles.Forest =assetInit.addTileFromTexture("Forest",grid,"res://textures/green_concrete_powder.png")
	Tiles.Sand =assetInit.addTileFromTexture("Sand",grid,"res://textures/sand.png")
	Tiles.Stone =assetInit.addTileFromTexture("Stone",grid,"res://textures/stone.png")
func  PopulateBuildings(grid):
		Buildings.House = assetInit.addBuildingFromTexture(
		"House",
		grid,
		"res://textures/house.png",
		{
			"population": 10,
			"income": 0.2,
			"needs": {"bread": 1, "water":1}
			
		}
	)
		Buildings.Mine = assetInit.addBuildingFromTexture(
		"Mine",
		grid ,
		"res://textures/mine.png",
		{
			"population" : 5,
			"income" : 3,
			"needs": {"bread" : 3, "water" : 5}
		}
		)
