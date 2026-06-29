shader_type canvas_item;

uniform float progress: hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float normal_x: hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float normal_y: hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float next_shadow_size: hint_range(0.0, 10.0, 0.01) = 0.5;
uniform vec4 next_shadow_color: source_color = vec4(0.0);
uniform vec4 back_color: source_color = vec4(1.0);
uniform float back_shadow_size: hint_range(0.0, 10.0, 0.01) = 2.0;
uniform vec4 back_shadow_color: source_color = vec4(0.0);

void fragment() {
	vec2 uv = UV;
	vec2 resolution = 1.0 / TEXTURE_PIXEL_SIZE;
	vec4 color = texture(TEXTURE, UV);
	vec2 aspect = vec2(resolution.x / resolution.y, 1.0);
	
	vec2 fold = vec2(1.0 - progress, 1.0 - progress) * aspect;
	vec2 normal = normalize(vec2(normal_x, normal_y) * aspect);
	vec2 page_uv = uv * aspect - fold;
	float page_side = dot(page_uv, normal);
	if (page_side > 0.0) {
		float shadow = smoothstep(0.0, next_shadow_size * 0.1, page_side);
		color = mix(next_shadow_color, vec4(0.0), shadow);
	} else {
		vec2 flip_uv = (uv * aspect - 2.0 * page_side * normal) / aspect;
		if (flip_uv.x >= 0.0 && flip_uv.x <= 1.0 &&
			flip_uv.y >= 0.0 && flip_uv.y <= 1.0) {
				float shadow = smoothstep(0.0, back_shadow_size * 0.1, page_side);
				color = back_color + mix(back_shadow_color, back_color, shadow);
			}
	}
	COLOR = color;
}