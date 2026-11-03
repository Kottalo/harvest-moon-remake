// Preserve each source texture's clamp-to-edge behaviour inside the packed image.
vec2 atlas_uv(vec2 uv, vec4 region, ivec2 size) {
	vec2 half_pixel = vec2(0.5) / (vec2(size) * region.zw);
	return region.xy + clamp(uv,half_pixel,vec2(1.0)-half_pixel)*region.zw;
}
