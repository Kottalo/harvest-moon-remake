shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform bool textured = true;
uniform float alpha_scissor_threshold = 0.5;
#include "res://game/rendering/source_animation.gdshaderinc"

void fragment() {
	vec4 pixel = textured ? sample_source(UV) : vec4(1.0);
	if (pixel.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = pixel.rgb * COLOR.rgb;
}
