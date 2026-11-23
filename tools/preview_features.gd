extends SceneTree
## Скриншоты новых систем: охотник, укрытие, журнал, концовка, шторм, зеркало, тайники.
## godot --path . --script res://tools/preview_features.gd -- /abs/dir
var out := "/tmp/features"
var game: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	call_deferred("run")

func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("Captured ", path)

func quiet() -> void:
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	game.message_time = 0
	game.radio.reset()

func place(at: Vector3, zoom := 22.0) -> void:
	game.player.position = at
	game.player.velocity = Vector3.ZERO
	game.camera_focus = at + Vector3.UP
	game.target_zoom = zoom
	game.camera_zoom = zoom

func setup_day(n: int) -> void:
	game.day = n
	game.campaign.state.day = n
	game.campaign.ensure_day()
	game.campaign.state.completed_days = range(1, n)
	for i in game.campaign.entry().goals.size():
		game.campaign.state.marks[str(i)] = true

func night(n: int) -> void:
	setup_day(n)
	game.barricade_built = true
	game.campaign.state.beacon_charge = 2
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.player.lantern_on = true
	game.campaign.begin_night()
	game.campaign.state.night_clock = 12
	game.hour = 23.0
	game.clear_enemies()
	game.lantern_oil = 80

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	game.checkpoints_enabled = false
	game.save_path = "user://preview_features.json"
	game.start_shift()
	game.hours_per_second = 0
	var h: Node3D = game.hunter

	# 1. охотник
	night(6)
	place(Vector3(2, 1.2, 7), 18)
	await create_timer(1.0).timeout
	h.body.global_position = Vector3(4.4, 1.0, 9.2)
	h._set_state("chase")
	h.body.look_at(Vector3(2, h.body.global_position.y, 7) * Vector3(1, 0, 1) + Vector3(0, h.body.global_position.y, 0), Vector3.UP, true)
	h.motion.play("jog", 0)
	h.motion.tick(.3)
	game.scares.fear = .8
	game.paused = true
	await create_timer(.6).timeout
	quiet()
	game.notify("Оно идёт на свет фонаря. Погасите фонарь или бегите к маяку.", 6, 1)
	await shot("1_hunter")
	game.paused = false

	# 2. укрытие: шкаф в хижине, охотник внутри
	game.enter_building("cabin")
	await create_timer(.5).timeout
	var wardrobe: Dictionary = {}
	for s in h.spots:
		if s.id == "wardrobe":
			wardrobe = s
	game.player.global_position = wardrobe.at + Vector3(.3, .05, .5)
	h.hide_in("wardrobe")
	h.space = "cabin"
	h.room_clock = 0
	h.body.global_position = wardrobe.at + Vector3(.9, 0, 1.1)
	h.body.look_at(wardrobe.at + Vector3(0, 0, 0), Vector3.UP, true)
	h.holding_forced = true
	h.breath = 3.2
	await create_timer(.4).timeout
	quiet()
	h._update_hud()
	h.preview_freeze = true
	h.prompt.text = "ОНО РЯДОМ · держите ПРОБЕЛ — не дышать"
	h.prompt.add_theme_color_override("font_color", Color("ffb1a1"))
	h.prompt.show()
	h.breath_bar.value = 3.2
	h.breath_bar.show()
	await shot("2_hiding")
	h.preview_freeze = false
	h.holding_forced = false
	h.leave_hiding()
	h.space = ""
	h._despawn()

	# 3. зеркало: отражение запаздывает и смотрит
	var ss: Node3D = game.small_scares
	game.player.global_position = ss.mirror_at() + Vector3(1.6, -1.4, 1.0)
	await create_timer(.5).timeout
	ss.stare_time = 30.0
	ss.double.global_position = ss.mirror_at() + Vector3(1.0, -1.4, -.3)
	game.target_zoom = 7.0
	await create_timer(.8).timeout
	ss.viewport.get_texture().get_image().save_png(out.path_join("6_mirror_view.png"))
	quiet()
	await shot("6_mirror")
	ss.stare_time = 0
	game.exit_building()
	await create_timer(.3).timeout

	# 4. журнал: страница дневника
	game.lore.collect("diary_2")
	game.lore.collect("tape_1")
	await create_timer(.2).timeout
	quiet()
	game.open_journal_entry("l:diary_2")
	await create_timer(.3).timeout
	await shot("3_journal")
	game.close_journal()

	# 5. шторм 5-й ночи
	game.campaign.state.night = false
	await create_timer(.2).timeout
	night(5)
	place(Vector3(-2, 1.3, -1), 26)
	game.coastal_life.weather_mode = 1
	await create_timer(1.5).timeout
	game.escalation.strike(true)
	game.escalation.flash_hold = true
	game.escalation.flash = .8
	await create_timer(.3).timeout
	quiet()
	game.notify("ШТОРМ. Ливень, молнии, генератор под ударом. Переживите ночь до рассвета.", 6, 1)
	await shot("5_storm")

	# 7. тайник и ракета
	game.escalation.flash_hold = false
	game.escalation.flash = 0
	var c: Dictionary = game.supplies.caches[0] if not game.supplies.caches.is_empty() else {}
	place(Vector3(2, 1.2, 7), 20)
	game.supplies.flares = 2
	await create_timer(.4).timeout
	game.supplies.fire_flare()
	await create_timer(.8).timeout
	print("FLARE ", game.supplies.flare_active(), " ", game.supplies.flare_node.global_position if is_instance_valid(game.supplies.flare_node) else Vector3.ZERO, " flares ", game.supplies.flares)
	quiet()
	await shot("7_flare")

	# 4. концовка
	game.lore.ending = "dark"
	game.finish_shift(true)
	await create_timer(.5).timeout
	if game.album.visible:
		game.album.hide()
	game.hud.show_menu("win")
	await create_timer(.5).timeout
	await shot("4_ending_dark")
	game.lore.card_layer.hide()
	await create_timer(.2).timeout
	await shot("4b_ending_menu")
	quit(0)
