extends "res://scripts/minigames/mini_base.gd"
## Двигатель катера: метки зажигания падают по четырём цилиндрам — жмите цилиндр, когда метка
## на линии. Чёрные метки — не искра: в цилиндре что-то есть. Их нужно пропустить.
const TRAVEL := 1.6
const WINDOW := .15
var notes: Array = []   ## {"lane", "t", "black", "state": 0 ждёт / 1 попал / 2 мимо}
var time := 0.0
var rpm := 0.0
var flash := [0.0, 0.0, 0.0, 0.0]

func start() -> void:
	fail_kind = "noise"
	var count := 9 + mini(4, day / 3)
	var t := 1.2
	var last := -1
	for i in count:
		var lane := randi() % 4
		if lane == last:
			lane = (lane + 1 + randi() % 3) % 4
		last = lane
		var black := i >= 2 and randf() < (.12 + day * .01)
		notes.append({"lane": lane, "t": t, "black": black, "state": 0})
		t += randf_range(.5, .78) - minf(.12, day * .008)
	time = 0

func title() -> String:
	return "Двигатель катера"

func hint() -> String:
	return "Давайте искру в цилиндр, когда метка ложится на линию. Чёрные метки не трогайте: в том цилиндре что-то шевелится."

func controls() -> String:
	return "1–4 или ЛКМ по цилиндру — искра   ·   Esc — отложить"

func _lane_x(i: int, c: Vector2) -> float:
	return c.x - 150 + i * 100

func _line_y(c: Vector2) -> float:
	return c.y + 110

func tick(delta: float) -> void:
	clock += delta
	for i in 4:
		flash[i] = move_toward(flash[i], 0, delta * 3)
	if done():
		return
	time += delta
	rpm = move_toward(rpm, 0, delta * .05)
	var pending := 0
	for n in notes:
		if n.state == 0 and time - float(n.t) > WINDOW:
			n.state = 2
			if not n.black:
				_miss("Пропуск зажигания")
		if n.state == 0:
			pending += 1
	if pending == 0 and not done():
		perfect = mistakes == 0
		finish(true, "Мотор схватил и ровно затарахтел." + (" Ни одного пропуска!" if perfect else " Из трюма отвечают стуком."))

func _miss(_why: String) -> void:
	mistakes += 1
	rpm = maxf(0, rpm - .15)
	sfx("cough", -6, randf_range(.85, 1.0))
	shake(.25)
	if mistakes >= 4:
		finish(false, "Двигатель заглох и залит. Попробуйте снова (E).")

func _fire(lane: int) -> void:
	if done():
		return
	flash[lane] = 1.0
	var best: Dictionary = {}
	var gap := 99.0
	for n in notes:
		if n.state == 0 and int(n.lane) == lane and absf(time - float(n.t)) < gap:
			gap = absf(time - float(n.t))
			best = n
	if best.is_empty() or gap > WINDOW:
		_miss("Холостая искра")
		return
	best.state = 1
	if best.black:
		game.sanity = maxf(0, game.sanity - BAL.MINIGAME_DECOY_SANITY)
		sfx("knock", -4, .8)
		if is_instance_valid(game.scares):
			game.scares.jolt(.5)
		_miss("Из цилиндра стучат в ответ")
		return
	rpm = minf(1, rpm + .12)
	sfx("thump", -8, .9 + lane * .06)
	burst(Color("ffb35c"), 8, Vector2(_lane_x(lane, host._center()), _line_y(host._center())))

func key(code: int) -> bool:
	if code >= KEY_1 and code <= KEY_4:
		_fire(code - KEY_1)
		return true
	return false

func act() -> void:
	pass

func click(at: Vector2) -> void:
	var c: Vector2 = host._center()
	for i in 4:
		if absf(at.x - _lane_x(i, c)) < 45 and absf(at.y - c.y) < 200:
			_fire(i)
			return

func draw(_box: Rect2, c: Vector2) -> void:
	var top := c.y - 120
	var line := _line_y(c)
	for i in 4:
		var x := _lane_x(i, c)
		host.draw_rect(Rect2(x - 38, top, 76, line - top + 30), Color(.09, .08, .07))
		host.draw_rect(Rect2(x - 38, top, 76, line - top + 30), Color(GOLD, .15 + flash[i] * .5), false, 2)
		host.draw_rect(Rect2(x - 30, line + 34, 60, 34), Color(.25, .22, .18).lightened(flash[i] * .5))
		text(str(i + 1), Vector2(x, line + 58), 16, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 60)
	host.draw_line(Vector2(c.x - 200, line), Vector2(c.x + 200, line), Color(GOLD, .8), 3)
	for n in notes:
		if n.state != 0:
			continue
		var k := 1.0 - (float(n.t) - time) / TRAVEL
		if k < 0 or k > 1.2:
			continue
		var y := lerpf(top, line, k)
		var x := _lane_x(int(n.lane), c)
		if n.black:
			host.draw_circle(Vector2(x, y), 17, Color(0, 0, 0, .95))
			host.draw_arc(Vector2(x, y), 17, 0, TAU, 24, Color(.6, .1, .1, .7), 2)
			host.draw_circle(Vector2(x - 5, y - 2), 2, Color(.9, .2, .2))
			host.draw_circle(Vector2(x + 5, y - 2), 2, Color(.9, .2, .2))
		else:
			host.draw_circle(Vector2(x, y), 15, Color("ffcf7a"))
			host.draw_circle(Vector2(x, y), 7, Color("fff1c4"))
	# обороты
	var gauge := Rect2(c.x + 225, top, 14, line - top)
	host.draw_rect(gauge, Color(1, 1, 1, .08))
	host.draw_rect(Rect2(gauge.position.x, gauge.end.y - gauge.size.y * rpm, gauge.size.x, gauge.size.y * rpm), TEAL)
	text("об.", Vector2(gauge.get_center().x, gauge.end.y + 20), 12, Color(PAPER, .6), HORIZONTAL_ALIGNMENT_CENTER, 40)
	for i in mistakes:
		text("✗", Vector2(c.x - 230, top + 20 + i * 24), 18, RED, HORIZONTAL_ALIGNMENT_LEFT, 30)
