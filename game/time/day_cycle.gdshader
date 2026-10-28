shader_type canvas_item;
render_mode blend_sub;
uniform vec3 subtract_rgb = vec3(0.0);
void fragment() {
	// screen_fill_quad: subtractive blend, RGB in 20.12 fixed point / 255.
	COLOR = vec4(subtract_rgb,1.0);
}
