extends SceneTree
## Прогон баланса v1.3: боты проживают ночи в настоящей сцене (ИИ охотника, тьма, особые ночи, причал).
## godot --headless --path . -s res://tools/playtest_sim.gd [-- out.json]
## Боты (без теней-волн — они отключены, чтобы мерить именно охотника/тьму/события):
##  careful   — фонарь горит, держится у света хижины, при погоне прячется в ближайшее укрытие;
##  wanderer  — ходит по острову между целями с фонарём, при погоне бежит к маяку;
##  dark      — стоит снаружи без фонаря и без маяка (проверка «тьма убивает, но не мгновенно»);
##  nightmare — как careful, но на «Кошмаре».
var game: Node
var rng := RandomNumberGenerator.new()
const DT := 1.0 / 20.0
var report := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	rng.seed = 1337
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://playtest_sim.json"
	game.start_or_resume()
	game.tutorial.stop()
	for i in 3:
		await process_frame
	game.night_raids.set_process(false)
	for n in [game.hunter, game.darkness, game.night_events, game.water_lurker, game.scares, game.small_scares]:
		n.set_process(false)
	for bot in ["careful", "wanderer", "dark", "nightmare"]:
		report[bot] = []
		for day in [4, 6, 9, 11, 12]:
			report[bot].append(night(bot, day))
	# сейнер: реакция игрока 0.5..4.5 с после вспышки камня
	var ship := []
	for reaction in [.5, 1.5, 2.5, 3.5, 4.5, 5.5]:
		ship.append({"reaction": reaction, "result": ship_run(reaction)})
	report["ship"] = ship
	report["pier"] = pier_run()
	var out := "/tmp/playtest_v13.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	summary()
	quit()

func setup_night(day: int, nightmare: bool) -> void:
	game.difficulty = "nightmare" if nightmare else "normal"
	game.day = day
	var c = game.campaign
	c.ensure_day()
	c.state.night = false
	c._start_night()
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.barricade_built = true
	game.health = 100
	game.sanity = 100
	game.hunger = 90
	game.lantern_oil = 100
	game.survival.warmth = 80
	game.drain_log.clear()
	game.hunter.reset()
	game.darkness.reset()
	game.night_events.reset()
	game.water_lurker.reset()
	game.clear_enemies()
	game.set_building_interior("")
	game.player.global_position = Vector3(3, 1.2, 4)

func ground(p: Vector3) -> Variant:
	return game.night_raids.ground_at(p)

func walk_to(target: Vector3, speed: float) -> void:
	var p: Vector3 = game.player.global_position
	var to := Vector3(target.x - p.x, 0, target.z - p.z)
	if to.length() < .2:
		return
	var step := to.normalized() * minf(to.length(), speed * DT)
	var g: Variant = ground(p + step)
	if g != null:
		game.player.global_position = g + Vector3.UP * .1

