uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float opacity = 1.0;
#include "res://game/rendering/source_animation.gdshaderinc"

void fragment() {
	vec4 pixel = sample_source(UV);
	// Alpha carries the PS1 STP bit: zero = transparent, half = blend, one = opaque.
	// Opaque texels are rendered by the accompanying normal-depth surface.
	if (pixel.a < 0.001 || pixel.a >= 0.75) {
		discard;
	}
	ALBEDO = pixel.rgb * COLOR.rgb;
	ALPHA = opacity;
}
