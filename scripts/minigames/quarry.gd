extends "res://scripts/minigames/mini_base.gd"
## Каменоломня: прицел пляшет от усталости и холода. Ведите его к светлой трещине и бейте.
## Каждый промах — звонкий удар по камню, который слышно далеко в темноте.
var aim := Vector2.ZERO
var cracks: Array = []
var hits := 0
var cooldown := 0.0
var last_mouse := Vector2.ZERO
var swing := 0.0
var face := 0.0

func start() -> void:
	fail_kind = "noise"
	aim = host._center()
	last_mouse = host.get_local_mouse_position()
	for i in 3:
		cracks.append(host._center() + Vector2(randf_range(-150, 150), randf_range(-80, 70)))

func title() -> String:
	return "Каменоломня"

func hint() -> String:
	return "Прицел дрожит. Подведите его к светящейся трещине и бейте киркой. Три точных удара — камень расколется. Промахи гулко разносятся по острову."

func controls() -> String:
	return "Мышь или WASD — прицел   ·   Пробел / ЛКМ — удар   ·   Esc — отложить"

func sway() -> Vector2:
	var k := 1.0 + mistakes * .25 + (.3 if night() else 0.0)
	return Vector2(sin(clock * 1.7) * 38 + sin(clock * 4.3) * 9, sin(clock * 2.3 + 1.0) * 24 + cos(clock * 5.1) * 6) * k

func crosshair() -> Vector2:
	return aim + sway()

func tick(delta: float) -> void:
	clock += delta
	cooldown = maxf(0, cooldown - delta)
	swing = maxf(0, swing - delta * 4)
	face = maxf(0, face - delta)
	if done():
		return
	var m: Vector2 = host.get_local_mouse_position()
	if m.distance_to(last_mouse) > .5:
		aim = m
	last_mouse = m
	aim += axis2() * 260 * delta
	var c: Vector2 = host._center()
	aim = aim.clamp(c - Vector2(250, 150), c + Vector2(250, 130))

func act() -> void:
	if done() or cooldown > 0:
		return
	cooldown = .45
	swing = 1.0
	var target: Vector2 = cracks[hits]
	if crosshair().distance_to(target) < 28:
		hits += 1
		sfx("pick", -6, randf_range(.9, 1.05))
		burst(Color("d9d2c0"), 16, target)
		shake(.2)
		if hits >= 3:
			perfect = mistakes == 0
			if randf() < .35:
				face = 1.2
			finish(true, "Камень раскололся. Внутри — пустота, будто кто-то там жил." if perfect else "Готово. Эхо ударов ещё долго гуляет между скал.")
	else:
		mistakes += 1
		sfx("clank", -4, randf_range(.6, .75))
		burst(Color(.6, .6, .6), 10, crosshair())
		shake(.3)
		if mistakes >= 3:
			finish(false, "Кирка соскользнула, звон разнёсся по скалам. Попробуйте снова (E).")

func click(_at: Vector2) -> void:
	act()

func draw(_box: Rect2, c: Vector2) -> void:
	var rock := PackedVector2Array()
	for i in 14:
		var a := i * TAU / 14
		rock.append(c + Vector2(cos(a) * (250 + sin(i * 3.1) * 22), sin(a) * (150 + cos(i * 2.2) * 16)) + Vector2(0, -6))
	host.draw_colored_polygon(rock, Color(.24, .24, .23))
	for i in 9:
		var p := c + Vector2(-200 + i * 50, -60 + sin(i * 1.7) * 60)
		host.draw_line(p, p + Vector2(30, 18), Color(.15, .15, .14), 2)
	for i in cracks.size():
		var p: Vector2 = cracks[i]
		if i < hits:
			host.draw_line(p + Vector2(-30, -20), p + Vector2(30, 24), Color(.05, .05, .05), 6)
			continue
		var glow := (.5 + .5 * sin(clock * 5)) if i == hits else .1
		host.draw_line(p + Vector2(-22, -14), p + Vector2(4, 2), Color(1, .85, .55, .25 + glow * .6), 4)
		host.draw_line(p + Vector2(4, 2), p + Vector2(18, 16), Color(1, .85, .55, .25 + glow * .6), 3)
		if i == hits:
			host.draw_circle(p, 28, Color(1, .85, .5, .07 + glow * .08))
	if face > 0:
		var f: Vector2 = cracks[mini(hits, 2)]
		host.draw_circle(f + Vector2(-8, 0), 3, Color(1, 1, .9, face * .7))
		host.draw_circle(f + Vector2(8, 0), 3, Color(1, 1, .9, face * .7))
	var x := crosshair()
	var col := GOLD if cooldown <= 0 else Color(GOLD, .4)
	host.draw_arc(x, 16, 0, TAU, 24, col, 2)
	host.draw_line(x + Vector2(-26, 0), x + Vector2(-8, 0), col, 2)
	host.draw_line(x + Vector2(8, 0), x + Vector2(26, 0), col, 2)
	host.draw_line(x + Vector2(0, -26), x + Vector2(0, -8), col, 2)
	host.draw_line(x + Vector2(0, 8), x + Vector2(0, 26), col, 2)
	if swing > 0:
		host.draw_line(x + Vector2(60, -80) * swing, x, Color(.6, .55, .5, swing), 6)
	for i in 3:
		host.draw_circle(Vector2(c.x - 40 + i * 40, c.y + 176), 10, TEAL if i < hits else DIM)
	for i in mistakes:
		text("✗", Vector2(c.x + 80 + i * 22, c.y + 184), 20, RED, HORIZONTAL_ALIGNMENT_LEFT, 30)
