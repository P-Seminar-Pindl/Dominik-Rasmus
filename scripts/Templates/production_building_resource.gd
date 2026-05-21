extends BuildingResource
class_name ProductionBuildingResource

@export_group("Production")
@export var input: Array[ResourceAmount] = []
@export var output: Array[ResourceAmount] = []
@export var production_time: float = 5.0              # seconds per production cycle
@export var storage_slots: Array[ResourceAmount] = [] # max local buffer per item, e.g. [Planks×10]
@export var input_stockpile: Array[ResourceAmount] = [] # target input buffer per item, e.g. [Gold×3]
