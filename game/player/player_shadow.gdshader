shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float sort_height = 0.0;
varying flat float source_depth;
void vertex() {
	// Centre the visible blob on the logical foot point shared with soil cells.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	// Keep source depth separate from picture placement so scene occlusion stays intact.
	vec4 anchor = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz+vec3(0.15,0.1+sort_height,0.15),1.0);
	anchor.z -= 0.01; // Behind body and held-item layers, with ordinary scene depth tests.
	vec4 projected = PROJECTION_MATRIX*anchor;
	source_depth = projected.z/projected.w;
}
void fragment() {
	vec4 pixel = texture(albedo_texture,UV);
	if (pixel.a<0.01) discard;
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a*0.5; // UI ANI attr 0x10, texture-page blend mode 0.
	DEPTH = CLIP_SPACE_FAR == -1.0 ? source_depth*0.5+0.5 : source_depth;
}
