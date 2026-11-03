@tool
extends RefCounted
## Offline native resource rewrite. Never adds nodes to the editor/game tree.
var aliases: Dictionary
var motion: Dictionary
var replacements := 0
var pack_regions := false

func _texture(texture: Texture2D) -> Texture2D:
	if texture==null: return null
	var target: String = aliases.get(texture.resource_path,"")
	if target.is_empty() and texture is ImageTexture:
		target = motion.get(texture.resource_name,"")
	if target.is_empty(): return texture
	replacements += 1
	return load(target)

func _material(material: Material) -> void:
	if material is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var texture: Texture2D = material.get_texture(slot)
			if texture!=null: material.set_texture(slot,_texture(texture))
		if pack_regions and material.albedo_texture is AtlasTexture:
			var rect: Vector4 = load("res://game/rendering/atlas_binding.gd").region(material.albedo_texture)
			material.uv1_scale = Vector3(rect.z,rect.w,1)
			material.uv1_offset = Vector3(rect.x,rect.y,0)
			replacements += 1
		return
	if not material is ShaderMaterial: return
	for uniform in ["albedo_texture","motion_texture"]:
		var value: Variant = material.get_shader_parameter(uniform)
		if value is Texture2D:
			var texture := _texture(value)
			if pack_regions:
				load("res://game/rendering/atlas_binding.gd").bind(material,uniform,texture)
				replacements += 1
			else: material.set_shader_parameter(uniform,texture)

func snapshot(scene: Node) -> Array:
	var state := []
	# Godot assigns process-dependent numeric suffixes to unnamed baked shapes.
	# Array order still distinguishes them; these IDs carry no geometry/state.
	var generated_name := RegEx.create_from_string("@([A-Za-z0-9_]+)@[0-9]+")
	for node in [scene]+scene.find_children("*","",true,false):
		var item := [generated_name.sub(str(scene.get_path_to(node)),"@$1@",true),node.get_class()]
		if node is Node3D: item.append(node.transform)
		if node is CollisionObject3D: item.append([node.collision_layer,node.collision_mask])
		if node is CollisionShape3D:
			item.append([node.disabled,node.shape.get_class(),node.shape.margin])
			if node.shape is ConcavePolygonShape3D: item.append([node.shape.get_faces(),node.shape.backface_collision])
			elif node.shape is BoxShape3D: item.append(node.shape.size)
		if node is MeshInstance3D:
			for surface in node.mesh.get_surface_count():
				item.append(node.mesh.surface_get_arrays(surface))
				var material: Material = node.mesh.surface_get_material(surface)
				if material is ShaderMaterial:
					item.append(material.shader.resource_path)
					for uniform in ["albedo_texture","textured","alpha_scissor_threshold","opacity","motion_texture","motion_count","motion_size","motion_destination","motion_source","motion_timing","motion_test_time","motion_smooth","motion_ripples"]:
						var value: Variant = material.get_shader_parameter(uniform)
						item.append([uniform,Vector2i(value.get_width(),value.get_height()) if value is Texture2D else value])
				elif material is BaseMaterial3D:
					for property in material.get_property_list():
						if not property.usage&PROPERTY_USAGE_STORAGE or property.name in ["resource_name","resource_path","script"]: continue
						var value: Variant = material.get(property.name)
						if material.albedo_texture is AtlasTexture:
							if property.name=="uv1_scale": value = Vector3.ONE
							elif property.name=="uv1_offset": value = Vector3.ZERO
						if value is Texture2D: value = Vector2i(value.get_width(),value.get_height())
						elif value is Resource: value = [value.get_class(),value.resource_name]
						item.append([str(property.name),value])
		state.append(item)
	return state

func digest(state: Array) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(state))
	return hash.finish().hex_encode()

func rewrite(path: String, plan: Dictionary) -> Dictionary:
	aliases = plan.aliases
	motion = plan.motion
	pack_regions = plan.get("pack_regions",false)
	replacements = 0
	var source: PackedScene = ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var scene := source.instantiate()
	var old_state := snapshot(scene)
	var before := digest(old_state)
	var temporary := path+".texture_tmp.scn"
	var stale_dependency := false
	for dependency in ResourceLoader.get_dependencies(path):
		for part in str(dependency).split("::"):
			stale_dependency = stale_dependency or aliases.has(part)
	for node in [scene]+scene.find_children("*","",true,false):
		if node is MeshInstance3D:
			_material(node.material_override)
			for surface in node.mesh.get_surface_count():
				_material(node.mesh.surface_get_material(surface))
				_material(node.get_surface_override_material(surface))
		if node is Sprite3D:
			node.texture = _texture(node.texture)
			_material(node.material_override)
	var changed := replacements>0 or stale_dependency
	if changed:
		var packed := PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,temporary)==OK,"Native texture rewrite could not save "+path)
	scene.free()
	var saved: PackedScene = ResourceLoader.load(temporary if changed else path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var restored := saved.instantiate()
	var new_state := snapshot(restored)
	var after := digest(new_state)
	restored.free()
	var differences := []
	for i in mini(old_state.size(),new_state.size()):
		for j in mini(old_state[i].size(),new_state[i].size()):
			if var_to_bytes(old_state[i][j])!=var_to_bytes(new_state[i][j]):
				differences.append([old_state[i][0],j,type_string(typeof(old_state[i][j])),str(old_state[i][j]).left(300),str(new_state[i][j]).left(300)])
	if before==after and changed:
		assert(DirAccess.rename_absolute(temporary,path)==OK)
	return {"scene":path,"bindings_replaced":replacements,"before":before,"after":after,"differences":differences.slice(0,12)}
