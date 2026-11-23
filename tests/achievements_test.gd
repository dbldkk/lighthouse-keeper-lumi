extends SceneTree
## Достижения, статистика и экран рекордов.
var game: Node
var a: Node
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
	game.save_path = "user://automated_achievements.json"
	a = game.achievements
	a.path = "user://automated_achievements_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(a.path))
	a.load_records()
	check(a.LIST.size() >= 8 and a.LIST.size() <= 12, "Достижений %d (8–12)" % a.LIST.size())
	check(a.unlocked.is_empty() and int(a.stats.nights) == 0, "Чистые рекорды")
	game.start_or_resume()
	game.tutorial.stop()
	await frames(2)
	check(int(a.stats.runs) == 1, "Новая смена засчитана в статистику")
	# первая ночь
	game.campaign.state.night = true
	game.campaign.finish_night()
	check(a.has("first_night") and int(a.stats.nights) == 1, "Пережили первую ночь — достижение и +1 ночь")
	await frames(1)
	a._process(.1)
	check(a.toast_visible() and a.toast_title.text.contains("Первая ночь"), "Всплывает плашка достижения")
	# ночь охотника без укрытий и поимок
	game.day = 3
	game.campaign.state.day = 3
	game.campaign.state.night = true
	game.hour = 23
	game.hunter.active = true
	a.reset_night()
	a._process(.1)
	check(a.night.hunter, "Ночь охотника замечена")
	a.on_night_survived(3)
	check(a.has("never_hide") and a.has("untouched"), "Без укрытия и невредимый")
	check(not a.has("nightmare_night"), "На обычной сложности «Кошмар наяву» не даётся")
	# прятался — «Без укрытия» не даётся
	a.unlocked.erase("never_hide")
	a.reset_night()
	a.night.hunter = true
	a.note("hid")
	a.on_night_survived(3)
	check(not a.has("never_hide") and int(a.stats.hides) == 1, "Спрятался — «Без укрытия» не открыто, укрытие посчитано")
	# фонарь погас без масла
	game.player.lantern_on = true
	game.lantern_oil = .01
	game.set_building_interior("")
	game.update_lantern_oil(1.0)
	check(a.night.oil_out, "Масло кончилось — отмечено")
	a.on_night_survived(3)
	check(a.has("no_oil"), "Пережили ночь без масла — «На ощупь»")
	# ракета отгоняет охотника
	game.hunter.active = true
	game.hunter.body.global_position = game.player.global_position + Vector3(6, 0, 0)
	game.supplies.flares = 1
	game.set_building_interior("")
	game.supplies.fire_flare()
	check(a.has("flare_repel") and int(a.stats.flares) == 1, "Ракета отогнала охотника — «Сигнал бедствия»")
	# задержка дыхания рядом с охотником
	var wardrobe: Dictionary = game.hunter.spots[0]
	game.hunter.hide_in(wardrobe.id)
	game.hunter.holding = true
	game.hunter.body.global_position = game.player.global_position + Vector3(1.5, 0, 0)
	for i in 20:
		game.hunter.holding = true
		a._process(.1)
	check(a.has("silent"), "Задержали дыхание в трёх шагах — «Ни звука»")
	game.hunter.leave_hiding()
	# кошмар
	game.difficulty = "nightmare"
	a.reset_night()
	a.night.hunter = true
	a.on_night_survived(4)
	check(a.has("nightmare_night"), "Ночь охотника на «Кошмаре»")
	game.difficulty = "normal"
	check(int(a.stats.best_day) >= 5, "Лучший день запомнен (%d)" % int(a.stats.best_day))
	# финал
	game.finish_shift(true)
	check(a.has("finish") and int(a.stats.wins) == 1, "Конец кампании — «Курс на материк»")
	# сохраняется между запусками
	var other: Node = a.duplicate()
	other.path = a.path
	other.load_records()
	check(other.unlocked.size() == a.unlocked.size() and int(other.stats.nights) == int(a.stats.nights), "Рекорды сохраняются в файл")
	other.free()
	# повтор не дублирует
	check(not a.unlock("first_night"), "Достижение открывается один раз")
	# экран рекордов
	game.return_to_title()
	await frames(1)
	check(game.hud.records_button.visible and game.hud.difficulty_button.visible, "В главном меню есть «Рекорды» и выбор сложности")
	game.hud.records_button.pressed.emit()
	await frames(1)
	check(a.records_open() and a.panel.get_parent() == game.hud.root, "Экран рекордов открывается")
	var texts := ""
	for n in a.panel.find_children("*", "Label", true, false):
		texts += (n as Label).text + "\n"
	var stamps := 0
	for n in a.panel.find_children("*", "TextureRect", true, false):
		if (n as TextureRect).texture == game.hud.UI.STAMP_RECORDED:
			stamps += 1
	# v1.3: открытые отмечены штампом «ЗАПИСАНО», закрытые — прочерком (без звёздочек-эмодзи)
	check(texts.contains("Ночей пережито") and texts.contains("Первая ночь") and texts.contains("Лоцман") and stamps == a.unlocked.size() and not texts.contains("★"), "На экране статистика, открытые (штамп ×%d) и закрытые достижения" % stamps)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.physical_keycode = KEY_ESCAPE
	a._input(esc)
	check(not a.records_open(), "Esc закрывает экран рекордов")
	print("ACHIEVEMENTS_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
