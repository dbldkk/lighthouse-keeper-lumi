extends SceneTree
## Регрессия (v1.2: «охотник появляется и стоит»): в настоящей сцене за ночь он ходит,
## замечает, догоняет и ловит, отступает от света, ломится в дверь и уходит на рассвете.
var game: Node
var h: Node3D
var checks := 0
var failures := 0
const DT := 1.0 / 30.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func night(lit: bool) -> void:
	game.day = 4
	game.campaign.state.day = 4
	game.campaign.state.night = true
	game.hour = 22
	game.lighthouse_on = lit
	game.beacon.set_powered(lit)
	game.paused = false

## Симуляция без ожидания кадров: шаг ИИ охотника. Возвращает собранную статистику.
func simulate(seconds: float, stop_on_catch := false) -> Dictionary:
	var states := {}
	var moved := 0.0
	var prev: Vector3 = h.body.global_position
	var still := 0.0
	var worst_still := 0.0
	var catches0: int = h.catches
	var t := 0.0
	while t < seconds:
		h._process(DT)
		t += DT
		states[h.state] = true
		var p: Vector3 = h.body.global_position
		var step := Vector2(p.x - prev.x, p.z - prev.z).length()
		if h.space.is_empty() and step < 5.0:
			moved += step
		var resting: bool = (h.state == "search" and h.sniff_time > 0) or h.door_clock > 0 or not h.space.is_empty()
		still = 0.0 if step > DT * .3 or resting else still + DT
		worst_still = maxf(worst_still, still)
		prev = p
		if stop_on_catch and h.catches > catches0:
			break
	return {"states": states, "moved": moved, "still": worst_still, "catches": h.catches - catches0, "t": t}

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_hunter_night.json"
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	h = game.hunter
	h.rng.seed = 4242   # обход случайный; фиксируем зерно, чтобы тест был воспроизводимым
	game.night_raids.set_process(false)
	# 1. точка появления/бегства никогда не в свете маяка (причина бага v1.2)
	night(true)
	var lit_spawns := 0
	for i in 60:
		if h._in_light(h._far_point(28.0)):
			lit_spawns += 1
	check(lit_spawns == 0, "Охотник не появляется в круге света маяка (%d из 60)" % lit_spawns)
	# 2. ночь у горящего маяка: смотритель стоит на открытом месте с фонарём
	game.player.global_position = Vector3(3, 1.2, 4)
	game.player.lantern_on = true
	game.health = 100
	h.reset()
	var r := simulate(80.0, true)
	print("lit night: ", r)
	check(h.active, "С наступлением ночи охотник вышел")
	check(r.moved > 12.0, "Он ходит, а не стоит (%.0f м)" % r.moved)
	check(r.states.has("patrol") and r.states.has("chase"), "Обход → погоня: %s" % [r.states.keys()])
	check(r.catches >= 1 and game.health < 100, "Догнал и схватил того, кто не прятался (%.0f с)" % r.t)
	check(h.state == "flee", "После броска отступает, давая опомниться")
	check(r.still < 5.0, "Нигде не застревает дольше 5 с (%.1f с)" % r.still)
	game.health = 100
	# 3. в темноте: тоже ходит и находит
	night(false)
	h.reset()
	game.player.global_position = Vector3(3, 1.2, 4)
	r = simulate(60.0, true)
	print("dark night: ", r)
	check(r.moved > 12.0 and r.catches >= 1, "Без маяка тоже приходит и ловит (%.0f м, %.0f с)" % [r.moved, r.t])
	game.health = 100
	# 4. свет маяка отгоняет — и он не замирает внутри круга
	night(true)
	h._set_state("patrol")
	h.body.global_position = Vector3(-6, 1, -4)
	h.target = h.body.global_position
	h.catches = 0
	h.mercy_time = 0
	r = simulate(12.0)
	check(not h._in_light(h.body.global_position) and r.states.has("flee"), "Из круга света уходит, а не стоит в нём")
	# если за это время он успел снова найти и схватить смотрителя — после броска законно отступает
	check(h.state in ["patrol", "investigate", "chase", "search"] or (h.state == "flee" and r.catches > 0), "Потом снова охотится (%s, бросков %d)" % [h.state, r.catches])
	# 5. луч фонаря (ПКМ) — отступает
	night(false)
	game.player.global_position = Vector3(3, 1.2, 4)
	h._set_state("chase")
	h.repel_time = 0
	h.body.global_position = Vector3(3, 1, 10)
	game.lantern_beam.focusing = true
	game.lantern_beam.aim = Vector3(0, 0, 1)
	var fled := false
	for i in 90:
		h.body.global_position = Vector3(3, h.body.global_position.y, 10)
		h._tick_outside(DT)
		if h.state == "flee":
			fled = true
			break
	game.lantern_beam.focusing = false
	check(fled, "Луч фонаря в упор — отступает")
	# 6. ломится в дверь и входит
	h._set_state("chase")
	h.repel_time = 0
	var door: Vector3 = game.building_interiors.exit_at("cabin")
	h.body.global_position = door + Vector3(6, 0, 2)
	game.enter_building("cabin")
	await frames(1)
	var knocks := 0
	var t := 0.0
	var was := 0.0
	while t < 20.0 and h.space.is_empty():
		h._process(DT)
		if h.door_clock > 0 and int(was / .7) != int(h.door_clock / .7):
			knocks += 1
		was = h.door_clock
		if OS.has_environment("HN_DEBUG") and int(t * 2) != int((t + DT) * 2):
			print("dbg t=%.1f st=%s pos=%s tgt=%s door=%.2f dd=%.1f out=%s" % [t, h.state, h.body.global_position, h.target, h.door_clock, h._flat(h.body.global_position, door), h._player_outside()])
		t += DT
	check(knocks >= 2, "Бьёт в дверь (%d ударов)" % knocks)
	check(h.space == "cabin", "Входит в хижину за смотрителем (%.1f с)" % t)
	game.exit_building()
	await frames(1)
	h.space = ""
	# 6б. баланс v1.3: два броска подряд не наносят урон дважды — после броска 25 с передышки
	h.mercy_time = 0
	game.health = 100
	h._catch()
	var after_first: float = game.health
	h._catch()
	check(after_first < 100 and game.health == after_first and h.state == "flee", "Второй бросок сразу после первого — только замах и отступление (%.0f → %.0f)" % [after_first, game.health])
	h.mercy_time = 0
	h._catch()
	check(game.health < after_first, "После передышки снова опасен")
	game.health = 100
	# 7. рассвет — уходит
	game.campaign.state.night = false
	h._process(DT)
	check(not h.active and not h.body.visible, "На рассвете уходит")
	print("HUNTER_NIGHT_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
