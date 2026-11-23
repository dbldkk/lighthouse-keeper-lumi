shader_type canvas_item;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform float night = 0.0;
uniform float stress = 0.0;
// Ужас: fear — вспышка испуга, tension — общее напряжение, heartbeat — пульс виньетки.
uniform float fear = 0.0;
uniform float tension = 0.0;
uniform float heartbeat = 0.0;
// Мрак (scripts/dread.gd): видимость вокруг смотрителя, туман на экране, сбои кадра.
uniform vec2 focus = vec2(0.5, 0.5);      // где на экране смотритель (UV)
uniform float sight = 1.0;                // радиус видимости в долях высоты экрана
uniform float dread = 0.0;                // 0 — обычная картинка, 1 — полный мрак
uniform float mist = 0.0;                 // экранный туман-клочья
uniform float glitch = 0.0;               // сбой кадра (0–1, короткие импульсы)
uniform float menu = 0.0;                 // титульный экран

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	// Этот слой рисуется до интерфейса: цветокоррекция затрагивает только мир.
	vec2 uv = SCREEN_UV;
	vec2 p = UV * 2.0 - 1.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// Сбой кадра: горизонтальные разрывы строк и сдвиг каналов.
	float band = step(0.82, hash(vec2(floor(uv.y * 38.0), floor(TIME * 24.0))));
	uv.x += glitch * band * (hash(vec2(floor(TIME * 24.0), uv.y)) - 0.5) * 0.06;
	// Лёгкое «плывущее» искажение и расхождение каналов при страхе и низком рассудке.
	float warp = (stress * 0.003 + fear * 0.006 + dread * tension * 0.002) * sin(TIME * 1.7 + p.y * 6.0);
	uv.x += warp;
	float split = fear * 0.006 + stress * 0.0035 + glitch * 0.012 + tension * 0.0012;
	vec2 dir = normalize(p + vec2(0.0001)) * length(p);
	vec3 scene = vec3(
		texture(scene_color, uv + dir * split).r,
		texture(scene_color, uv).g,
		texture(scene_color, uv - dir * split).b);
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	float highlight = smoothstep(0.42, 0.85, luminance);
	// Выцветание: днём пасмурно и серо, ночью почти монохром; свет фонарей сохраняет цвет.
	float sat = mix(mix(0.70, 0.60, night), mix(0.42, 0.30, night), dread) * (1.0 - tension * 0.35);
	vec3 graded = mix(vec3(luminance), scene, mix(sat, 0.85, highlight * dread));
	// Холодные болезненно-зелёные тени и сине-стальные полутона.
	vec3 shadow_tint = mix(vec3(0.82, 0.94, 1.02), vec3(0.74, 0.90, 0.86), dread);
	graded *= mix(shadow_tint, vec3(1.05, 1.0, 0.92), highlight);
	graded = max(vec3(0.0), (graded - 0.16) * mix(1.08, 1.18, dread) + 0.16 - dread * 0.03);
	graded *= 1.0 - tension * 0.18;
	// Видимость: тёмное вокруг смотрителя тонет во мраке, яркий свет (луч, фонари) пробивает его.
	vec2 d = (SCREEN_UV - focus) * vec2(aspect, 1.0);
	float r = length(d);
	float blind = smoothstep(sight * 0.55, sight * 1.25, r) * dread;
	float pierce = smoothstep(0.30, 0.75, luminance);
	vec3 murk = mix(vec3(0.020, 0.032, 0.036), vec3(0.008, 0.014, 0.018), night);
	graded = mix(graded, murk, blind * (1.0 - pierce * 0.85) * mix(0.55, 0.84, night));
	// Экранный туман: медленные клочья, гуще по краям видимости.
	vec2 q = SCREEN_UV * vec2(aspect, 1.0) * 3.0;
	float wisps = fbm(q + vec2(TIME * 0.035, TIME * 0.012)) * fbm(q * 0.6 - vec2(TIME * 0.02, 0.0));
	float fogamt = mist * smoothstep(0.08, 0.45, wisps) * (0.35 + 0.65 * smoothstep(sight * 0.3, sight * 1.1, r));
	vec3 fogcol = mix(vec3(0.42, 0.47, 0.46), vec3(0.09, 0.12, 0.13), night);
	graded = mix(graded, fogcol, clamp(fogamt, 0.0, 0.75) * (1.0 - pierce * 0.5));
	// Виньетка с пульсом сердца.
	float edge = smoothstep(0.35, 1.45, length(p * vec2(0.85, 1.0)));
	float beat = heartbeat > 0.0 ? pow(max(0.0, sin(TIME * 6.2831 * mix(1.0, 2.3, heartbeat))), 6.0) : 0.0;
	float pulse = 0.5 + sin(TIME * 2.3) * 0.5;
	vec3 color = mix(vec3(0.015, 0.045, 0.05), vec3(0.22, 0.04, 0.06), clamp(stress * 0.65 + fear, 0.0, 1.0));
	float vignette = 0.12 + night * 0.14 + dread * 0.22 + menu * 0.15 + stress * pulse * 0.18 + tension * 0.22 + beat * heartbeat * 0.22 + fear * 0.45;
	graded = mix(graded, color, clamp(edge * vignette, 0.0, 0.94));
	graded += vec3(0.9, 0.85, 0.8) * fear * fear * 0.08;
	// Сбой: короткая вспышка/провал яркости кадра.
	graded *= 1.0 - glitch * 0.45 * step(0.5, hash(vec2(floor(TIME * 30.0), 3.0)));
	// Плёночное зерно и редкие царапины.
	float grain = hash(floor(FRAGCOORD.xy) + floor(TIME * 24.0) * 1.7) - 0.5;
	float scratch = step(0.9985, hash(vec2(floor(FRAGCOORD.x * 0.5), floor(TIME * 12.0)))) * dread * 0.08;
	graded += grain * (0.004 + dread * 0.035 + tension * 0.03) + scratch;
	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), 1.0);
}
