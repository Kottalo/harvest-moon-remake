uniform sampler2D motion_texture : source_color, filter_linear, repeat_disable;
uniform int motion_count = 0;
uniform vec2 motion_size = vec2(1.0);
uniform vec4 motion_destination[16];
uniform vec4 motion_source[16];
uniform vec4 motion_timing[16];
uniform float motion_test_time = -1.0;
uniform bool motion_smooth = true;
uniform bool motion_ripples = false;
varying vec3 motion_world_position;

void vertex() {
	motion_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 sample_motion(vec4 source, vec2 local, float seconds) {
	if (motion_ripples) {
		vec2 ripple = sin(motion_world_position.xz * vec2(1.8, 2.1) + vec2(seconds * 1.3, -seconds * 1.7));
		local += ripple * vec2(0.6, 0.4);
	}
	local = mod(local, source.zw);
	local = clamp(local, vec2(0.5), source.zw - vec2(0.5));
	return texture(motion_texture, (source.xy + local) / motion_size);
}

vec4 sample_source(vec2 uv) {
	vec2 pixel = uv * 256.0;
	// ponytail: renderer clock; bind a paused scene clock when gameplay pause is implemented.
	float seconds = motion_test_time < 0.0 ? TIME : motion_test_time;
	float ticks = seconds * 30.0;
	if (!motion_smooth) {
		ticks = floor(ticks);
	}
	for (int i = 0; i < motion_count; i++) {
		vec4 dest = motion_destination[i];
		vec4 source = motion_source[i];
		vec4 timing = motion_timing[i];
		vec2 local = pixel - dest.xy;
		if (any(lessThan(local, vec2(0.0))) || any(greaterThanEqual(local, dest.zw))) {
			continue;
		}
		if (timing.w > 0.0) {
			// slot_rect_step copies two slices, advancing 2 rows every next+1 ticks.
			float step = ticks / timing.w;
			float count = ceil(source.w / 2.0);
			float offset = mod(floor(step), count) * 2.0;
			if (motion_smooth) {
				float next_offset = mod(floor(step) + 1.0, count) * 2.0;
				if (next_offset < offset) {
					next_offset += source.w;
				}
				offset = mix(offset, next_offset, fract(step));
			}
			local.y = mod(local.y - offset, source.w);
			return sample_motion(source, local, seconds);
		} else {
			float frame = mod(ticks, timing.z);
			if (frame < timing.x || frame >= timing.y) {
				continue;
			}
			vec4 current_pixel = sample_motion(source, local, seconds);
			if (motion_smooth) {
				float next_start = timing.y >= timing.z ? 0.0 : timing.y;
				for (int j = 0; j < motion_count; j++) {
					if (abs(motion_timing[j].x - next_start) < 0.001 && all(equal(motion_destination[j], dest))) {
						float blend = smoothstep(0.0, 1.0, (frame - timing.x) / (timing.y - timing.x));
						return mix(current_pixel, sample_motion(motion_source[j], local, seconds), blend);
					}
				}
			}
			return current_pixel;
		}
	}
	return texture(albedo_texture, uv);
}
