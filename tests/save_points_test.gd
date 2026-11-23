extends SceneTree
## Сохранение только у журнала смены; полное состояние; «Продолжить» в главном меню.
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
	game.save_path = "user://automated_logbook.json"
	if FileAccess.file_exists(game.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	game.start_shift()
	await frames(2)
	var sp: Node3D = game.save_points
	check(sp.books.size() == 2, "Logbooks in the cabin and the lighthouse")
	game.player.global_position = Vector3(10, 1.2, -6)
	check(not game.request_save() and not FileAccess.file_exists(game.save_path), "F9 in the open does not save")
	game.enter_building("cabin")
	await frames(1)
	game.player.global_position = sp.books[0].at + Vector3(-.6, .05, 0)
	check(not sp.near_book().is_empty(), "Cabin logbook is in reach from the floor")
	# состояние для проверки
	game.day = 6
	game.campaign.state.day = 6
	game.inventory.wood = 4
	game.lore.collect("roster")
	game.dread.found["claws"] = true
	game.hunter.announced = true
	game.hunter.catches = 2
	game.sanity = 61
	check(sp.interact() and FileAccess.file_exists(game.save_path), "E at the logbook saves")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	check(saved is Dictionary and saved.has("lore") and saved.has("hunter") and saved.has("dread_found"), "Save holds lore, hunter and story progress")
	# портим и грузим
	game.inventory.wood = 0
	game.lore.reset()
	game.dread.found.clear()
	game.hunter.catches = 0
	game.sanity = 100
	check(game.load_game(), "Load works")
	check(game.day == 6 and game.inventory.wood == 4 and is_equal_approx(game.sanity, 61), "Core state restored")
	check("roster" in game.lore.found and game.dread.found.has("claws") and game.hunter.catches == 2 and game.hunter.announced, "Lore, story marks and hunter memory restored")
	check(game.building_interiors.active == "cabin", "Restored inside the cabin")
	# маяк
	game.exit_building()
	game.set_lighthouse_interior(true)
	await frames(1)
	game.player.global_position = sp.books[1].at + Vector3(.5, .05, .3)
	check(not sp.near_book().is_empty() and game.request_save(), "Lighthouse logbook saves too")
	game.set_lighthouse_interior(false)
	# ночью при погоне — нельзя
	game.campaign.state.night = true
	game.hunter.active = true
	game.hunter.state = "chase"
	game.enter_building("cabin")
	game.player.global_position = sp.books[0].at + Vector3(-.6, .05, 0)
	check(not game.request_save(), "No saving while it is chasing you")
	game.hunter.state = "patrol"
	game.campaign.state.night = false
	game.exit_building()
	# главное меню
	game.return_to_title()
	await frames(1)
	game.hud.show_menu("title")
	check(game.hud.continue_button.visible and game.hud.continue_button.text == "Продолжить", "Title menu offers Continue")
	game.hud.continue_button.pressed.emit()
	await frames(2)
	check(game.playing and not game.finished and game.day == 6, "Continue resumes the saved shift")
	print("SAVE_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
