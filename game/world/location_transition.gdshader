shader_type canvas_item;
uniform sampler2D screen_image : hint_screen_texture, filter_nearest;
uniform sampler2D old_frame : filter_linear;
uniform bool frozen = false;
uniform float shade = 0.0;
void fragment() {
	vec3 source = frozen ? texture(old_frame,SCREEN_UV).rgb : texture(screen_image,SCREEN_UV).rgb;
	COLOR = vec4(max(source-vec3(shade),vec3(0.0)),1.0);
}
