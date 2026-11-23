shader_type canvas_item;
// Калибровка яркости: почти чёрный силуэт маяка на чёрном фоне, пропущенный через те же яркость и гамму,
// что и экранный шейдер мрака. Правильная настройка — символ едва виден.
uniform float brightness = 1.0;
uniform float gamma = 1.0;
uniform float symbol = 0.034;
uniform float ground = 0.010;

float box(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

void fragment() {
	vec2 p = UV;
	// башня-трапеция
	float y = p.y;
	float half_w = mix(0.07, 0.15, smoothstep(0.32, 0.86, y));
	float tower = step(abs(p.x - 0.5), half_w) * step(0.32, y) * step(y, 0.86);
	float gallery = box(p, vec2(0.33, 0.28), vec2(0.67, 0.32));
	float lamp = box(p, vec2(0.40, 0.16), vec2(0.60, 0.28));
	float roof = step(abs(p.x - 0.5), (y - 0.08) * 1.2) * step(0.08, y) * step(y, 0.16);
	float ground_line = box(p, vec2(0.18, 0.86), vec2(0.82, 0.90));
	float a = clamp(tower + gallery + lamp + roof + ground_line, 0.0, 1.0);
	vec3 c = vec3(mix(ground, symbol, a));
	c = pow(c, vec3(1.0 / max(gamma, 0.1))) * brightness;
	COLOR = vec4(c, 1.0);
}
