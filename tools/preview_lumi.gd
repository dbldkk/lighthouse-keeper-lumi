extends SceneTree
## Скриншоты доработок Lumi: новый HUD, фигура в луче, фантомный выпад, стук в окно, погасший фонарь.
## Запуск: godot --path . --script res://tools/preview_lumi.gd   (LUMI_SHOTS=/abs/dir — куда сохранить)
## Изолированная сцена: сохранения игрока не трогает.
var out := "res://docs/lumi/"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("Captured ", path)

func setup_day(game: Node, number: int) -> void:
	game.day = number
	game.campaign.state.day = number
	game.campaign.ensure_day()
	game.campaign.state.completed_days = range(1, number)
	game.inventory.fuel = 2
	game.inventory.wood = 3

func night(game: Node, number: int) -> void:
	setup_day(game, number)
	game.campaign.state.beacon_charge = 2
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.campaign.begin_night()
	game.campaign.state.night_clock = 12
	game.hour = 22.5
	game.night_raids.advance(1)
	game.clear_enemies()

func quiet_ui(game: Node) -> void:
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	game.radio.reset()

func run() -> void:
	var env_out := OS.get_environment("LUMI_SHOTS")
	if not env_out.is_empty():
		out = env_out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://preview_lumi.json"
	game.start_shift()
	game.hours_per_second = 0
	var sc: Node = game.scares

	# 1. Новый HUD: полосы со значениями, масло, тепло, предупреждения.
	setup_day(game, 5)
	game.hour = 18.4
	game.health = 38
	game.hunger = 46
	game.sanity = 52
	game.lantern_oil = 22
	game.player.position = Vector3(3, 1.1, 5.5)
	game.camera_focus = game.player.position + Vector3.UP
	await create_timer(1.5).timeout
	quiet_ui(game)
	game.notify("Масло на исходе: долейте фонарь в хижине.", 1.2, 1)
	await create_timer(.4).timeout
	await shot("01-hud.png")

	# 2. Ночь: фигура в луче фонаря, виньетка и искажение.
	night(game, 6)
	game.health = 80
	game.sanity = 34
	game.lantern_oil = 70
	game.player.lantern_on = true
	game.player.position = Vector3(-3, 1.4, 3)
	game.camera_focus = game.player.position + Vector3.UP
	game.target_zoom = 22
	game.camera_zoom = 22
	game.lantern_beam.forced = true
	game.lantern_beam.aim_override = Vector3(.75, 0, .66).normalized()
	sc.tension = .85
	await create_timer(1.2).timeout
	quiet_ui(game)
	sc.fire("figure")
	if is_instance_valid(sc.figure):
		sc.figure_time = 3.0
		print("Figure at ", sc.figure.global_position, " player ", game.player.global_position)
		game.camera_focus = (sc.figure.global_position + game.player.global_position) * .5 + Vector3.UP
		game.camera_zoom = 16
		game.target_zoom = 16
		game.update_camera(0.0)
	await create_timer(.15).timeout
	if is_instance_valid(sc.figure):
		print("Figure on screen ", game.camera.unproject_position(sc.figure.global_position + Vector3.UP), " visible ", sc.figure.is_visible_in_tree(), " zoom ", game.camera.size)
	else:
		print("Figure gone")
	await shot("02-scare-figure.png")
	game.lantern_beam.forced = false

	# 3. Низкий рассудок: силуэт бросается на смотрителя.
	await create_timer(1.0).timeout
	game.sanity = 18
	sc.tension = 1.0
	sc.fire("lunge")
	await create_timer(.45).timeout
	await shot("03-scare-lunge.png")

	# 4. Погасший фонарь.
	await create_timer(1.2).timeout
	game.lantern_oil = .05
	await create_timer(.4).timeout
	await shot("04-lantern-died.png")

	# 5. Хижина: стук и лицо в окне.
	game.lantern_oil = 60
	game.enter_building("cabin")
	await create_timer(1.0).timeout
	quiet_ui(game)
	sc.tension = .7
	sc.fire("window")
	await create_timer(.3).timeout
	await shot("05-scare-window.png")
	quit()
