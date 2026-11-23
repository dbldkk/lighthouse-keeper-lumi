extends "res://scripts/minigames/mini_base.gd"
## Насос колодца: фланец держат шесть болтов. Фонарь по очереди выхватывает их из темноты —
## запомните порядок «звездой» и затяните в том же порядке. Из колодца в это время стучат.
var sequence: Array = []
var progress := 0
var showing := true
var show_time := 0.0
var cursor := 0
var tightened := {}
var knock_at := -1
var eyes := 0.0
const STEP := .62

func start() -> void:
	fail_kind = "noise"
	var length := 4 + (1 if day >= 7 else 0) + (1 if day >= 11 else 0)
	var pool := [0, 1, 2, 3, 4, 5]
	pool.shuffle()
	for i in length:
		sequence.append(pool[i % 6])
	_replay()

func _replay() -> void:
	showing = true
	show_time = -.4
	progress = 0
	tightened.clear()
	knock_at = randi_range(1, sequence.size() - 1)

func title() -> String:
	return "Насос колодца"

func hint() -> String:
	return "Запомните, в каком порядке свет выхватывает болты, и затяните их так же. Ошибка — фланец сорвёт, и всё сначала. Две ошибки — насос захлебнётся."

func controls() -> String:
	return "ЛКМ по болту или 1–6   ·   ←/→ + пробел   ·   Esc — отложить"

func _bolt_pos(i: int, c: Vector2) -> Vector2:
	var a := -PI * .5 + i * TAU / 6
	return c + Vector2(cos(a), sin(a)) * 110 + Vector2(0, -10)

func tick(delta: float) -> void:
	clock += delta
	eyes = move_toward(eyes, 0, delta * .5)
	if done() or not showing:
		return
	var before := int(floor(show_time / STEP))
	show_time += delta
	var now := int(floor(show_time / STEP))
	if now != before and now >= 0 and now < sequence.size():
		sfx("tick", -12, .7)
		if now == knock_at:
			sfx("knock", -8, randf_range(.85, 1.0))
			eyes = 1.0 if night() or day >= 4 else .5
	if show_time >= sequence.size() * STEP:
		showing = false

func _press(i: int) -> void:
	if done() or showing:
		return
	cursor = i
	if sequence[progress] == i:
		tightened[progress] = i
		progress += 1
		sfx("clank", -10, .8 + progress * .05)
		burst(Color("cfd6da"), 8, _bolt_pos(i, host._center()))
		if progress >= sequence.size():
			perfect = mistakes == 0
			finish(true, "Фланец держит. Насос качает — вода тёмная и ледяная." if perfect else "Насос заработал. Из трубы ещё долго что-то стучит.")
	else:
		mistakes += 1
		sfx("groan", -6, randf_range(.8, .95))
		burst(Color("7fb4c8"), 28, host._center())
		shake(.35)
		if mistakes >= 2:
			finish(false, "Фланец сорвало, насос захлебнулся. Попробуйте снова (E).")
		else:
			game.notify("Фланец повело — затягивайте заново.", 2)
			_replay()

func act() -> void:
	_press(cursor)

func key(code: int) -> bool:
	if code >= KEY_1 and code <= KEY_6:
		_press(code - KEY_1)
	elif code in [KEY_LEFT, KEY_A]:
		cursor = (cursor + 5) % 6
	elif code in [KEY_RIGHT, KEY_D]:
		cursor = (cursor + 1) % 6
	else:
		return false
	return true

func click(at: Vector2) -> void:
	var c: Vector2 = host._center()
	for i in 6:
		if at.distance_to(_bolt_pos(i, c)) < 30:
			_press(i)
			return

func draw(_box: Rect2, c: Vector2) -> void:
	var center := c + Vector2(0, -10)
	host.draw_circle(center, 150, Color(.07, .08, .08))
	host.draw_circle(center, 140, Color(.2, .21, .2))
	host.draw_circle(center, 62, Color(.03, .03, .03))
	if eyes > 0:
		host.draw_circle(center + Vector2(-14, -4), 4, Color(.9, .85, .6, eyes))
		host.draw_circle(center + Vector2(14, -4), 4, Color(.9, .85, .6, eyes))
	var lit := -1
	if showing:
		var step := int(floor(show_time / STEP))
		if step >= 0 and step < sequence.size() and fmod(show_time, STEP) < STEP * .72:
			lit = sequence[step]
	for i in 6:
		var p := _bolt_pos(i, c)
		var done_bolt := tightened.values().has(i)
		var col := Color(.45, .45, .42)
		if done_bolt:
			col = Color(.7, .72, .68)
		host.draw_circle(p, 22, col.darkened(.4))
		var angle := (PI * .25 if done_bolt else 0.0)
		var hexagon := PackedVector2Array()
		for k in 6:
			var a := angle + k * TAU / 6
			hexagon.append(p + Vector2(cos(a), sin(a)) * 16)
		host.draw_colored_polygon(hexagon, col)
		if lit == i:
			host.draw_circle(p, 30, Color(1, .9, .55, .35))
			host.draw_circle(p, 18, Color(1, .92, .6, .8))
		if not showing and cursor == i:
			host.draw_arc(p, 28, 0, TAU, 32, GOLD, 2)
		text(str(i + 1), p + Vector2(0, 46), 13, Color(PAPER, .5), HORIZONTAL_ALIGNMENT_CENTER, 40)
	# порядок
	for k in sequence.size():
		host.draw_circle(Vector2(c.x - (sequence.size() - 1) * 14 + k * 28, c.y + 190), 8, TEAL if k < progress else DIM)
	var state := "Смотрите…" if showing else "Затягивайте: %d из %d" % [progress, sequence.size()]
	text(state, Vector2(c.x, c.y + 166), 15, GOLD if showing else PAPER)
	# темнота вокруг пятна света
	if showing:
		host.draw_rect(Rect2(c.x - 330, c.y - 180, 660, 30), Color(0, 0, 0, .2))
