extends SceneTree
## Регрессия (баг #5, v1.2): ночью здоровье «само» утекало — сломленный рассудок и холод
## отнимали его молча. Теперь: при свете, в безопасности и без нападений здоровье ночью не падает,
## а любая медленная потеря видна (плашка с причиной) и сразу прекращается на свету.
var game: Node
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

func step(seconds: float, lantern := true) -> void:
	var t := 0.0
	while t < seconds:
		game.clear_enemies()
		game.hunter.active = false
		game.player.lantern_on = lantern
		game.hunger = 90
		game.lantern_oil = 100.0
		game._process(DT)
		game.darkness.tick(DT)
		t += DT

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_night_health.json"
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	game.night_raids.set_process(false)
	game.scares.set_process(false)
	game.small_scares.set_process(false)
	game.hunter.set_process(false)
	game.darkness.set_process(false)
	var c = game.campaign
	game.day = 6
	c.ensure_day()
	c.state.night = true
	c.state.night_clock = 5
	game.hour = 22
	game.hours_per_second = 0
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.barricade_built = true
	game.survival.warmth = 70
	game.survival.meal_warmth_time = 999
	game.health = 100
	game.sanity = 100
	game.drain_log.clear()
	# 1. у маяка, с фонарём, без нападений — 3 минуты ночи
	game.player.global_position = Vector3(-6, 1.2, -2)
	check(game.is_safe(game.player.global_position), "Смотритель в круге света маяка")
	step(180.0)
	check(game.health >= 99.9, "Ночь при свете: здоровье не утекает (%.1f)" % game.health)
	check(game.drain_log.is_empty(), "Ни одной причины урона: %s" % [game.drain_log])
	check(not game.hud.drain_panel.visible, "Плашки потерь нет")
	# 2. рассудок на нуле, но фонарь горит — урона нет
	game.sanity = 0
	game.player.global_position = Vector3(12, 1.2, 8)
	game.lighthouse_on = true
	step(30.0)
	check(game.health >= 99.9, "Сломленный рассудок при горящем фонаре не ранит (%.1f)" % game.health)
	# 3. полная тьма: сначала предупреждение, потом медленный урон с названной причиной
	game.lighthouse_on = false
	game.beacon.set_powered(false)
	game.sanity = 60
	game.darkness.reset()
	var warned_before_damage := false
	var t := 0.0
	while t < 120.0 and game.health >= 99.9:
		step(DT, false)
		t += DT
		if game.hud.drain_panel.visible and game.health >= 99.9:
			warned_before_damage = true
	check(warned_before_damage, "Перед уроном видно предупреждение «%s»" % game.hud.drain_title.text)
	check(t >= 30.0, "Урон начинается не сразу (%.0f с тьмы)" % t)
	step(10.0, false)
	check(game.hud.drain_panel.visible and "ТЕМНОТА" in game.hud.drain_title.text, "Во время урона плашка называет причину: %s" % game.hud.drain_title.text)
	var lost: float = 100.0 - game.health
	check(lost > 2.0 and lost < 25.0, "Тьма отнимает медленно (%.1f за 10 с)" % lost)
	# 4. свет фонаря — потеря прекращается сразу
	var hp: float = game.health
	step(.2, true)
	var hp2: float = game.health
	step(20.0, true)
	check(game.health >= hp2 - .01 and hp2 >= hp - .5, "Фонарь включён — потеря остановилась сразу (%.1f → %.1f)" % [hp, game.health])
	step(1.0, true)
	check(not game.hud.drain_panel.visible, "Плашка исчезла, когда опасность ушла")
	# 5. холод: отсрочка, затем медленный урон с причиной
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.player.global_position = Vector3(-6, 1.2, -2)
	game.survival.meal_warmth_time = 0
	game.survival.warmth = 5
	game.health = 100
	game.drain_log.clear()
	var cold_t := 0.0
	while cold_t < 60 and game.health >= 99.9:
		game.survival.warmth = 5
		step(DT)
		cold_t += DT
	check(cold_t >= 11.0 and game.drain_log.has("cold"), "Холод ранит после отсрочки и с причиной (%.0f с)" % cold_t)
	print("NIGHT_HEALTH_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
