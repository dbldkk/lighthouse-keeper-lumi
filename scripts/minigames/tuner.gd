extends "res://scripts/minigames/mini_base.gd"
## Передатчик: поймайте три контура несущей частоты и удержите стрелку, пока сигнал не
## «защёлкнется». Рядом с настоящей частотой прячется чужой голос — на нём задерживаться нельзя.
var freq := 0.5
var targets: Array = []
var band := 0
var lock := 0.0
var window := 0.04
var decoy := 0.0
var decoy_time := 0.0
var time_left := 22.0
var static_clock := 0.0
var dragging := false

func start() -> void:
	fail_kind = "static"
	for i in 3:
		targets.append(randf_range(.12, .88))
	window = clampf(.05 - day * .0015, .03, .05)
	freq = .5
	_new_decoy()
	time_left = 24.0

func _new_decoy() -> void:
	var t: float = targets[mini(band, 2)]
	decoy = clampf(t + (randf_range(.12, .22) * (1.0 if randf() < .5 else -1.0)), .05, .95)

func title() -> String:
	return "Настройка передатчика"

func hint() -> String:
	return "Ведите стрелку по шкале и ищите чистую волну. Удержите её, пока контур не защёлкнется. Если в шуме слышен шёпот — уходите с этой частоты."

func controls() -> String:
	return "A/D или ←/→ — частота   ·   зажмите ЛКМ и ведите мышью   ·   Esc — отложить"

func target() -> float:
	return float(targets[mini(band, 2)]) + sin(clock * .7 + band) * .015

func quality() -> float:
	return clampf(1.0 - absf(freq - target()) / .22, 0, 1)

func on_decoy() -> bool:
	return absf(freq - decoy) < .03

func tick(delta: float) -> void:
	clock += delta
	if done():
		return
	time_left -= delta
	freq = clampf(freq + axis() * delta * .32, 0, 1)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var c: Vector2 = host._center()
		var m: Vector2 = host.get_local_mouse_position()
		if absf(m.y - (c.y + 90)) < 70 or dragging:
			dragging = true
			freq = clampf((m.x - (c.x - 240)) / 480.0, 0, 1)
	else:
		dragging = false
	var inside := absf(freq - target()) < window
	lock = clampf(lock + (delta if inside else -delta * 1.6), 0, 1.4)
	static_clock -= delta
	if static_clock <= 0 and not inside:
		static_clock = randf_range(.5, 1.1)
		sfx("static", lerpf(-14, -24, quality()), randf_range(.9, 1.1))
	if on_decoy():
		decoy_time += delta
		if decoy_time > .25 and fmod(decoy_time, 1.0) < delta:
			sfx("whisper", -10, randf_range(.85, 1.0))
		if decoy_time > 1.2:
			mistakes += 1
			decoy_time = 0
			game.sanity = maxf(0, game.sanity - BAL.MINIGAME_DECOY_SANITY)
			shake(.3)
			if is_instance_valid(game.scares):
				game.scares.jolt(.6)
			_new_decoy()
	else:
		decoy_time = maxf(0, decoy_time - delta)
	if lock >= 1.3:
		band += 1
		lock = 0
		sfx("clank", -12, .7 + band * .1)
		burst(TEAL, 14)
		if band >= 3:
			perfect = mistakes == 0
			finish(true, "Все три контура держат. Эфир чист… почти." if perfect else "Передатчик настроен. В эфире кто-то дышит.")
			return
		_new_decoy()
	if time_left <= 0:
		finish(false, "Лампы перегорели в треске помех. Попробуйте снова (E).")

func draw(_box: Rect2, c: Vector2) -> void:
	# осциллограф
	var scope := Rect2(c.x - 240, c.y - 120, 480, 170)
	host.draw_rect(scope, Color(.02, .07, .05))
	for gx in 9:
		host.draw_line(Vector2(scope.position.x + gx * 60, scope.position.y), Vector2(scope.position.x + gx * 60, scope.end.y), Color(.2, .5, .35, .12), 1)
	for gy in 4:
		host.draw_line(Vector2(scope.position.x, scope.position.y + gy * 56), Vector2(scope.end.x, scope.position.y + gy * 56), Color(.2, .5, .35, .12), 1)
	var q := quality()
	var ghost := clampf(1.0 - absf(freq - decoy) / .05, 0, 1)
	var pts := PackedVector2Array()
	for i in 121:
		var x := float(i) / 120.0
		var clean := sin(x * TAU * 3 + clock * 6) * q
		var noise := randf_range(-1, 1) * (1.0 - q) * .8
		var voice := sin(x * TAU * 11 + clock * 20) * sin(x * PI * 2) * ghost * .9
		var y := clampf(clean * .7 + noise + voice, -1, 1)
		pts.append(Vector2(scope.position.x + x * scope.size.x, scope.get_center().y + y * 70))
	var trace := Color("7dffb0").lerp(Color("ff6a6a"), ghost)
	host.draw_polyline(pts, Color(trace, .85), 2)
	if ghost > .6:
		# в шуме проступает лицо
		var f := scope.get_center()
		host.draw_circle(f + Vector2(-26, -14), 6, Color(1, .4, .4, ghost * .5))
		host.draw_circle(f + Vector2(26, -14), 6, Color(1, .4, .4, ghost * .5))
		host.draw_arc(f + Vector2(0, 30), 26, PI * 1.1, PI * 1.9, 16, Color(1, .4, .4, ghost * .4), 3)
	host.draw_rect(scope, Color(.3, .6, .45, .4), false, 2)
	# шкала
	var dial := Rect2(c.x - 240, c.y + 76, 480, 28)
	host.draw_rect(dial, Color(.12, .1, .07))
	for i in 49:
		var x := dial.position.x + i * 10
		host.draw_line(Vector2(x, dial.position.y), Vector2(x, dial.position.y + (12 if i % 4 == 0 else 6)), Color(GOLD, .5), 1)
	var nx := dial.position.x + freq * dial.size.x
	host.draw_line(Vector2(nx, dial.position.y - 8), Vector2(nx, dial.end.y + 8), RED, 3)
	text("%.1f МГц" % (2.0 + freq * 6.0), Vector2(c.x, dial.end.y + 26), 15, PAPER)
	# контуры и захват
	for i in 3:
		host.draw_circle(Vector2(c.x - 40 + i * 40, c.y + 160), 10, TEAL if i < band else DIM)
	var lb := Rect2(c.x - 120, c.y + 182, 240, 8)
	host.draw_rect(lb, Color(1, 1, 1, .08))
	host.draw_rect(Rect2(lb.position, Vector2(lb.size.x * clampf(lock / 1.3, 0, 1), lb.size.y)), TEAL)
	text("Лампы остынут через %d с" % ceili(maxf(0, time_left)), Vector2(c.x, c.y + 210), 12, Color(PAPER, .55))
