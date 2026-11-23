extends SceneTree
## Регрессия (день 4, v1.2): без топлива часы вставали на 19:30 и ночь не наступала.
## Время идёт всегда; ночь приходит по расписанию; темнота без света опасна.
var game: Node
var c
var checks := 0
var failures := 0
const DT := .25

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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_time_flow.json"
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	c = game.campaign
	game.night_raids.set_process(false)
	check(c.DAY_SECONDS >= 74.0, "День стал длиннее в 1.5 раза (%.0f с вместо 50)" % c.DAY_SECONDS)
	# день 4: топлива нет, маяк не горит, задачи не сделаны, висит подсказка
	game.day = 4
	c.ensure_day()
	game.inventory.fuel = 0
	c.state.beacon_charge = 0
	game.lighthouse_on = false
	game.notify("Генератору нужно топливо. Проверьте ящики на тропе.", 30)
	game.fuel_glint_time = 30
	check(not c.day_complete(), "Задачи дня не выполнены")
	var last: float = game.hour
	var stuck := 0.0
	var worst := 0.0
	var t := 0.0
	while t < c.DAY_SECONDS + c.DUSK_GRACE + 2 and not c.state.night:
		c.advance(DT)
		t += DT
		stuck = stuck + DT if game.hour <= last else 0.0
		worst = maxf(worst, stuck)
		last = game.hour
	check(worst < 1.0, "Часы не стоят ни секунды (макс. пауза %.2f с)" % worst)
	check(c.state.night and t <= c.DAY_SECONDS + c.DUSK_GRACE + .5, "Ночь наступила по расписанию без маяка и задач (%.0f с)" % t)
	check(c.state.get("unfinished", false), "Ночь отмечена как «день не закончен»")
	# ночь без света: часы идут, рассвет приходит
	game.player.global_position = Vector3(3, 1.2, 4)
	game.set_building_interior("")
	var night_start: float = game.hour
	var dur: float = float(c.entry().night.seconds)
	t = 0.0
	var hour_mid := 0.0
	while c.state.night and t < dur + c.NIGHT_OVERTIME + 5:
		c.advance(DT)
		t += DT
		if absf(t - (dur + 10)) < DT:
			hour_mid = game.hour
		game.health = 100
	check(hour_mid > 23.5, "После полуночи часы идут дальше (%.2f)" % hour_mid)
	check(not c.state.night and game.hour < 8, "Рассвет пришёл сам (%.0f с)" % t)
	check(game.day == 4, "Задачи не закончены — тот же день продолжается")
	check(c.state.day_clock < 1.0 and not c.state.night, "Новое утро: часы снова с 07:00")
	# быстрый вариант: задачи сделаны, но маяк не горит — день сменяется
	c.state.night = false
	c.state.day_clock = 0
	for i in c.entry().goals.size():
		c.state.marks[str(i)] = true
	check(c.day_complete(), "Задачи дня выполнены")
	t = 0.0
	while not c.state.night and t < 200:
		c.advance(DT)
		t += DT
	check(c.state.night and not c.state.get("unfinished", true), "Ночь по расписанию, день засчитан")
	while c.state.night and t < 600:
		c.advance(DT)
		t += DT
		game.health = 100
	check(game.day == 5, "Утром — следующий день (день %d)" % game.day)
	# последствия темноты
	game.day = 5
	c.ensure_day()
	c.state.night = true
	game.lighthouse_on = false
	game.set_building_interior("")
	game.player.global_position = Vector3(3, 1.2, 4)
	game.player.lantern_on = false
	game.health = 100
	game.sanity = 100
	var d = game.darkness
	d.reset()
	check(d.in_full_darkness(), "Снаружи, без маяка и фонаря — полная темнота")
	var alerts := 0
	t = 0.0
	var warned_at := -1.0
	while t < d.DARK_LIMIT + 1:
		d.tick(DT)
		t += DT
		if d.warned >= 1 and warned_at < 0:
			warned_at = t
	check(warned_at > 0 and warned_at < d.DARK_LIMIT * .5, "Сначала предупреждение (%.0f с)" % warned_at)
	check(d.warned >= 2, "Второе предупреждение до урона")
	check(game.sanity < 95, "Рассудок тает быстрее без маяка (%.0f)" % game.sanity)
	check(d.hunter_bonus() > 0, "Охотник смелее, пока маяк не горит")
	var hp: float = game.health
	for i in 40:
		d.tick(DT)
	check(game.health < hp - 10 and game.health > hp - 25, "Предел темноты — здоровье уходит медленно (%.0f → %.0f за 10 с)" % [hp, game.health])
	check(game.drain_log.get("dark", 0.0) > 0, "Потеря записана с причиной «темнота»")
	for i in 320:
		d.tick(DT)
	check(game.health <= 0, "Если так и не найти свет — смерть")
	game.health = 60
	game.player.lantern_on = true
	for i in 8:
		d.tick(DT)
	var hp2: float = game.health
	for i in 40:
		d.tick(DT)
	check(game.health == hp2 and d.level < 1.0, "Свет фонаря останавливает урон, шкала спадает (%.0f→%.0f, lantern %s, level %.2f, dark %s)" % [hp2, game.health, game.player.lantern_on, d.level, d.in_full_darkness()])
	game.player.lantern_on = false
	game.enter_building("cabin")
	await frames(1)
	check(not d.in_full_darkness(), "В хижине темнота не убивает")
	game.exit_building()
	await frames(1)
	game.lighthouse_on = true
	d.tick(DT)
	check(not d.unlit_night and d.hunter_bonus() == 0.0, "Маяк горит — обычная ночь")
	print("TIME_FLOW_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
