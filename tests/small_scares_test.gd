extends SceneTree
## Мелкие страхи: запаздывающее отражение, свой голос по радио, вещи сдвинуты к утру.
var game: Node
var ss: Node3D
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
	game.save_path = "user://automated_small.json"
	game.start_shift()
	ss = game.small_scares
	await frames(2)
	check(is_instance_valid(ss.mirror_root) and is_instance_valid(ss.double), "Mirror and reflection exist")
	check(game.camera.cull_mask & ss.MIRROR_LAYER == 0, "Main camera never sees the reflection double")
	check(ss.mirror_cam.cull_mask & ss.PLAYER_LAYER == 0 and ss.mirror_cam.cull_mask & ss.MIRROR_LAYER != 0, "Mirror camera sees the double, not the keeper")
	check(ss.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Mirror does not render outside the cabin")
	game.enter_building("cabin")
	game.player.global_position = ss.mirror_at() + Vector3(1.4, -1.4, .3)
	await frames(3)
	check(ss.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and ss.double.visible, "Inside the cabin the mirror is live")
	check(ss.double.global_position.distance_to(game.player.global_position) < .05, "Normally the reflection follows exactly")
	# запаздывание
	ss.start_lag()
	var start: Vector3 = game.player.global_position
	for i in 20:
		game.player.global_position = start + Vector3(0, 0, -.05 * i)
		ss._tick_mirror(.05)
		ss.clock += .05
	check(ss.lagging() and ss.double.global_position.distance_to(game.player.global_position) > .5, "During a scare the reflection lags a second behind")
	var san: float = game.sanity
	for i in int(ss.LAG_SECONDS / .1) + 2:
		ss.clock += .1
		ss._tick_mirror(.1)
	check(ss.stare_time > 0 and game.sanity < san, "Then it stops and stares — costs sanity")
	for i in 30:
		ss.clock += .1
		ss._tick_mirror(.1)
	check(ss.stare_time <= 0 and ss.double.global_position.distance_to(game.player.global_position) < .05, "Afterwards it snaps back to normal")
	game.exit_building()
	await frames(2)
	check(not ss.double.visible, "Reflection hidden outside")

	# свой голос
	game.day = 6
	game.campaign.state.day = 6
	game.campaign.state.night = true
	ss.voice_clock = 0
	ss._tick_voice(.1)
	check(game.radio.current == "own_1" and ss.voice_used.has("own_1"), "At night the radio speaks in your own voice")
	check(ss.play_own_voice() and ss.voice_used.has("own_2") and not ss.play_own_voice(), "Each voice line plays once")
	check(ResourceLoader.exists("res://assets/audio/voice/own_1.ogg") and ResourceLoader.exists("res://assets/audio/voice/own_2.ogg"), "Voice lines are recorded")

	# утро
	game.dread.ensure_props()
	var crate: Node3D = game.supplies.get_node("Supply_flare_crate")
	var before: Transform3D = crate.global_transform
	ss.night_was = true
	game.campaign.state.night = false
	game.day = 7
	seed(4)
	var moved: Array = ss.move_things()
	check(moved.size() == 2, "By night 7 two things are moved at dawn (%s)" % str(moved))
	ss.night_was = true
	ss._tick_dawn()
	check(not ss.moved_today.is_empty(), "Dawn triggers the moved-things check")
	# сохранение
	check(game.save_game(true), "Saved")
	ss.reset()
	check(game.load_game() and ss.voice_used.has("own_1") and ss.voice_used.has("own_2"), "Used voices are remembered across a reload")
	print("SMALL_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
