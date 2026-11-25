extends SceneTree
## v1.3.2: укрытие — честный способ спастись от охотника.
## Сломали прямую видимость и спрятались → он обыскивает, бьёт по дверце и уходит, не убив.
## Видел, как вы прятались / дышите рядом / третий раз в том же месте → находит.
var game: Node
var h: Node3D
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

func spot(id: String) -> Dictionary:
	for s in h.spots:
		if s.id == id:
			return s
	return {}

## Игрок «как человек»: задерживает дыхание, только когда тень под дверцей совсем близко.
func simulate(seconds: float, smart := true) -> Dictionary:
	var r := {"max_shadow": 0.0, "entered": false, "gave_up": false, "banged": false, "found": false, "t": 0.0}
	var t := 0.0
	while t < seconds:
		var sh: Vector2 = h.door_shadow()
		r.max_shadow = maxf(r.max_shadow, sh.x)
		h.holding_forced = smart and h.hiding() and sh.x > .55 and h.breath > .05
		h._process(.05)
		t += .05
		if h.space != "":
			r.entered = true
		if h.banged or h.inspections > 0:
			r.banged = true
		if h.give_up_time > 0:
			r.gave_up = true
		if not h.hiding():
			r.found = true
			break
		if r.gave_up and t > 2.0 and h.give_up_time < h.GIVE_UP_SECONDS - 3.0:
			break
	h.holding_forced = false
	r.t = t
	return r

func night() -> void:
	game.day = 6
	game.campaign.state.day = 6
	game.campaign.state.night = true
	game.hour = 22
	game.hours_per_second = 0

func fresh() -> void:
	if h.hiding():
		h.leave_hiding()
	if game.building_interiors.active != "":
		game.exit_building()
		await frames(1)
	h.space = ""
	h.mercy_time = 0
	h.give_up_time = 0
	h.spot_uses.clear()
	game.health = 100.0
	game.sanity = 100.0
	game.lighthouse_on = false
	game.barricade_built = false

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_hiding.json"
	game.start_shift()
	game.tutorial.stop()
	game.night_raids.set_process(false)
	h = game.hunter
	h.rng.seed = 1302
	night()
	await frames(3)
	check(h.active, "Hunter is out at night")
	check(h.BREATH_MAX >= h.INSPECT_SECONDS + 2.0, "Breath (%.1f s) outlasts a close inspection (%.1f s)" % [h.BREATH_MAX, h.INSPECT_SECONDS])

	# 1) погоня → вбежал в хижину → шкаф. Он за дверью и не видел, как вы прятались.
	await fresh()
	game.enter_building("cabin")
	await frames(2)
	var w := spot("wardrobe")
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	var door: Vector3 = game.building_interiors.exit_at("cabin")
	h.body.global_position = door + Vector3(7, 0, 3)
	h._set_state("chase")
	check(h.interact() and h.hiding() and not h.hide_known, "Hid in the wardrobe while it was outside: it doesn't know which spot")
	var r := simulate(60.0)
	check(r.entered, "It follows into the cabin")
	check(r.banged, "It inspects and bangs on the wardrobe")
	check(r.max_shadow > .6, "Its shadow passes under the wardrobe door (tension telegraph)")
	check(r.gave_up and not r.found, "It gives up and leaves without finding you (%.1f s)" % r.t)
	check(game.health >= 100.0 and h.hiding(), "No damage taken while hiding properly")
	check(h.space == "", "It left the cabin")
	check(h.breath > 0, "Breath never ran out")

	# 2) охотник уже в комнате и видит, как вы лезете в шкаф → вытаскивает даже без дыхания
	await fresh()
	game.enter_building("cabin")
	await frames(2)
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	h.space = "cabin"
	h.body.global_position = w.at + Vector3(1.6, 0, 1.2)
	h._set_state("chase")
	h.hide_in("wardrobe")
	check(h.hide_known and h.hide_reason == "seen", "Seen entering: it knows the spot")
	r = simulate(10.0)
	check(r.found and game.health < 100.0, "Seen entering → it drags you out even while holding breath")

	# 3) снаружи: брезент, фонарь погашен, он отстал (>4.5 м) → обыскивает и уходит
	await fresh()
	var tarp := spot("tarp")
	game.player.global_position = tarp.at + Vector3(.4, .35, .4)
	game.player.lantern_on = false
	h.body.global_position = tarp.at + Vector3(11, .35, 0)
	h._set_state("chase")
	h.hide_in("tarp")
	check(not h.hide_known, "Broke line of sight before hiding under the tarp")
	r = simulate(60.0)
	check(r.gave_up and not r.found and game.health >= 100.0, "Outdoors: it searches, gives up and leaves (%.1f s)" % r.t)

	# 4) снаружи, но он в трёх метрах с фонарём в руках у вас → видел
	await fresh()
	game.player.global_position = tarp.at + Vector3(.4, .35, .4)
	game.player.lantern_on = true
	h.body.global_position = tarp.at + Vector3(3, .35, 0)
	h._set_state("chase")
	h.hide_in("tarp")
	check(h.hide_known, "Hiding right in front of it is seen")
	r = simulate(10.0)
	check(r.found, "…and it pulls you out")

	# 5) не задерживаете дыхание, когда он вплотную → слышит
	await fresh()
	game.enter_building("cabin")
	await frames(2)
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	h.body.global_position = door + Vector3(6, 0, 2)
	h._set_state("chase")
	h.hide_in("wardrobe")
	r = simulate(60.0, false)
	check(r.found and not r.gave_up, "Breathing right next to it gives you away")

	# 6) третий раз за ночь в том же шкафу во время погони → знает
	await fresh()
	game.enter_building("cabin")
	await frames(2)
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	h.body.global_position = door + Vector3(6, 0, 2)
	h._set_state("chase")
	for i in 2:
		h.hide_in("wardrobe")
		h.leave_hiding()
	h.hide_in("wardrobe")
	check(h.hide_known and h.hide_reason == "repeat", "Third time in the same spot in one night: it remembers")

	# 7) короткий вдох вплотную прощается
	await fresh()
	game.enter_building("cabin")
	await frames(2)
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	h.space = ""
	h.body.global_position = door + Vector3(6, 0, 2)
	h._set_state("chase")
	h.hide_in("wardrobe")
	h.space = "cabin"
	h.body.global_position = w.at + Vector3(.6, 0, .6)
	h.hide_clock = 0
	h.holding_forced = false
	for i in 6:
		h._hide_search(.05)
	check(h.hiding(), "A short breath right next to it is forgiven (%.2f s < %.2f s)" % [.3, h.NOISE_LIMIT])
	h.holding_forced = false
	await fresh()
	print("HIDING_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
