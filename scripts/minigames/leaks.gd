extends "res://scripts/minigames/mini_base.gd"
## Пробоина корпуса: в обшивке открываются течи — забейте каждую двумя ударами молотка, пока
## вода не поднялась. Иногда из дыры лезет не вода, а бледная рука: её не трогайте, ждите.
const SLOTS := 6
const GOAL := 6
var holes: Array = []   ## {"state": 0 закрыто / 1 течь / 2 рука, "hits", "time"}
var water := 0.0
var patched := 0
var spawn := .6
var grabs := 0

func start() -> void:
	fail_kind = "grab"
	for i in SLOTS:
		holes.append({"state": 0, "hits": 0, "time": 0.0})

func title() -> String:
	return "Пробоина корпуса"

func hint() -> String:
	return "Забивайте течи — по два удара молотком. Не давайте воде подняться до черты. Если из дыры тянется рука — не бейте, дождитесь, пока она уйдёт."

func controls() -> String:
	return "ЛКМ по течи или 1–6 — удар молотком   ·   Esc — отложить"

func _slot_pos(i: int, c: Vector2) -> Vector2:
	return c + Vector2(-170 + (i % 3) * 170, -70 + (i / 3) * 120)

func tick(delta: float) -> void:
	clock += delta
	if done():
		return
	spawn -= delta
	var open := 0
	for h in holes:
		if h.state != 0:
			h.time += delta
		if h.state == 1:
			open += 1
		if h.state == 2 and h.time > 1.7:
			h.state = 0
			h.time = 0
	if spawn <= 0 and patched + open < GOAL + 2:
		spawn = maxf(.75, 1.5 - day * .04) * randf_range(.8, 1.2)
		var free: Array = []
		for i in SLOTS:
			if holes[i].state == 0:
				free.append(i)
		if not free.is_empty():
			var h: Dictionary = holes[free[randi() % free.size()]]
			var hand := open > 0 and randf() < clampf(.12 + day * .012, .12, .3)
			h.state = 2 if hand else 1
			h.hits = 0
			h.time = 0
			sfx("creak" if hand else "splash", -10, randf_range(.8, 1.1))
	water = minf(1.0, water + delta * open * BAL.MINIGAME_LEAK_RATE)
	if water >= 1.0:
		finish(false, "Вода залила трюм. Вычерпайте и попробуйте снова (E).")
		fail_kind = "noise"

func _hit(i: int) -> void:
	if done():
		return
	var h: Dictionary = holes[i]
	var at := _slot_pos(i, host._center())
	match int(h.state):
		1:
			h.hits += 1
			sfx("hammer", -7, randf_range(.9, 1.1))
			burst(Color("c9a46a"), 6, at)
			if h.hits >= 2:
				h.state = 0
				h.time = 0
				patched += 1
				water = maxf(0, water - .04)
				if patched >= GOAL:
					perfect = grabs == 0 and water < .5
					finish(true, "Пробоина заделана. За бортом кто-то медленно уходит на дно." if perfect else "Корпус держит. На досках остались следы пальцев.")
		2:
			grabs += 1
			mistakes += 1
			h.state = 0
			game.sanity = maxf(0, game.sanity - BAL.MINIGAME_DECOY_SANITY)
			sfx("stinger", -8, .9)
			shake(.6)
			if is_instance_valid(game.scares):
				game.scares.jolt(.8)
			burst(Color(.85, .85, .8), 20, at)
			if grabs >= 2:
				finish(false, "Ледяная рука вцепилась в запястье и тянет вниз! Вырвались… (E)")
		_:
			sfx("hammer", -14, 1.3)

func key(code: int) -> bool:
	if code >= KEY_1 and code <= KEY_6:
		_hit(code - KEY_1)
		return true
	return false

func act() -> void:
	# пробел бьёт по первой течи — для клавиатуры без мыши
	for i in SLOTS:
		if holes[i].state == 1:
			_hit(i)
			return

func click(at: Vector2) -> void:
	var c: Vector2 = host._center()
	for i in SLOTS:
		if at.distance_to(_slot_pos(i, c)) < 46:
			_hit(i)
			return

func draw(_box: Rect2, c: Vector2) -> void:
	var hull := Rect2(c.x - 260, c.y - 140, 520, 260)
	for row in 7:
		var r := Rect2(hull.position.x, hull.position.y + row * 37, hull.size.x, 35)
		host.draw_rect(r, Color(.22, .16, .1).darkened(row % 2 * .15))
	for i in SLOTS:
		var p := _slot_pos(i, c)
		var h: Dictionary = holes[i]
		host.draw_circle(p, 26, Color(.04, .03, .02))
		match int(h.state):
			1:
				var spray := 0.6 + .4 * sin(clock * 30 + i)
				host.draw_circle(p, 22 * spray, Color(.35, .55, .6, .8))
				for k in 4:
					var d := Vector2(randf_range(-1, 1), randf_range(.2, 1)).normalized() * randf_range(20, 60)
					host.draw_line(p, p + d, Color(.5, .7, .75, .5), 2)
				for k in int(h.hits):
					host.draw_rect(Rect2(p + Vector2(-30, -6 + k * 10), Vector2(60, 8)), Color(.55, .4, .25))
			2:
				var reach := clampf(h.time / .4, 0, 1) * (1.0 - clampf((h.time - 1.3) / .4, 0, 1))
				var palm := p + Vector2(0, -30 * reach)
				host.draw_line(p, palm, Color(.8, .82, .78), 14)
				for f in 4:
					host.draw_line(palm, palm + Vector2(-12 + f * 8, -22 * reach), Color(.85, .87, .82), 4)
			_:
				pass
		text(str(i + 1), p + Vector2(0, 48), 12, Color(PAPER, .45), HORIZONTAL_ALIGNMENT_CENTER, 30)
	# вода поднимается снизу
	var wh := hull.size.y * water
	host.draw_rect(Rect2(hull.position.x, hull.end.y - wh, hull.size.x, wh), Color(.05, .16, .2, .7))
	host.draw_line(Vector2(hull.position.x, hull.position.y + 10), Vector2(hull.end.x, hull.position.y + 10), Color(RED, .6), 2)
	text("Заделано %d из %d" % [patched, GOAL], Vector2(c.x, hull.end.y + 30), 15, PAPER)
