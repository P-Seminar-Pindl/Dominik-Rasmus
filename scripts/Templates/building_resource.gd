extends Resource
class_name BuildingResource

@export var name: String = ""
@export var texture: Texture2D
@export var workforce: int = 0
@export var costs: Dictionary = {}
@export var input: Dictionary = {}
@export var output: Dictionary = {}
@export var mesh: Mesh = BoxMesh.new()
@export var collision_size: Vector3 = Vector3(2,2,2)

func _init():
	if texture:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.uv1_scale = Vector3(0.5,0.5,0.5)
		mat.uv1_offset = Vector3(0.5,0.5,0.5)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 1.0
		
		for s in range(mesh.get_surface_count()):
			mesh.surface_set_material(s, mat)
