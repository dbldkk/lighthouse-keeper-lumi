extends SceneTree
## Нарастание ночей: агрессия охотника, ночной туман, шторм 5-й ночи, «мёртвый час», финальный шторм.
var game: Node
var esc: Node
var checks := 0
var failures := 0

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

func start_night(day: int) -> void:
	game.campaign.state.night = false
	await frames(1)
	game.day = day
	game.campaign.state.day = day
	game.campaign.ensure_day()
	for i in game.campaign.entry().goals.size():
		game.campaign.state.marks[str(i)] = true
	game.campaign.state.night = true
	game.campaign.state.night_clock = 0.0
	game.campaign.state.blackout = false
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	await frames(2)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_escalation.json"
	game.start_shift()
	esc = game.escalation
	await frames(2)
	var agg := []
	for d in [2, 5, 9, 13]:
		game.day = d
		agg.append(esc.hunter_aggression())
	check(agg[0] < agg[1] and agg[1] < agg[2] and agg[2] < agg[3], "Hunter aggression rises every night %s" % str(agg))
	check(is_equal_approx(agg[0], 1.0) and agg[3] >= 1.75, "From 1.0 on night 2 to ~1.8 at the end")

	await start_night(3)
	check(not esc.storm and not esc.fog, "Early nights: no storm, no fog")
	check(game.hunter.active and is_equal_approx(game.hunter.aggression, esc.hunter_aggression()), "Hunter picks up the night's aggression")

	# туман: шанс растёт, в 12-ю ночь — почти всегда
	var fogs := 0
	for i in 40:
		esc.rng.seed = i
		game.day = 12
		esc.begin_night()
		fogs += 1 if esc.fog else 0
	var early := 0
	for i in 40:
		esc.rng.seed = i
		game.day = 4
		esc.begin_night()
		early += 1 if esc.fog else 0
	check(fogs > early, "Night fog gets more likely (%d vs %d of 40)" % [fogs, early])
	esc.fog = true
	game.player.lantern_on = true
	var foggy: float = game.dread.target_sight()
	esc.fog = false
	var clear: float = game.dread.target_sight()
	check(foggy < clear, "Night fog cuts visibility")
	esc.end_night()

	# шторм 5-й ночи
	await start_night(5)
	check(esc.storm and game.coastal_life.weather_mode == 1, "Night 5 is a storm with rain")
	check(float(game.campaign.entry().night.seconds) >= esc.STORM_SECONDS, "The storm night is longer — survive till dawn")
	check(esc.hunter_aggression() > 1.0 + .8 * esc.level(), "Storm makes the hunter bolder")
	esc.lightning_clock = 0
	esc._tick_night(.1)
	check(esc.flash > .5, "Lightning flashes")
	game.campaign.state.night_clock = esc.BOLT_AT + .1
	esc._tick_night(.1)
	check(not game.lighthouse_on and game.campaign.state.blackout and not game.campaign.state.event_done, "Lightning knocks out the generator mid-storm")
	check(game.campaign.intercept("beacon") == 1 and game.lighthouse_on, "Power can be restored at the generator")
	game.campaign.state.night_clock = 200.0
	game.campaign.state.event_done = true
	game.barricade_built = true
	game.player.lantern_on = true
	game.hunger = 80
	check(game.campaign.prep_missing().is_empty(), "Shelter ready for dawn: " + game.campaign.prep_missing())
	game.campaign.advance(.1)
	await frames(2)
	check(game.day == 6 and not game.campaign.state.night, "Surviving the storm brings dawn")
	check(game.coastal_life.weather_mode == 0 and not esc.storm, "The storm ends at dawn")

	# мёртвый час
	await start_night(8)
	game.campaign.state.night_clock = float(game.campaign.entry().night.seconds) * .55
	esc._tick_night(.1)
	check(esc.done.has("dead_hour") and game.dread.blackout_time > 0, "From night 7 every light dies for a moment mid-night")
	esc.end_night()

	# финал
	await start_night(game.campaign.final_night())
	check(esc.storm, "The final night is a storm too")
	print("ESCALATION_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
