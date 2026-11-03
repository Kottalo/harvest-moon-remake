extends SceneTree
## Projection/ownership checks in headless; --gpu also checks the rendered pixels.
var world: Node3D
var gpu := false
func _initialize() -> void: run.call_deferred()
func require_ok(ok: bool,message: String) -> bool:
	if not ok: push_error(message);quit(1)
	return ok
func run() -> void:
	gpu = OS.get_cmdline_user_args().has("--gpu")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true;viewport.size=Vector2i(960,720)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world=load("res://game/world/world.tscn").instantiate();viewport.add_child(world)
	world.set_process(false);world.set_physics_process(false);world.player.set_physics_process(false)
	var camera = world.camera
	var original_zoom: float = camera.size
	var count := 0
	for id in world.world:
		var info: Dictionary = world.world[id]
		world._change_area(int(id),Vector3(info.spawn[0],info.spawn[1],info.spawn[2]))
		var outdoors: bool = int(world.day_cycle.catalogue.areas[id].source_flags)&0x1800==0
		var background = camera.backdrop
		if not require_ok(background.visible==outdoors,"Background indoor/outdoor mismatch: "+id): return
		if not outdoors: continue
		if not require_ok(background.get_parent()==camera and background.find_children("*","CollisionObject3D",true,false).is_empty(),"Background must have no collision or world ownership"): return
		for label in ["uv","axes","bounds","tint"]:
			var texture: Texture2D = background.material_override.get_shader_parameter("patch_"+label)
			if not require_ok(texture!=null and texture.get_width()==64 and texture.get_height()==64,"Invalid baked shader data: "+id+" "+label): return
		if not require_ok(background.material_override.get_shader_parameter("view_right").is_equal_approx(camera.basis.x) and background.material_override.get_shader_parameter("view_up").is_equal_approx(camera.basis.y),"Background plane does not match gameplay camera: "+id): return
		for aspect in [Vector2i(960,720),Vector2i(1152,720),Vector2i(1920,720),Vector2i(720,960)]:
			viewport.size=aspect
			for offset in [Vector3.ZERO,Vector3(16,0,16),Vector3(-16,0,-16)]:
				world.player.position=Vector3(info.spawn[0],info.spawn[1],info.spawn[2])+offset
				camera.follow(world.player,false,false)
				var quad: QuadMesh = background.mesh
				var half := quad.size*0.5
				var tl: Vector2 = camera.unproject_position(background.global_transform*Vector3(-half.x,half.y,0))
				var br: Vector2 = camera.unproject_position(background.global_transform*Vector3(half.x,-half.y,0))
				if not require_ok(tl.x<0 and tl.y<0 and br.x>aspect.x and br.y>aspect.y and -background.position.z>camera.near and -background.position.z<camera.far and camera.size==original_zoom,"Background does not cover the complete unchanged viewport: "+str([id,aspect,tl,br])): return
				count+=1
		# Clear-colour isolation: only the backdrop remains, so every sample must be
		# opaque scene texture, including edges/corners and non-original aspects.
		if gpu:
			world.get_node("Location").hide();world.player.hide()
			for tick in 3: await RenderingServer.frame_post_draw
			var image=viewport.get_texture().get_image()
			if not require_ok(image!=null and not image.is_empty(),"No GPU image"): return
			var clear=ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
			for y in range(0,image.get_height(),7):
				for x in range(0,image.get_width(),7):
					var pixel=image.get_pixel(x,y)
					if not require_ok(pixel.a>0.999 and Vector3(pixel.r-clear.r,pixel.g-clear.g,pixel.b-clear.b).length()>0.001,"Outdoor clear-colour pixel: "+str([id,x,y])): return
			world.get_node("Location").show();world.player.show()
		print("OUTDOOR_BACKDROP_LOCATION_OK: ",info.slug," quad covers all tested aspect ratios/poses")
		if gpu and id in ["0","52","60","72"]:
			viewport.size=Vector2i(960,720)
			world.player.position=Vector3(info.spawn[0],info.spawn[1],info.spawn[2])
			camera.follow(world.player,false,false)
			for tick in 3: await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://tools/generated/"+info.slug+"_background_gpu.png")
	# Interior switch releases the previous material; coast label switches retain it.
	world._change_area(52,Vector3(4.5,0,0))
	var resource=world.camera.backdrop.material_override
	world.current_area=56;world._update_camera()
	if not require_ok(world.camera.backdrop.material_override==resource,"Coast label switch replaced background"): return
	world._change_area(80,Vector3.ZERO)
	if not require_ok(not world.camera.backdrop.visible and world.camera.backdrop.material_override==null,"Interior retained exterior background"): return
	if not require_ok(ProjectSettings.get_setting("display/window/stretch/aspect")=="expand","Fixed-aspect letterbox bars remain enabled"): return
	print("OUTDOOR_BACKDROP_OK: ",count," poses; 15 areas, full viewport, unchanged zoom, opaque background, no collisions, shared coast, indoor cleanup; GPU=",gpu)
	world.free();viewport.free();quit()
