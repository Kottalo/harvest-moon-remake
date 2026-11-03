shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D tilled_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D watered_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D field_states : filter_nearest, repeat_disable;
uniform vec4 albedo_texture_region = vec4(0.0,0.0,1.0,1.0);
uniform vec4 tilled_texture_region = vec4(0.0,0.0,1.0,1.0);
uniform vec4 watered_texture_region = vec4(0.0,0.0,1.0,1.0);
#include "res://game/rendering/atlas_sampling.gdshaderinc"
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec4 pixel = texture(albedo_texture,atlas_uv(UV,albedo_texture_region,textureSize(albedo_texture,0)));
	vec2 grid = (world_point.xz-vec2(-4.4,-1.6))/0.4;
	vec2 cell = floor(grid);
	if (abs(world_point.y)<0.001 && all(greaterThanEqual(cell,vec2(0.0))) && all(lessThan(cell,vec2(45.0,25.0)))) {
		float state = texture(field_states,(cell+0.5)/vec2(45.0,25.0)).r*255.0;
		// field_cell_retexture: exact 31-texel corner span, including half-texel centres.
		vec2 local = fract(grid);
		if (state>0.5 && state<1.5) {
			vec2 soil_uv = (vec2(159.5,176.5)+vec2(-31.0*local.y,31.0*local.x))/256.0;
			pixel = texture(tilled_texture,atlas_uv(soil_uv,tilled_texture_region,textureSize(tilled_texture,0)));
		} else if (state>1.5) {
			vec2 soil_uv = (vec2(191.5,176.5)+vec2(-31.0*local.y,31.0*local.x))/256.0;
			pixel = texture(watered_texture,atlas_uv(soil_uv,watered_texture_region,textureSize(watered_texture,0)));
		}
	}
	if (pixel.a<0.5) { discard; }
	ALBEDO = pixel.rgb*COLOR.rgb;
}
