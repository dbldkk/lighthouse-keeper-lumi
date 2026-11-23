extends SceneTree
## Укрытия не перекрывают станции: E у рыбалки — рыбалка, а не брезент.
var game: Node
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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_hiding_spots.json"
	game.start_shift()
	game.tutorial.stop()
	await frames(2)
	var h: Node3D = game.hunter
	var fish: Area3D = null
	for st in game.stations:
		if st.station_id == "fish":
			fish = st
	check(fish != null, "Станция рыбалки найдена")
	var reach: float = game.station_reach()
	var worst := 999.0
	var worst_pair := ""
	for s in h.spots:
		if not str(s.room).is_empty():
			continue
		for st in game.stations:
			var d := Vector2(s.at.x - st.position.x, s.at.z - st.position.z).length()
			if d < worst:
				worst = d
				worst_pair = "%s ↔ %s" % [s.id, st.station_id]
	check(worst >= reach + h.SPOT_REACH_OUTDOOR, "Зоны уличных укрытий не пересекаются со станциями (ближе всего %s: %.1f м ≥ %.1f)" % [worst_pair, worst, reach + h.SPOT_REACH_OUTDOOR])
	var tarp: Dictionary = {}
	for s in h.spots:
		if s.id == "tarp":
			tarp = s
	var fd := Vector2(tarp.at.x - fish.position.x, tarp.at.z - fish.position.z).length()
	check(fd >= 4.0 and fd <= 14.0, "Брезент — у лодки, но в стороне от рыбалки (%.1f м)" % fd)
	check(game.night_raids.ground_at(tarp.at) != null, "Брезент стоит на твёрдой земле")
	# E у места рыбалки — не прячет
	game.player.global_position = Vector3(fish.position.x, game.player.global_position.y, fish.position.z) + Vector3(.3, 0, .3)
	game.update_nearest()
	check(game.nearest_station == fish, "У причала ближайшая станция — рыбалка")
	check(h.spot_near(game.player.global_position).is_empty(), "У рыбалки нет укрытия в зоне досягаемости")
	check(not h.interact() and not h.hiding(), "E у рыбалки не прячет в брезент")
	# у брезента — прячет
	game.player.global_position = tarp.at + Vector3(.4, 0, .4)
	game.update_nearest()
	check(h.interact() and h.hiding() and h.hidden_in == "tarp", "E у брезента — спрятаться")
	h.leave_hiding()
	# приоритет ближайшего: укрытие и станция рядом — выигрывает ближняя станция
	var fake := Vector3(fish.position.x, tarp.at.y, fish.position.z) + Vector3(1.0, 0, 0)
	h.spots.append({"id": "probe", "title": "Проба", "at": fake, "room": ""})
	game.player.global_position = Vector3(fish.position.x, game.player.global_position.y, fish.position.z) + Vector3(.2, 0, 0)
	game.update_nearest()
	check(not h.interact() and not h.hiding(), "Если станция ближе укрытия — E достаётся станции")
	game.player.global_position = fake + Vector3(.1, 0, 0)
	game.update_nearest()
	check(h.interact() and h.hiding(), "Если укрытие ближе — прячемся")
	h.leave_hiding()
	h.spots.pop_back()
	print("HIDING_SPOTS_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
