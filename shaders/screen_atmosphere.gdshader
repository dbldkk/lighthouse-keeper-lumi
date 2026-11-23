shader_type canvas_item;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform float night = 0.0;
uniform float stress = 0.0;
// Ужас: fear — вспышка испуга, tension — общее напряжение, heartbeat — пульс виньетки.
uniform float fear = 0.0;
uniform float tension = 0.0;
uniform float heartbeat = 0.0;
void fragment() {
	// Этот слой рисуется до интерфейса: цветокоррекция затрагивает только мир.
	vec2 uv = SCREEN_UV;
	vec2 p = UV * 2.0 - 1.0;
	// Лёгкое «плывущее» искажение и расхождение каналов при сильном страхе.
	float warp = (stress * 0.0025 + fear * 0.006) * sin(TIME * 1.7 + p.y * 6.0);
	uv.x += warp;
	float split = fear * 0.006 + stress * 0.0015;
	vec3 scene = vec3(
		texture(scene_color, uv + vec2(split, 0.0)).r,
		texture(scene_color, uv).g,
		texture(scene_color, uv - vec2(split, 0.0)).b);
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	float highlight = smoothstep(0.48, 0.88, luminance);
	vec3 graded = mix(vec3(luminance), scene, mix(0.70, 0.60, night) * (1.0 - tension * 0.35));
	// Холодные тени; янтарные окна и фонари сохраняют свой цвет.
	graded *= mix(vec3(0.82, 0.94, 1.02), vec3(1.05, 1.01, 0.94), highlight);
	graded = max(vec3(0.0), (graded - 0.16) * 1.08 + 0.16);
	graded *= 1.0 - tension * 0.18;
	float edge = smoothstep(0.35, 1.45, length(p * vec2(0.85, 1.0)));
	float beat = heartbeat > 0.0 ? pow(max(0.0, sin(TIME * 6.2831 * mix(1.0, 2.3, heartbeat))), 6.0) : 0.0;
	float pulse = 0.5 + sin(TIME * 2.3) * 0.5;
	vec3 color = mix(vec3(0.025, 0.07, 0.08), vec3(0.22, 0.06, 0.08), clamp(stress * 0.65 + fear, 0.0, 1.0));
	float vignette = 0.12 + night * 0.14 + stress * pulse * 0.18 + tension * 0.22 + beat * heartbeat * 0.22 + fear * 0.45;
	graded = mix(graded, color, clamp(edge * vignette, 0.0, 0.92));
	graded += vec3(0.9, 0.85, 0.8) * fear * fear * 0.08;
	float grain = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233)) + floor(TIME * 12.0)) * 43758.5453) - 0.5;
	COLOR = vec4(clamp(graded + grain * (0.002 + tension * 0.03), vec3(0.0), vec3(1.0)), 1.0);
}
