extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var c=JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	var d=JSON.parse_string(FileAccess.get_file_as_string("res://game/time/day_cycle_catalog.json"))
	var output={}
	for id in c:
		if int(d.areas[id].source_flags)&0x1800!=0 or id=="56": continue
		var name: String = "coast" if id=="52" else c[id].slug
		var scene=load("res://game/world/coast.tscn" if id=="52" else c[id].scene).instantiate()
		root.add_child(scene)
		var surfaces=[];var atlases=[]
		for geometry: MeshInstance3D in scene.find_children("Geometry","MeshInstance3D",true,false):
			if geometry.get_parent().name.begins_with("ZoneModel"): continue
			for index in geometry.mesh.get_surface_count():
				var m=geometry.mesh.surface_get_material(index)
				if not m is ShaderMaterial or not m.shader.resource_path.ends_with("source_surface.gdshader"): continue
				var a=geometry.mesh.surface_get_arrays(index)
				var texture=m.get_shader_parameter("albedo_texture")
				var region=Vector4(0,0,1,1);var slot = -1
				if texture!=null:
					if texture is AtlasTexture:
						region=load("res://game/rendering/atlas_binding.gd").region(texture)
						texture=texture.atlas
					if not atlases.has(texture.resource_path): atlases.append(texture.resource_path)
					slot=atlases.find(texture.resource_path)
				var vertices=[];var uvs=[];var colors=[]
				for j in a[Mesh.ARRAY_VERTEX].size():
					var v: Vector3 = geometry.global_transform*a[Mesh.ARRAY_VERTEX][j]
					var uv: Vector2 = a[Mesh.ARRAY_TEX_UV][j]
					var color: Color = a[Mesh.ARRAY_COLOR][j]
					vertices.append_array([v.x,v.y,v.z]);uvs.append_array([uv.x,uv.y]);colors.append_array([color.r,color.g,color.b])
				surfaces.append({"vertices":vertices,"uv":uvs,"colors":colors,"slot":slot,"region":[region.x,region.y,region.z,region.w],"water":m.get_shader_parameter("motion_count")!=null and m.get_shader_parameter("motion_count")>0})
		output[name]={"atlases":atlases,"surfaces":surfaces}
		print("BACKDROP_SOURCE ",name," atlases=",atlases.size()," surfaces=",surfaces.size())
		scene.free()
	var f=FileAccess.open("res://tools/generated/backdrop_geometry.json",FileAccess.WRITE);f.store_string(JSON.stringify(output));f.close()
	quit()
