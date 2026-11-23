extends SceneTree
## v1.3: особые ночи (шторм с обрывом питания, туман, сейнер у камней, ложный «спасатель»)
## и второй враг — то, что живёт под причалом.
var game: Node
var ev: Node
var lk: Node
var checks := 0
var failures := 0
const DT := .1

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

func night(day: int) -> void:
	game.day = day
	game.campaign.ensure_day()
	game.campaign.state.night = true
	game.campaign.state.night_clock = 0
	game.hour = 21
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.health = 100
	game.sanity = 100

func run_events(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ev.tick(DT)
		t += DT

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_night_events.json"
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	game.night_raids.set_process(false)
	game.hunter.set_process(false)
	ev = game.night_events
	lk = game.water_lurker
	ev.set_process(false)
	lk.set_process(false)
	game.achievements.unlocked.clear()
	# расписание
	var c = game.campaign
	var plan := {}
	for d in range(1, c.calendar_days() + 1):
		game.day = d
		var e: String = ev.event_for(d, str(c.entry().night.kind))
		if not e.is_empty():
			plan[e] = plan.get(e, []) + [d]
	print("plan ", plan)
	check(plan.has("storm") and plan.has("fog") and plan.has("ship") and plan.has("rescuer"), "Все четыре особые ночи есть в кампании: %s" % [plan])
	check(ev.event_for(1, "storm") == "" and ev.event_for(2, "storm") == "", "Первые ночи — без особых событий")
	# --- шторм
	night(plan.storm[0])
	ev.tick(DT)
	check(ev.event == "storm", "Ночь шторма распознана")
	run_events(ev.outage_at() + .5)
	check(not game.lighthouse_on and c.state.blackout and not c.state.event_done, "Шторм оборвал питание: маяк погас, задание — генератор")
	check(c.night_instruction().find("генератор") >= 0, "Подсказка ведёт к генератору: %s" % c.night_instruction())
	c.restore_beacon()
	ev.tick(DT)
	check(game.lighthouse_on and ev.result == "restored", "Генератор перезапущен — свет вернулся")
	# --- туман
	night(plan.fog[0])
	run_events(8.0)
	check(ev.event == "fog" and ev.fog_strength() > .99, "Туман сгустился (%.2f)" % ev.fog_strength())
	# --- сейнер: вовремя подали сигналы
	night(plan.ship[0])
	ev.tick(DT)
	check(ev.event == "ship" and is_instance_valid(ev.ship) and is_instance_valid(ev.lamp), "Сейнер, камни и сигнальный фонарь на месте")
	game.player.global_position = ev.SIGNAL_LAMP + Vector3(.5, .3, 0)
	check(ev.near_lamp() and ev.prompt().find("сигнал") >= 0, "У фонаря подсказка: %s" % ev.prompt())
	var signals := 0
	var t := 0.0
	while t < 120 and ev.result.is_empty():
		ev.tick(DT)
		t += DT
		if ev.danger >= 0 and ev.danger_time > 1.0:
			ev.signal_ship()
			signals += 1
	check(ev.result == "saved" and signals == 3, "Сигнал у каждого из трёх камней — сейнер спасён (%s, %d сигналов, %.0f с)" % [ev.result, signals, t])
	check(game.achievements.has("ship_guided"), "Достижение «Лоцман»")
	# --- сейнер: без сигналов разбивается
	ev.force("ship")
	var sanity0: float = game.sanity
	t = 0.0
	while t < 120 and ev.result.is_empty():
		ev.tick(DT)
		t += DT
	check(ev.result == "lost" and game.sanity < sanity0, "Без сигнала сейнер садится на камни, рассудок падает")
	# --- «спасатель»: не открыли
	night(plan.rescuer[0])
	game.enter_building("cabin")
	await frames(1)
	ev.tick(DT)
	check(ev.event == "rescuer", "Ночь ложного спасателя")
	run_events(ev.RESCUER_START + 1)
	check(ev.rescuer_active(), "Стучат в дверь")
	run_events(ev.RESCUER_SECONDS)
	check(ev.result == "shut" and game.achievements.has("door_shut") and game.health == 100, "Не открыли — стук стих, достижение «Не открывай»")
	# --- «спасатель»: открыли
	ev.force("rescuer")
	ev.clock = ev.RESCUER_START + 1
	ev.tick(DT)
	game.player.position = game.building_interiors.exit_at("cabin")
	game.enter_building("cabin")
	await frames(1)
	# встать к двери изнутри
	var room: Dictionary = game.building_interiors.ROOMS.cabin
	var door_inside: Vector3 = game.building_interiors.spawn_at("cabin")
	game.player.position = door_inside
	var at_door: bool = game.building_interiors.door_at(game.player.position) == "cabin"
	check(at_door and ev.prompt().find("Открыть") >= 0, "У двери изнутри предупреждающая подсказка: %s" % ev.prompt())
	check(ev.interact() and ev.result == "opened" and game.health < 100 and game.building_interiors.active.is_empty(), "Открыли — за дверью «никого», удар и потеря рассудка (%.0f)" % game.health)
	# --- под причалом
	game.achievements.unlocked.erase("pier_escape")
	night(6)
	var edge := Vector3.ZERO
	var inner := Vector3.ZERO
	for x in range(34, 52):
		for z in range(5, 16):
			var p := Vector3(x * .5, 1.2, z * .5)
			var g: Variant = game.night_raids.ground_at(p)
			if g == null or not lk.in_zone(p):
				continue
			if lk.water_near(g) != null and edge == Vector3.ZERO:
				edge = g + Vector3.UP * .1
	check(edge != Vector3.ZERO, "Нашлась точка у края рыбацкого причала %s" % edge)
	game.player.global_position = edge
	check(lk.at_edge(), "Смотритель у края настила")
	game.hour = 12
	game.campaign.state.night = false
	for i in 50:
		lk.tick(DT)
	check(lk.state == "idle", "Днём под причалом тихо")
	night(6)
	for i in 25:
		lk.tick(DT)
		game.player.global_position = edge
	check(lk.state == "bubbling", "Ночью у края вода забурлила (сигнал до броска)")
	# отойти вглубь
	game.player.global_position = Vector3(16.0, 1.3, 7.5)
	var gg: Variant = game.night_raids.ground_at(game.player.global_position)
	if gg != null:
		game.player.global_position = gg + Vector3.UP * .1
	lk.tick(DT)
	check(lk.state == "cooldown" and lk.escapes == 1 and game.health == 100 and game.achievements.has("pier_escape"), "Отошли вовремя — без урона, достижение «Не у края»")
	lk.reset()
	game.player.global_position = edge
	var hp: float = game.health
	t = 0.0
	while t < 10 and lk.grabs == 0:
		game.player.global_position = edge if lk.state != "drag" else game.player.global_position
		lk.tick(DT)
		t += DT
	check(lk.grabs == 1 and t >= lk.EDGE_TRIGGER + lk.TELEGRAPH - .2, "Остались у края — оно хватает, но только после предупреждения (%.1f с)" % t)
	for i in 20:
		lk.tick(DT)
	check(game.health < hp and game.sanity < 100 and game.drain_log.has("water"), "Утащило под доски: урон и рассудок с причиной")
	check(not lk.in_zone(game.player.global_position), "Выбросило на берег, подальше от края")
	print("NIGHT_EVENTS_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
