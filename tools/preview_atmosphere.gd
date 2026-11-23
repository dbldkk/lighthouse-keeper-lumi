extends SceneTree
## Скриншоты атмосферы «до/после»: меню, день, сумерки, ночь с фонарём, ночь в тумане, хижина.
## godot --path . --script res://tools/preview_atmosphere.gd -- /abs/dir prefix
var out := "/tmp/atmo"
var prefix := "shot"
var game: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: prefix = args[1]
	call_deferred("run")

func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(prefix + "_" + name + ".png")
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

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.5).timeout
	await shot("0_menu")
	game.checkpoints_enabled = false
	game.save_path = "user://preview_atmosphere.json"
	game.start_shift()
	game.hours_per_second = 0
	setup_day(4)
	game.hour = 11.0
	place(Vector3(3, 1.1, 6.5))
	await create_timer(1.5).timeout
	quiet()
	await shot("1_day")
	game.hour = 18.6
	place(Vector3(-4, 1.2, -1), 24)
	await create_timer(1.0).timeout
	quiet()
	await shot("2_dusk")
	# ночь
	game.campaign.state.beacon_charge = 2
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.campaign.begin_night()
	game.campaign.state.night_clock = 12
	game.hour = 23.0
	game.night_raids.advance(1)
	game.clear_enemies()
	game.player.lantern_on = true
	game.lantern_oil = 80
	game.sanity = 70
	place(Vector3(-3, 1.4, 3))
	await create_timer(2.0).timeout
	quiet()
	await shot("3_night_lantern")
	game.sanity = 30
	if game.scares.has_method("force_presence"):
		game.scares.force_presence()
	await create_timer(1.0).timeout
	quiet()
	await shot("4_night_low_sanity")
	game.sanity = 70
	place(Vector3(12, 1.2, -6), 26)
	game.island_events.current = "fog"
	game.island_events.time_left = 30.0
	await create_timer(1.5).timeout
	quiet()
	await shot("5_night_fog")
	game.island_events.current = ""
	quit(0)
