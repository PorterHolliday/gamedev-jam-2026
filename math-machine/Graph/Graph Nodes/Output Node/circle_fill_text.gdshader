shader_type canvas_item;

uniform float progress: hint_range(0.0, 1.0, 0.1) = 0.0;
uniform vec4 fill_color: source_color = vec4(1.0);
uniform bool invert = false;
uniform vec2 label_size = vec2(1.0, 1.0);
varying vec2 local_uv;

bool is_within_radius(vec2 point) {
	float radius = progress * 0.65;
	float radius_squared = radius * radius;
	float distance_squared = (point.x - 0.5) * (point.x - 0.5) + (point.y - 0.5) * (point.y - 0.5);
	if (distance_squared <= radius_squared) {
		return !invert;
	}
	return invert;
}

void vertex() {
	local_uv = VERTEX / label_size;
}

void fragment() {
	vec4 color = COLOR;
	if (is_within_radius(local_uv)) {
		color = (1.0 - color) * fill_color + color;
	}
	COLOR = vec4(color.rgb, color.a * COLOR.a);
}