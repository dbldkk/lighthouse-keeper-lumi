extends SceneTree
## Обучение первого дня: шаги по порядку, постановка с укрытием и ракетой, показ один раз, пропуск, повтор.
var game: Node
var tut: Node
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
	game.save_path = "user://automated_tutorial_save.json"
	var prefs = game.preferences
	prefs.path = "user://automated_tutorial_settings.cfg"
	prefs.tutorial_done = false
	prefs.save_preferences()
	tut = game.tutorial
	tut.enabled = true
	check(game.hud.tutorial_button.visible, "The title menu offers «Обучение»")
	game.start_shift()
	await frames(2)
	check(tut.active() and tut.current() == "move" and tut.panel.visible, "A new campaign starts the tutorial with movement")
	check(tut.body_label.text.contains("Shift") and tut.body_label.text.contains("шум"), "Movement prompt teaches that running is noisy")
	check(tut.title_label.text.contains("1 / 7"), "The panel shows progress")
	tut.moved = 3.0
	tut.ran = 1.0
	await frames(2)
	check(tut.current() == "move", "Walking a little is not enough")
	tut.moved = 7.0
	await frames(2)
	check(tut.current() == "lantern" and tut.body_label.text.contains("ЗАПАС"), "Next: lantern and the oil reserve")
	game.toggle_lantern()
	await frames(2)
	check(tut.current() == "generator" and tut.body_label.text.contains("мини-игра"), "Next: fuel, generator and its mini-game")
	game.lighthouse_on = true
	await frames(2)
	check(tut.current() == "logbook" and tut.body_label.text.contains("хижину"), "Outside, the logbook step sends you into the cabin")
	game.enter_building("cabin")
	await frames(2)
	check(tut.body_label.text.contains("E") and tut.body_label.text.contains("журнал смены"), "Inside, it points at the logbook")
	check(tut.current() == "logbook" and tut.phase == "", "Hide scene waits until the logbook is done")
	game.save_points.write(game.save_points.books[0])
	await frames(2)
	check(tut.current() == "journal", "Saving at the logbook completes the step")
	game.open_journal()
	await frames(2)
	check(not tut.panel.visible, "The tutorial panel hides while the journal is open")
	game.close_journal()
	await frames(2)
	check(tut.current() == "hide" and tut.phase == "hide_wait" and tut.body_label.text.contains("шкаф"), "Scripted scene: steps outside — hide in the wardrobe")
	check(not game.hunter.active and not game.hunter.should_hunt(), "Day 1 has no hunter — the scene is safe")
	game.hunter.hide_in("wardrobe")
	await frames(2)
	check(tut.phase == "hold" and tut.body_label.text.contains("ПРОБЕЛ"), "Hidden: hold your breath")
	game.hunter.holding_forced = true
	await create_timer(1.9).timeout
	game.hunter.holding_forced = false
	await frames(2)
	check(tut.phase == "leave", "Holding breath for a moment passes the scene")
	game.hunter.leave_hiding()
	await frames(2)
	check(tut.current() == "flare" and tut.body_label.text.contains("Выйдите"), "Then: go outside for the flare")
	var flares_before: int = game.supplies.flares
	game.exit_building()
	await frames(3)
	check(tut.phase == "flare_aim" and is_instance_valid(tut.flare_shadow) and tut.flare_shadow.passive, "A harmless shadow appears by the path")
	check(tut.body_label.text.contains("X"), "Prompt explains the X flare")
	var hp: float = game.health
	await create_timer(1.0).timeout
	check(is_equal_approx(game.health, hp) and is_instance_valid(tut.flare_shadow), "The shadow does not attack and does not vanish")
	game.supplies.fire_flare()
	await frames(3)
	check(not tut.active() and not tut.panel.visible, "Firing the flare finishes the tutorial")
	check(game.supplies.flares == flares_before, "The training flare does not cost a real flare")
	check(prefs.tutorial_done, "Completion is remembered")
	prefs.tutorial_done = false
	prefs.load_preferences()
	check(prefs.tutorial_done, "…and survives reloading settings")
	game.start_shift()
	await frames(2)
	check(not tut.active() and not tut.panel.visible, "Shown once: the next campaign has no tutorial")
	game.return_to_title()
	await frames(1)
	game.hud.tutorial_button.pressed.emit()
	await frames(2)
	check(game.playing and tut.active() and tut.current() == "move", "«Обучение» in the menu replays it with a new shift")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_BACKSPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(1)
	check(not tut.active() and prefs.tutorial_done, "Backspace skips the tutorial and remembers it")
	# автопрохождение уже сделанных шагов
	prefs.tutorial_done = false
	game.start_shift()
	game.lighthouse_on = true
	tut.moved = 9.0
	tut.ran = 1.0
	tut.lantern_toggles = 2
	await frames(2)
	check(tut.current() == "logbook", "Steps already done by the player are skipped")
	tut.stop()
	game.campaign.state.night = true
	check(not game.hunter.should_hunt(), "First night stays hunter-free")
	for f in ["user://automated_tutorial_save.json", "user://automated_tutorial_settings.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("tutorial_test: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
