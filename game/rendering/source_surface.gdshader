shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool textured = true;
varying flat float source_depth;

void vertex() {
	// model.c orders each complete source primitive by its average camera depth.
	vec4 center = VIEW_MATRIX * MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	center.z -= CUSTOM0.w;
	vec4 projected = PROJECTION_MATRIX * center;
	source_depth = projected.z / projected.w;
}

void fragment() {
	vec4 pixel = textured ? texture(albedo_texture, UV) : vec4(1.0);
	if (pixel.a < 0.5) {
		discard;
	}
	ALBEDO = pixel.rgb * COLOR.rgb;
	DEPTH = CLIP_SPACE_FAR == -1.0 ? source_depth * 0.5 + 0.5 : source_depth;
}
