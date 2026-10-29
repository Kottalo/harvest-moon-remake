shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D dug_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D cell_states : filter_nearest, repeat_disable;
uniform float orientations[100];
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec4 pixel = texture(albedo_texture,UV);
	vec2 grid = (world_point.xz+vec2(2.0))/0.4;
	vec2 cell = floor(grid);
	if (abs(world_point.y)<0.001 && all(greaterThanEqual(cell,vec2(0.0))) && all(lessThan(cell,vec2(10.0)))) {
		if (texture(cell_states,(cell+0.5)/10.0).r>0.5) {
			int code = int(orientations[int(cell.y)*10+int(cell.x)]);
			vec2 local = fract(grid);
			if ((code&1)!=0) local = local.yx;
			if ((code&2)!=0) local.x = 1.0-local.x;
			if ((code&4)!=0) local.y = 1.0-local.y;
			// mine_retexture_cell: original FT4 corner spans and clear-cell CLUT.
			pixel = texture(dug_texture,(vec2(131.5,0.5)+vec2(28.0,31.0)*local)/256.0);
		}
	}
	if (pixel.a<0.5) discard;
	ALBEDO = pixel.rgb*COLOR.rgb;
}
