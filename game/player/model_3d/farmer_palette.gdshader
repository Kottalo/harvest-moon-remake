shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	// glTF vertex colours are linear; Compatibility writes an sRGB framebuffer.
	vec3 low = COLOR.rgb * 12.92;
	vec3 high = 1.055 * pow(max(COLOR.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	ALBEDO = OUTPUT_IS_SRGB ? mix(low, high, step(vec3(0.0031308), COLOR.rgb)) : COLOR.rgb;
}
