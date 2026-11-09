shader_type canvas_item;

uniform vec4 flash_color: source_color = vec4(1.0,1.0,1.0,1.0); // The color to use when active
uniform float power: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec4 mixed_color = mix(color, flash_color, power);
	COLOR = mixed_color.rgba;
	COLOR.a = color.a;
}