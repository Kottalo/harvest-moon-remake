shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
varying flat float source_depth;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	// player_draw sorts the entire body at the hand point relative to its ground position.
	// Pose pixels keep one depth, so a wall cannot slice through the billboard.
	vec3 anchor = MODEL_MATRIX[3].xyz + vec3(0.15, 0.1, 0.15);
	vec4 projected = PROJECTION_MATRIX * VIEW_MATRIX * vec4(anchor, 1.0);
	source_depth = projected.z / projected.w;
}

void fragment() {
	vec4 pixel = texture(albedo_texture, UV);
	if (pixel.a < 0.5) {
		discard;
	}
	ALBEDO = pixel.rgb;
	DEPTH = CLIP_SPACE_FAR == -1.0 ? source_depth * 0.5 + 0.5 : source_depth;
}
