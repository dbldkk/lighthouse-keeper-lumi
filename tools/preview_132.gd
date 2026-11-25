extends SceneTree
## v1.3.2 screenshots: night readability, day, hiding scene. godot --path . --script res://tools/preview_132.gd -- /abs/out
var out := "/tmp/p132"
var game: Node

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	call_deferred("run")

func shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Captured ", name)

func quiet() -> void:
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	game.message_time = 0
	game.message_queue.clear()
	game.radio.reset()

func cam(at: Vector3, z: float) -> void:
	game.camera_focus = at + Vector3.UP; game.target_zoom = z; game.camera_zoom = z

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	game.checkpoints_enabled = false
	game.save_path = "user://preview132.json"
	game.preferences.path = "user://preview132_settings.cfg"
	game.preferences.tutorial_done = true
	game.start_shift()
	game.tutorial.stop()
	game.hunter.enabled = false
	game.night_raids.set_process(false)
	var at := Vector3(4.4, 1.2, 9.4)
	game.player.position = at
	game.hour = 12.0; game.hours_per_second = 0
	await create_timer(.8).timeout
	cam(game.player.position, 7); await create_timer(.4).timeout; quiet()
	await shot("night_readability_0_day_zoom7")
	game.day = 4; game.campaign.state.day = 4; game.campaign.state.night = true
	game.hour = 23; game.lighthouse_on = true; game.player.lantern_on = true
	await create_timer(1.2).timeout
	game.clear_enemies(); game.night_raids.set_process(false)
	for z in [7.0, 11.0]:
		cam(game.player.position, z); await create_timer(.5).timeout; game.clear_enemies(); quiet()
		await shot("night_readability_after_lantern_zoom%d" % int(z))
	game.player.lantern_on = false
	await create_timer(.4).timeout; game.clear_enemies(); quiet()
	await shot("night_readability_after_no_lantern_zoom7")
	game.player.lantern_on = true
	# hiding scene: wardrobe in the cabin, hunter inside, shadow under the door
	var h = game.hunter
	h.enabled = true
	await create_timer(.3).timeout
	game.enter_building("cabin")
	await create_timer(.5).timeout
	var w: Dictionary = {}
	for s in h.spots:
		if s.id == "wardrobe": w = s
	game.player.global_position = w.at + Vector3(.3, 0, .5)
	cam(game.player.global_position, 7)
	h._set_state("chase")
	h.body.global_position = game.building_interiors.exit_at("cabin") + Vector3(6, 0, 2)
	h.hide_in("wardrobe")
	h.space = "cabin"
	h.body.global_position = w.at + Vector3(1.2, 0, .9)
	h.hide_clock = 3.0
	h.holding_forced = true
	h.set_process(false)
	quiet()
	game.notify("Оно прямо у дверцы. Не дышите!", 3, 2)
	for i in 8:
		game.hud.overlay.card_time = 0
		game.hud.overlay.alert_time = 0
		game.radio.reset()
		h._update_hud()
		await process_frame
	await shot("hiding_wardrobe_shadow_under_door")
	h.body.global_position = w.at + Vector3(4.5, 0, -1.0)
	h.holding_forced = false
	quiet()
	game.notify("Шаги удаляются. Оно ушло искать в другом месте.", 4)
	for i in 8:
		game.hud.overlay.card_time = 0
		game.hud.overlay.alert_time = 0
		game.radio.reset()
		h._update_hud()
		await process_frame
	await shot("hiding_wardrobe_steps_fading")
	quit()
