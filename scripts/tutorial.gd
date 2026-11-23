extends Node
## Обучение в первый день кампании (ночь 1 — без охотника).
## Контекстные подсказки по порядку + короткая постановка: «шаги снаружи» → укрытие и задержка дыхания,
## затем безвредная тень у тропы → сигнальная ракета. Пропуск — Backspace. Показывается один раз
## (флаг в настройках), повтор — кнопка «Обучение» в главном меню.
const BI = preload("res://scripts/building_interiors.gd")
const SKIP_KEY := KEY_BACKSPACE
const STEPS := ["move", "lantern", "generator", "logbook", "journal", "hide", "flare"]

var game: Node
var enabled := DisplayServer.get_name() != "headless"   ## тесты включают вручную
var running := false
var step := 0
var phase := ""                 ## для постановочных шагов: hide_wait, hold, leave; flare_go, flare_aim
var done_steps: Array = []
var shown_text := ""
# наблюдения
var moved := 0.0
var ran := 0.0
var last_pos := Vector3.ZERO
var lantern_toggles := 0
var lantern_was := true
var journal_seen := false
var minigame_seen := false
var held := 0.0
var cue_clock := 0.0
var cue_count := 0
var flare_shadow: Node3D
var flares_before := 0
var gifted := false
var writes_base := 0
# интерфейс
var panel: Panel
var title_label: Label
var body_label: Label
var footer_label: Label

func setup() -> void:
	pass

func _ensure_panel() -> void:
	if panel != null or game.hud == null or game.hud.game_ui == null:
		return
	var hud = game.hud
	panel = hud.panel(hud.game_ui, Rect2(1017, 300, 391, 200), Color(0.05, 0.12, 0.13, 0.92))
	panel.name = "TutorialPanel"
	panel.add_theme_stylebox_override("panel", hud.style(Color(0.05, 0.12, 0.13, 0.92), Color("deb777"), 9))
	title_label = hud.text(panel, "", Rect2(18, 12, 355, 20), 12, hud.GOLD)
	body_label = hud.text(panel, "", Rect2(18, 38, 355, 120), 16, hud.PAPER)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label = hud.text(panel, "Backspace — пропустить обучение", Rect2(18, 170, 355, 18), 11, hud.MUTED)
	panel.hide()

## Вызывается в начале новой смены кампании.
func begin() -> void:
	stop()
	if not enabled or not game.campaign.enabled or game.first_shift_demo.active() or game.preferences.tutorial_done:
		return
	_ensure_panel()
	running = true
	step = 0
	phase = ""
	done_steps.clear()
	moved = 0.0
	ran = 0.0
	last_pos = game.player.global_position
	lantern_toggles = 0
	lantern_was = game.player.lantern_on
	journal_seen = false
	minigame_seen = false
	held = 0.0
	gifted = false
	writes_base = game.save_points.writes

func stop() -> void:
	running = false
	phase = ""
	if is_instance_valid(flare_shadow):
		flare_shadow.queue_free()
	flare_shadow = null
	if panel:
		panel.hide()

func active() -> bool:
	return running

func current() -> String:
	return STEPS[step] if running and step < STEPS.size() else ""

func skip() -> void:
	if not running:
		return
	stop()
	_finish_flag()
	game.notify("Обучение пропущено. Его можно пройти снова: главное меню → «Обучение».", 5)

func _finish_flag() -> void:
	game.preferences.tutorial_done = true
	game.preferences.save_preferences()

func handle_key(code: int) -> bool:
	if running and code == SKIP_KEY:
		skip()
		return true
	return false

func _process(delta: float) -> void:
	if not running:
		return
	if not game.playing or game.finished or game.day != 1 or not game.campaign.enabled:
		if game.playing and (game.day != 1 or not game.campaign.enabled):
			stop()
		elif panel:
			panel.hide()
		return
	_observe(delta)
	_advance(delta)
	_show()

func _observe(delta: float) -> void:
	var p: Vector3 = game.player.global_position
	var flat := Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
	if flat < 3.0:    # телепорт через дверь не считается шагом
		moved += flat
	last_pos = p
	if game.player.is_running:
		ran += delta
	if game.player.lantern_on != lantern_was:
		lantern_was = game.player.lantern_on
		lantern_toggles += 1
	if game.journal_open:
		journal_seen = true
	if is_instance_valid(game.minigames) and game.minigames.visible:
		minigame_seen = true

func _done(id: String) -> bool:
	match id:
		"move": return moved >= 6.0 and ran >= .6
		"lantern": return lantern_toggles >= 1
		"generator": return game.lighthouse_on or minigame_seen
		"logbook": return game.save_points.writes > writes_base
		"journal": return journal_seen
	return id in done_steps

func _advance(delta: float) -> void:
	while step < STEPS.size() and _done(STEPS[step]):
		_complete_step()
	if step >= STEPS.size():
		return
	match STEPS[step]:
		"hide": _tick_hide(delta)
		"flare": _tick_flare(delta)

func _complete_step() -> void:
	var id: String = STEPS[step]
	if id not in done_steps:
		done_steps.append(id)
	step += 1
	phase = ""
	game.sound.interact("paper")
	if step >= STEPS.size():
		running = false
		panel.hide()
		_finish_flag()
		game.notify("Обучение пройдено. Дальше — сами. Со второй ночи по острову ходит охотник.", 7)

func _in_cabin() -> bool:
	return game.building_interiors.active == "cabin"

func _outside() -> bool:
	return game.building_interiors.active.is_empty() and not game.lighthouse_interior.active

