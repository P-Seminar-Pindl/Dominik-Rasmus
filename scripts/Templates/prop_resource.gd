extends Resource
class_name PropResource

@export_group("Identity")
@export var name: String = ""
@export var family: String = ""
@export var texture: Texture

@export_group("Mesh")
@export var mesh: Mesh = BoxMesh.new()
@export var size: Vector3 = Vector3(2, 2, 2)
@export var collision_size: Vector3 = Vector3(2, 2, 2)

@export_group("Density tier")
@export_range(0.0, 1.0) var min_density: float = 0.0
@export_range(0.0, 1.0) var max_density: float = 1.0

@export_group("Harvesting")
@export var is_harvestable: bool = false
@export var harvest_yields: Array[ResourceAmount] = []

func setup_mesh() -> void:
	var mat = StandardMaterial3D.new()
	if texture:
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_scale = Vector3i(1, 1, 1)
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 1.0

	if mesh is BoxMesh:
		mesh.size = size

	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, mat)