func night(bot: String, day: int) -> Dictionary:
	setup_night(day, bot == "nightmare")
	var h = game.hunter
	var c = game.campaign
	var t := 0.0
	var caught := 0
	var hides := 0
	var died := false
	var min_hp := 100.0
	var goal := Vector3(3, 1.2, 4)
	var catches0: int = h.catches
	var event: String = game.night_events.event_for(day, str(c.entry().night.kind))
	while c.state.night and t < 260:
		var p: Vector3 = game.player.global_position
		var hd: float = Vector2(h.body.global_position.x - p.x, h.body.global_position.z - p.z).length()
		match bot:
			"careful", "nightmare":
				game.player.lantern_on = true
				if h.active and h.state in ["chase", "investigate"] and hd < 14 and not h.hiding():
					# бежит к ближайшему укрытию снаружи и прячется
					var best: Dictionary = {}
					var bd := 1e9
					for sp in h.spots:
						if str(sp.room).is_empty():
							var dd := Vector2(sp.at.x - p.x, sp.at.z - p.z).length()
							if dd < bd:
								bd = dd
								best = sp
					if not best.is_empty() and bd < 1.4:
						h.hide_in(str(best.id))
						hides += 1
					elif not best.is_empty():
						walk_to(best.at, 6.3)
				elif h.hiding() and (h.state not in ["chase", "search"] or hd > 16):
					h.leave_hiding()
				elif not h.hiding():
					walk_to(Vector3(4, 1.2, 4.5), 3.0)
			"wanderer":
				game.player.lantern_on = true
				if h.active and h.state == "chase" and hd < 12:
					walk_to(Vector3(-6, 1.2, -3), 5.5)
				else:
					if Vector2(p.x - goal.x, p.z - goal.z).length() < 1.0 or rng.randf() < DT / 25.0:
						for k in 10:
							var q := Vector3(rng.randf_range(-12, 16), 1.2, rng.randf_range(-12, 10))
							var g: Variant = ground(q)
							if g != null:
								goal = g
								break
					walk_to(goal, 3.0)
			"dark":
				game.lighthouse_on = false
				game.beacon.set_powered(false)
				game.player.lantern_on = false
				game.player.global_position = Vector3(12, 1.2, 8)
		# ночные события: бот реагирует на шторм (идёт к генератору) и сейнер (сигналит через 2 с)
		if c.state.blackout and bot != "dark":
			c.restore_beacon()
		var ev = game.night_events
		if ev.event == "ship" and ev.danger >= 0 and ev.danger_time > 2.0 and bot != "dark":
			var keep: Vector3 = game.player.global_position
			game.player.global_position = ev.SIGNAL_LAMP
			ev.signal_ship()
			game.player.global_position = keep
		game._process(DT)
		h._process(DT)
		game.darkness.tick(DT)
		ev.tick(DT)
		game.water_lurker.tick(DT)
		game.clear_enemies()
		game.hunger = maxf(game.hunger, 60)
		min_hp = minf(min_hp, game.health)
		if game.health <= 0:
			died = true
			break
		t += DT
	if h.hiding():
		h.leave_hiding()
	return {"day": day, "event": event, "seconds": snappedf(t, .1), "dawn": not c.state.night, "died": died,
		"catches": h.catches - catches0, "hides": hides, "min_hp": snappedf(min_hp, .1), "sanity": snappedf(game.sanity, .1),
		"drain": game.drain_log.duplicate(), "oil": snappedf(game.lantern_oil, .1), "ev_result": game.night_events.result}

func ship_run(reaction: float) -> String:
	setup_night(6, false)
	game.hunter.active = false
	var ev = game.night_events
	ev.force("ship")
	var t := 0.0
	while t < 150 and ev.result.is_empty():
		if ev.danger >= 0 and ev.danger_time >= reaction:
			game.player.global_position = ev.SIGNAL_LAMP
			ev.signal_ship()
		ev.tick(DT)
		t += DT
	return ev.result

func pier_run() -> Dictionary:
	setup_night(6, false)
	var lk = game.water_lurker
	var edge := Vector3(18.5, 1.45, 7.0)
	var res := {}
	for react in [.5, 1.5, 2.5, 3.0]:
		lk.reset()
		game.health = 100
		var t := 0.0
		var bubbling_at := -1.0
		var outcome := "none"
		while t < 15:
			if lk.state == "bubbling" and bubbling_at < 0:
				bubbling_at = t
			if bubbling_at >= 0 and t - bubbling_at >= react and lk.state == "bubbling":
				game.player.global_position = Vector3(16, 1.3, 7.5)
			elif lk.state != "drag" and bubbling_at < 0:
				game.player.global_position = edge
			lk.tick(DT)
			if lk.grabs > 0:
				outcome = "grabbed"
				break
			if lk.escapes > 0:
				outcome = "escaped"
				break
			t += DT
		res[str(react)] = outcome
		lk.grabs = 0
		lk.escapes = 0
	return res

func summary() -> void:
	for bot in ["careful", "wanderer", "dark", "nightmare"]:
		var deaths := 0
		var catches := 0
		var dawns := 0
		var min_hp := 100.0
		for r in report[bot]:
			deaths += int(r.died)
			catches += int(r.catches)
			dawns += int(r.dawn)
			min_hp = minf(min_hp, float(r.min_hp))
		print("BOT %-9s nights=%d dawn=%d deaths=%d catches=%d (%.2f/night) min_hp=%.0f" % [bot, report[bot].size(), dawns, deaths, catches, float(catches) / report[bot].size(), min_hp])
		for r in report[bot]:
			print("   day %2d %-8s %5.0fs dawn=%s died=%s catches=%d hides=%d min_hp=%.0f sanity=%.0f ev=%s drain=%s" % [r.day, r.event, r.seconds, r.dawn, r.died, r.catches, r.hides, r.min_hp, r.sanity, r.ev_result, r.drain])
	print("SHIP ", report.ship)
	print("PIER ", report.pier)
