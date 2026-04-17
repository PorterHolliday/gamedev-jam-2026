shader_type canvas_item;

uniform sampler2D pencil_texture : repeat_enable, filter_linear;
uniform vec2 pencil_scale = vec2(3.0, 3.0);
uniform float pencil_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec3 color : source_color = vec3(0.0);

void fragment() {
    vec4 base = texture(TEXTURE, UV);

    vec2 pencil_uv = 1.0 - SCREEN_UV * pencil_scale;
    float pencil = texture(pencil_texture, pencil_uv).r;
	
    vec3 inverted = 1.0 - base.rgb;
    vec3 result = 1.0 - (inverted + mix(vec3(1.0), vec3(pencil), 1.0 - pencil_strength));
	result = result + color;

    COLOR = vec4(result, base.a);
}