# ---------------------------------------------------------------- укрытие (постановка)
func _tick_hide(delta: float) -> void:
	var hunter = game.hunter
	match phase:
		"":
			if _in_cabin():
				phase = "hide_wait"
				cue_clock = 0.0
				cue_count = 0
				game.sound.horror_cue("knock", _window())
		"hide_wait":
			cue_clock += delta
			if cue_clock > 3.0 and cue_count < 6:
				cue_clock = 0.0
				cue_count += 1
				game.sound.horror_cue("steps", _window() + Vector3(randf_range(-1.5, 1.5), 0, 0))
			if hunter.hiding():
				phase = "hold"
				held = 0.0
				cue_clock = 0.0
		"hold":
			if not hunter.hiding():
				phase = "hide_wait"
				return
			cue_clock += delta
			if cue_clock > 1.2:
				cue_clock = 0.0
				game.sound.horror_cue("steps", _window())
			if hunter.holding and hunter.breath > 0:
				held += delta
			if held >= 1.5:
				phase = "leave"
				game.sound.horror_cue("whisper", _window())
		"leave":
			if not hunter.hiding():
				done_steps.append("hide")

func _window() -> Vector3:
	return BI.ROOMS.cabin.origin + Vector3(-1.87, 1.45, -2.22)

# ---------------------------------------------------------------- ракета (постановка)
func _tick_flare(_delta: float) -> void:
	var supplies = game.supplies
	match phase:
		"":
			if _outside():
				phase = "flare_aim"
				flares_before = supplies.flares
				gifted = supplies.flares <= 0
				if gifted:
					supplies.flares = 1
				_spawn_shadow()
		"flare_aim":
			if is_instance_valid(flare_shadow):
				flare_shadow.life_clock = 0.0     # безвредная тень не исчезает сама
			if supplies.flare_active() or (not is_instance_valid(flare_shadow) and supplies.flares < maxi(1, flares_before)):
				# учебная ракета не тратит запас
				supplies.flares = flares_before
				if is_instance_valid(flare_shadow) and flare_shadow.has_method("burn"):
					flare_shadow.burn(1000)
				done_steps.append("flare")
			elif not _outside():
				phase = ""
				if is_instance_valid(flare_shadow):
					flare_shadow.queue_free()

func _spawn_shadow() -> void:
	var p: Vector3 = game.player.global_position
	var at := p + Vector3(5.5, .3, -2.0)
	var ground: Variant = game.night_raids.ground_at(at)
	if ground != null:
		at = (ground as Vector3) + Vector3.UP * .2
	# не в game.enemies: днём список врагов очищается, а эта тень — часть урока
	flare_shadow = game.SHADOW_SCENE.instantiate()
	flare_shadow.position = at
	flare_shadow.keeper = game.player
	flare_shadow.game = game
	flare_shadow.passive = true
	flare_shadow.stationary = true
	game.add_child(flare_shadow)

# ---------------------------------------------------------------- подсказка
func _k(action: String) -> String:
	return game.preferences.key_name(action)

func text_for(id: String) -> String:
	match id:
		"move":
			return "WASD — идти, %s — бег.\nБег слышно издалека: со второй ночи на шум приходит охотник. Пройдитесь и пробегитесь." % _k("sprint")
		"lantern":
			return "%s — фонарь. Масло горит (шкала МАСЛО). В хижине и маяке фонарь доливается из ЗАПАСА — а запас не бесконечен.\nНочью полная тьма (без фонаря, маяка и крыши) через ~45 с начинает забирать здоровье — над экраном появится «ТЕМНОТА ЗАБИРАЕТ СИЛЫ». Свет сразу останавливает урон. Погасите и зажгите фонарь." % _k("lantern")
		"generator":
			if game.inventory.fuel >= 1:
				return "Канистра у вас. Отнесите её к генератору у маяка и нажмите %s. Запуск — мини-игра: E или Пробел, когда стрелка в секторе." % _k("interact")
			return "Найдите канистру на тропе (бирюзовый столб света) и запустите генератор у маяка. Запуск — короткая мини-игра."
		"logbook":
			if _in_cabin() or game.lighthouse_interior.active:
				return "Видите «✎ журнал смены»? Подойдите и нажмите %s — игра сохранится. Сохраняться можно только у журналов." % _k("interact")
			return "Зайдите в хижину (E у двери). Внутри лежит журнал смены — у него сохраняются."
		"journal":
			return "%s — записи: задания дня, найденные страницы и кассеты прежнего смотрителя. Откройте журнал и закройте его." % _k("journal")
		"hide":
			match phase:
				"hide_wait":
					return "Снаружи кто-то ходит. Спрячьтесь: подойдите к шкафу и нажмите %s." % _k("interact")
				"hold":
					return "Шаги у самой стены. Зажмите %s — задержите дыхание. Шкала внизу — сколько выдержите." % _k("breath").to_upper()
				"leave":
					return "Тихо. Сегодня это был ветер. %s — выйти из шкафа.\nСо второй ночи прячьтесь по-настоящему." % _k("interact")
			return "Вернитесь в хижину — там есть шкаф-укрытие."
		"flare":
			if phase == "flare_aim":
				return "У тропы стоит тень. Сегодня она безвредна. %s — сигнальная ракета: отгоняет охотника и сжигает тени рядом. Выстрелите." % _k("flare")
			return "Выйдите из хижины."
	return ""

func _show() -> void:
	if step >= STEPS.size():
		panel.hide()
		return
	var blocked: bool = game.paused or game.journal_open or (is_instance_valid(game.minigames) and game.minigames.visible)
	panel.visible = not blocked
	title_label.text = "ОБУЧЕНИЕ · %d / %d" % [step + 1, STEPS.size()]
	shown_text = text_for(STEPS[step])
	body_label.text = shown_text
