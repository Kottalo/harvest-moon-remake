@tool
extends Node3D
## Editor-only footprint guide. Runtime reads the authored Sprite and collision nodes.
@export_enum("Initial field item", "Freely placed item") var preview_mode := 0
var guide: MeshInstance3D

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		return
	_create_guide()

func _create_guide() -> void:
	if is_instance_valid(guide):
		return
	guide = MeshInstance3D.new()
	guide.name = "FootprintGuide"
	guide.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0,0.65,0.1,0.2)
	guide.material_override = material
	add_child(guide,false,Node.INTERNAL_MODE_BACK)
	_process(0)

func _process(_delta: float) -> void:
	if guide == null:
		return
	var field: CollisionShape3D = $Obstruction/FieldFootprint
	var loose: CollisionShape3D = $Obstruction/LooseFootprint
	field.visible = preview_mode==0
	loose.visible = preview_mode==1
	field.disabled = preview_mode!=0
	loose.disabled = preview_mode!=1
	var selected := field if preview_mode==0 else loose
	guide.mesh.size = selected.shape.size
	guide.transform = $Obstruction.transform*selected.transform
