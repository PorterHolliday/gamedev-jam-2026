shader_type canvas_item;

uniform float progress: hint_range(0.0, 1.0, 0.1) = 0.0;
uniform vec4 fill_color: source_color = vec4(1.0);
uniform bool invert = false;

bool is_within_radius(vec2 point) {
	float radius = progress * 0.65;
	float radius_squared = radius * radius;
	float distance_squared = (point.x - 0.5) * (point.x - 0.5) + (point.y - 0.5) * (point.y - 0.5);
	if (distance_squared <= radius_squared) {
		return !invert;
	}
	return invert;
}

void fragment() {
	vec4 color = COLOR;
	if (is_within_radius(UV)) {
		color = color * fill_color;
	}
	COLOR = vec4(color.rgb, color.a * COLOR.a);
}