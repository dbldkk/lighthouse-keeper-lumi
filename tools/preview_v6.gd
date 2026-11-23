extends SceneTree
## Скриншоты v1.2: меню и обучение, настройки, охотник крупным планом.
## godot --path . --script res://tools/preview_v6.gd -- /abs/dir [only]
var out := "/tmp/v6"
var only := ""
var game: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: only = args[1]
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
	game.message_queue.clear()
	game.radio.reset()

func place(at: Vector3, zoom := 22.0) -> void:
	game.player.position = at
	game.player.velocity = Vector3.ZERO
	game.camera_focus = at + Vector3.UP
	game.target_zoom = zoom
	game.camera_zoom = zoom

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	game.checkpoints_enabled = false
	game.save_path = "user://preview_v6.json"
	game.preferences.path = "user://preview_v6_settings.cfg"
	if only in ["", "tutorial"]:
		await tutorial_shots()
	if only in ["", "settings"]:
		await settings_shots()
	if only in ["", "hunter"]:
		await hunter_shots()
	quit()

func tutorial_shots() -> void:
	game.hud.show_menu("title")
	await shot("1_title_menu")
	game.tutorial.enabled = true
	game.replay_tutorial()
	game.hours_per_second = 0
	await create_timer(.5).timeout
	quiet()
	place(Vector3(3, 1.2, 4), 20)
	await create_timer(1.0).timeout
	await shot("2_tutorial_move")
	game.tutorial.moved = 9
	game.tutorial.ran = 1
	game.toggle_lantern()
	game.toggle_lantern()
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	game.save_points.writes += 1
	game.tutorial.journal_seen = true
	game.enter_building("cabin")
	await create_timer(.6).timeout
	quiet()
	await create_timer(.6).timeout
	await shot("3_tutorial_hide")
	game.hunter.hide_in("wardrobe")
	game.hunter.holding_forced = true
	await create_timer(.6).timeout
	quiet()
	await shot("4_tutorial_breath")
	await create_timer(1.6).timeout
	game.hunter.holding_forced = false
	game.hunter.leave_hiding()
	await create_timer(.3).timeout
	game.exit_building()
	game.hour = 18.5
	await create_timer(1.0).timeout
	quiet()
	place(game.player.position, 18)
	await create_timer(.8).timeout
	await shot("5_tutorial_flare")
	game.tutorial.stop()

func settings_shots() -> void:
	game.return_to_title()
	await create_timer(.5).timeout
	var panel = game.hud.settings_panel
	panel.open()
	panel.tabs.current_tab = 0
	await shot("6_settings_video")
	panel.tabs.current_tab = 1
	await shot("7_settings_audio")
	panel.tabs.current_tab = 2
	panel._start_capture("flare")
	await shot("8_settings_controls")
	panel.capture_key(KEY_ESCAPE)
	panel.close()

func hunter_shots() -> void:
	pass
