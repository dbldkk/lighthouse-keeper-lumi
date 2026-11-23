extends SceneTree
## Сложность: Обычная и «Кошмар» (охотник быстрее, масла меньше, без сохранений).
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

func hunter_step() -> float:
	var h: Node3D = game.hunter
	h.body.global_position = Vector3(3, 1, -2)
	h.detour_time = 0
	var from: Vector3 = h.body.global_position
	h._move(Vector3(3, 1, 12), 2.0, .5)
	return Vector2(h.body.global_position.x - from.x, h.body.global_position.z - from.z).length()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.save_path = "user://automated_difficulty.json"
	game.checkpoint_path = "user://automated_difficulty_checkpoint.json"
	game.preferences.path = "user://automated_difficulty_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.checkpoint_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	game.achievements.path = "user://automated_difficulty_records.cfg"
	# меню
	game.preferences.difficulty = "normal"
	game.hud.show_menu("title")
	check(game.hud.difficulty_button.visible and game.hud.difficulty_button.text.contains("Обычная"), "В меню выбрана обычная сложность")
	game.hud.difficulty_button.pressed.emit()
	check(game.preferences.difficulty == "nightmare" and game.hud.difficulty_button.text.contains("Кошмар"), "Кнопка переключает на «Кошмар»")
	var cfg := ConfigFile.new()
	cfg.load(game.preferences.path)
	check(str(cfg.get_value("progress", "difficulty", "")) == "nightmare", "Выбор сохраняется в настройках")
	# обычная смена — для сравнения
	game.preferences.difficulty = "normal"
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	check(game.difficulty == "normal", "Обычная смена")
	var normal_oil: float = game.supplies.oil_reserve
	var normal_step := hunter_step()
	game.campaign.state.night = true
	game.hour = 22
	game.set_building_interior("")
	game.player.lantern_on = true
	game.lantern_oil = 50
	game.update_lantern_oil(1.0)
	var normal_drain: float = 50 - game.lantern_oil
	check(FileAccess.file_exists(game.checkpoint_path), "На обычной есть автосохранение начала дня")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.checkpoint_path))
	# кошмар
	game.preferences.difficulty = "nightmare"
	game.finished = true
	game.last_run_won = true
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	check(game.difficulty == "nightmare", "Новая смена на «Кошмаре»")
	check(is_equal_approx(game.supplies.oil_reserve, normal_oil * .5), "Масла в запасе вдвое меньше (%d из %d)" % [game.supplies.oil_reserve, normal_oil])
	game.campaign.state.night = true
	game.hour = 22
	game.set_building_interior("")
	game.player.lantern_on = true
	game.lantern_oil = 50
	game.update_lantern_oil(1.0)
	check(50 - game.lantern_oil > normal_drain * 1.5, "Фонарь горит быстрее (%.2f против %.2f)" % [50 - game.lantern_oil, normal_drain])
	var fast := hunter_step()
	check(fast > normal_step * 1.1, "Охотник быстрее (%.2f против %.2f м)" % [fast, normal_step])
	check(game.hunter.CHASE_SPEED * 1.25 * float(game.diff("hunter_speed")) > 6.3, "На «Кошмаре» в погоне он быстрее бегущего смотрителя")
	check(not game.request_save(), "F9/пауза: сохранения нет")
	check(not game.save_points.write({"title": "Журнал"}), "Журнал смены не сохраняет")
	game.save_checkpoint()
	check(not FileAccess.file_exists(game.checkpoint_path), "Автосохранения начала дня нет")
	# гибель — только заново
	game.finish_shift(false)
	check(game.hud.menu_title.text.contains("Кошмар") and game.hud.start_button.text == "Начать заново", "После гибели — «Начать заново»")
	game.start_or_resume()
	game.tutorial.stop()
	await frames(1)
	check(game.day == 1 and game.difficulty == "nightmare", "Новая попытка — с первого дня, снова «Кошмар»")
	# сохранение помнит сложность (обычная загрузка старой игры)
	game.difficulty = "nightmare"
	check(game.save_game(true), "Служебная запись состояния работает")
	game.difficulty = "normal"
	game.load_game()
	check(game.difficulty == "nightmare", "Сложность хранится в сохранении")
	# демо и обучение — всегда обычные
	game.start_first_shift_demo()
	check(game.difficulty == "normal", "Демо — на обычной сложности")
	game.preferences.difficulty = "normal"
	print("DIFFICULTY_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
