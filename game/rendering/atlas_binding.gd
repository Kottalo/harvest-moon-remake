extends RefCounted
## Shader samplers receive the whole atlas RID; Sprite3D handles its own AtlasTexture UVs.
static func region(texture: Texture2D) -> Vector4:
	if texture is AtlasTexture:
		var size: Vector2 = texture.atlas.get_size()
		return Vector4(texture.region.position.x/size.x,texture.region.position.y/size.y,texture.region.size.x/size.x,texture.region.size.y/size.y)
	return Vector4(0,0,1,1)

static func bind(material: ShaderMaterial, uniform: String, texture: Texture2D) -> void:
	material.set_shader_parameter(uniform,texture)
	material.set_shader_parameter(uniform+"_region",region(texture))
