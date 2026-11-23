extends SceneTree
## Мрачная атмосфера: экранный мрак, ограниченная видимость, мерцание света,
## следы прошлого на острове и новые виды «присутствия».
const BAL = preload("res://scripts/balance.gd")
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
	game.save_path = "user://automated_atmosphere.json"
	await frames(3)
	var mat: ShaderMaterial = game.hud.atmosphere.material
	check(is_instance_valid(game.dread), "Dread director exists")
	check(float(mat.get_shader_parameter("menu")) > .5, "Title screen uses the ominous menu grade")
	game.start_shift()
	await frames(5)
	check(mat.get_shader_parameter("dread") != null and float(mat.get_shader_parameter("dread")) >= BAL.DREAD_DAY_LEVEL - .01, "Even daytime is graded gloomy")
	check(float(mat.get_shader_parameter("menu")) < .5, "Menu grade is off in play")

	# видимость: днём шире, ночью без фонаря — узкое пятно
	var day_sight: float = game.dread.target_sight()
	game.coastal_life.night_strength = 1.0
	game.player.lantern_on = false
	var dark_sight: float = game.dread.target_sight()
	game.player.lantern_on = true
	var lantern_sight: float = game.dread.target_sight()
	check(dark_sight < lantern_sight and lantern_sight < day_sight, "Night narrows sight; lantern widens it (%.2f < %.2f < %.2f)" % [dark_sight, lantern_sight, day_sight])
	game.coastal_life.night_strength = 0.0

	# следы прошлого
	game.dread.ensure_props()
	check(game.dread.stories.size() >= 6, "Environmental stories are placed (%d)" % game.dread.stories.size())
	check(game.dread.props_root.get_child_count() >= 10, "Decals and props spawned (%d)" % game.dread.props_root.get_child_count())
	check(game.dread.gulls.size() >= 2, "Dead gulls lie on the island")
	var story: Dictionary = game.dread.stories[0]
	var sanity_before: float = game.sanity
	game.player.global_position = story.at
	game.dread._update_stories()
	check(game.dread.found.has(story.id), "Walking up to a story reveals it")
	check(game.sanity < sanity_before, "A grim discovery costs a little sanity")
	var again: float = game.sanity
	game.dread._update_stories()
	check(is_equal_approx(game.sanity, again), "Each story fires once")

	# мерцание
	var ok_range := true
	for i in 200:
		game.dread.clock = i * .037
		var f: float = game.dread.flicker(i * 1.7)
		ok_range = ok_range and f >= 0.0 and f <= 1.0
	check(ok_range, "Flicker multiplier stays in 0..1")
	game.dread.blackout(1.0)
	check(game.dread.flicker(3.0) < .1, "Blackout kills the lights")
	game.dread.blackout_time = 0

	# сдвинутая чайка
	game.player.global_position = Vector3(-12, 1, -30)
	var moved: bool = game.dread.displace_gull()
	check(moved, "A far dead gull can reappear closer")

	# новые виды присутствия
	for kind in ["watcher", "water", "shutter", "blackout", "displace"]:
		check(kind in game.scares.TYPES, "Scare type registered: " + kind)
	game.player.global_position = Vector3(3, 1.1, 6.5)
	game.scares.fire("watcher")
	check(is_instance_valid(game.scares.watcher), "Watcher appears at the edge of sight")
	if is_instance_valid(game.scares.watcher):
		var d: float = game.scares.watcher.global_position.distance_to(game.player.global_position)
		check(d > BAL.WATCHER_VANISH_DIST, "Watcher keeps its distance (%.1f m)" % d)
		game.player.global_position = game.scares.watcher.global_position + Vector3(1, 0, 0)
		game.scares._tick_watcher(.1)
		check(not is_instance_valid(game.scares.watcher) or game.scares.watcher.is_queued_for_deletion(), "Watcher vanishes when approached")
	game.player.global_position = Vector3(19, 1.1, 4)
	game.scares.fire("water")
	check(is_instance_valid(game.scares.swimmer), "Something surfaces in the water near shore")
	if is_instance_valid(game.scares.swimmer):
		for i in 80:
			game.scares._tick_swimmer(.1)
		check(not is_instance_valid(game.scares.swimmer), "It sinks back under")
	game.scares.fire("shutter")
	game.scares.fire("blackout")
	check(game.dread.blackout_time > 0, "Blackout scare darkens the lights")
	game.dread.glitch_pulse(.8)
	check(game.dread.glitch >= .8, "Glitch pulse registers")
	await frames(30)
	check(float(mat.get_shader_parameter("glitch")) < .8, "Glitch decays")
	print("ATMOSPHERE_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
