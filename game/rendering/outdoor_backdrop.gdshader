shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D scene_atlas_0 : source_color, filter_linear, repeat_disable;
uniform sampler2D scene_atlas_1 : source_color, filter_linear, repeat_disable;
uniform sampler2D scene_atlas_2 : source_color, filter_linear, repeat_disable;
uniform sampler2D patch_uv : filter_nearest, repeat_disable;
uniform sampler2D patch_axes : filter_nearest, repeat_disable;
uniform sampler2D patch_bounds : filter_nearest, repeat_disable;
uniform sampler2D patch_tint : filter_nearest, repeat_disable;
uniform vec4 field_rect;
uniform vec3 view_right = vec3(0.70710678,0.0,-0.70710678);
uniform vec3 view_up = vec3(-0.31622777,0.89442719,-0.31622777);
varying vec2 map_point;

void vertex() {
	vec3 world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	map_point = vec2(dot(world,view_right),dot(world,view_up));
}

vec4 source_pixel(vec2 uv, float slot) {
	if (slot<0.0) return vec4(1.0);
	if (slot<0.5) return texture(scene_atlas_0,uv);
	if (slot<1.5) return texture(scene_atlas_1,uv);
	return texture(scene_atlas_2,uv);
}

vec3 continuation(ivec2 cell, vec2 dimensions) {
	vec4 patch = texelFetch(patch_uv,cell,0);
	vec4 axes = texelFetch(patch_axes,cell,0);
	vec4 bounds = texelFetch(patch_bounds,cell,0);
	vec3 tint = texelFetch(patch_tint,cell,0).rgb;
	vec2 anchor = field_rect.xy+vec2(cell)/(dimensions-vec2(1.0))*field_rect.zw;
	vec2 uv = patch.xy+axes.xy*(map_point.x-anchor.x)+axes.zw*(map_point.y-anchor.y);
	vec2 extent = max(bounds.xy-patch.zw,vec2(0.000001));
	// Mirror within this original triangle's tile, never into neighbouring atlas art.
	uv = patch.zw+(vec2(1.0)-abs(mod((uv-patch.zw)/extent,vec2(2.0))-vec2(1.0)))*extent;
	vec4 pixel = source_pixel(uv,bounds.z);
	// Transparent foliage pixels must reveal continuation, never the clear colour.
	vec3 base = max(source_pixel((patch.zw+bounds.xy)*0.5,bounds.z).rgb,vec3(0.08,0.12,0.06));
	return mix(base,pixel.rgb,smoothstep(0.0,0.5,pixel.a))*tint;
}

void fragment() {
	vec2 dimensions = vec2(textureSize(patch_uv,0));
	vec2 grid = clamp((map_point-field_rect.xy)/field_rect.zw*(dimensions-vec2(1.0)),vec2(0.0),dimensions-vec2(1.0));
	ivec2 cell = min(ivec2(floor(grid)),ivec2(dimensions)-ivec2(2));
	vec2 blend = smoothstep(vec2(0.0),vec2(1.0),grid-vec2(cell));
	vec3 low = mix(continuation(cell,dimensions),continuation(cell+ivec2(1,0),dimensions),blend.x);
	vec3 high = mix(continuation(cell+ivec2(0,1),dimensions),continuation(cell+ivec2(1,1),dimensions),blend.x);
	ALBEDO = mix(low,high,blend.y);
}
