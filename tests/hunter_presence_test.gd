extends SceneTree
## Видимость охотника ночью: отблеск глаз, фонарь его «ловит», отражение на воде.
var game: Node
var h: Node3D
var pr: Node3D
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

func tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		pr.tick(1.0 / 30.0)
		t += 1.0 / 30.0

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_presence.json"
	game.start_shift()
	h = game.hunter
	await frames(2)
	pr = h.presence
	check(pr != null and pr.glints.size() == 2 and pr.reflections.size() == 2, "Отблеск глаз и отражения созданы")
	check(pr.glints[0].get_parent() == h.visual.head_attach, "Отблеск глаз едет вместе с головой")
	check(absf(pr.glints[0].position.x - pr.glints[1].position.x) > .03, "Два глаза разнесены по ширине лица")
	game.day = 4
	game.campaign.state.day = 4
	game.campaign.state.night = true
	game.hour = 23
	h.preview_freeze = true
	h.active = true
	h.space = ""
	h.body.show()
	game.player.global_position = Vector3(2, 1.2, 4)
	game.player.lantern_on = true
	game.player.get_node("Visual").rotation.y = 0.0     # смотрит на +Z
	# вблизи и издалека
	h.body.global_position = Vector3(2, 1, 7)
	tick(.3)
	var near_size: float = pr.glint_size
	h.body.global_position = Vector3(2, 1, 19)
	tick(.3)
	check(pr.glint_size > near_size * 1.6, "Издалека глаза заметнее (%.2f > %.2f)" % [pr.glint_size, near_size])
	check(pr.glints[0].visible, "Ночью глаза светятся")
	game.camera_focus = Vector3(2, 2, 12)
	game.update_camera(1.0)
	pr.blink_clock = 99
	pr.blink = 0
	tick(.1)
	check(pr.overlay != null and pr.overlay.get_parent() == game.hud.root and pr.overlay.get_index() == game.hud.atmosphere.get_index() + 1, "Точки глаз рисуются поверх ночной темноты, но под интерфейсом")
	check(pr.overlay_visible and pr.overlay_points.size() == 2, "Издалека в темноте видны две точки глаз")
	# фонарь ловит
	h.body.global_position = Vector3(2, 1, 9)
	tick(1.0)
	check(pr.catch_level > .5 and pr.catch_light.light_energy > .8, "Фонарь смотрителя освещает его спереди (%.2f)" % pr.catch_level)
	var lit: float = pr.catch_level
	game.player.get_node("Visual").rotation.y = PI      # отвернулся
	tick(1.0)
	check(pr.catch_level < lit * .5, "Если отвернуться — свет на нём гаснет")
	game.player.lantern_on = false
	game.player.get_node("Visual").rotation.y = 0.0
	tick(1.0)
	check(pr.catch_level < .05, "Без фонаря его не видно в свете")
	game.player.lantern_on = true
	h.body.global_position = Vector3(2, 1, 4 + pr.CATCH_RANGE + 3)
	tick(1.0)
	check(pr.catch_level < .05, "Слишком далеко для фонаря")
	# моргает
	pr.blink_clock = 1.0
	var closed := false
	for i in 400:
		pr.tick(1.0 / 30.0)
		if pr.glints[0].scale.y < .001:
			closed = true
			break
	check(closed, "Иногда моргает")
	# отражение на воде: ищем берег, за которым к камере — вода
	var cam_dir := Vector3(29, 0, 40).normalized()
	var shore: Variant = null
	for x in range(-30, 31, 2):
		for z in range(-40, 31, 2):
			var g: Variant = game.night_raids.ground_at(Vector3(x, 1, z))
			if g == null:
				continue
			if game.night_raids.ground_at(Vector3(x, 1, z) + cam_dir * 1.2) == null and game.night_raids.ground_at(Vector3(x, 1, z) + cam_dir * 2.2) == null:
				shore = (g as Vector3) - Vector3(0, .35, 0)
				break
		if shore != null:
			break
	check(shore != null, "На острове есть берег, обращённый к камере")
	if shore != null:
		h.body.global_position = shore
		tick(.2)
		check(pr.reflection_visible and pr.reflections[0].visible and pr.silhouette.visible, "На воде видно отражение глаз и бледный силуэт")
		check(absf(pr.reflections[0].global_position.y - pr._ocean_y()) < .1, "Отражение лежит на поверхности воды")
	h.body.global_position = Vector3(2, 1, 9)
	tick(.2)
	check(not pr.reflection_visible, "В глубине острова отражения нет")
	h._despawn()
	check(pr.overlay_points.is_empty() and not pr.overlay_visible, "Ушёл — точки глаз пропали")
	h.active = true
	# днём — без светящихся глаз
	game.campaign.state.night = false
	game.hour = 12
	tick(.2)
	check(not pr.glints[0].visible, "Днём глаза не светятся")
	h.preview_freeze = false
	print("PRESENCE_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
