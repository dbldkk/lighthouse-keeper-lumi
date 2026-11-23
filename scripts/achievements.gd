extends Node
## Достижения и рекорды: 12 достижений с всплывающими плашками, статистика всех смен,
## экран «Рекорды» в главном меню. Хранится отдельно от сохранений: user://records.cfg.
const LIST := [
	["first_night", "Первая ночь", "Пережить первую ночь кампании."],
	["no_oil", "На ощупь", "Пережить ночь, в которую фонарь погас без масла."],
	["never_hide", "Без укрытия", "Пережить ночь охотника, ни разу не спрятавшись."],
	["untouched", "Невредимый", "Пережить ночь охотника, ни разу не попавшись."],
	["silent", "Ни звука", "Задержать дыхание, когда охотник в трёх шагах от укрытия."],
	["flare_repel", "Сигнал бедствия", "Отогнать охотника сигнальной ракетой."],
	["door_shut", "Не открывай", "Не впустить «спасателя», который стучал в дверь."],
	["ship_guided", "Лоцман", "Провести сейнер лучом маяка мимо камней."],
	["pier_escape", "Не у края", "Отойти от края причала, когда вода уже забурлила."],
	["archivist", "Архивариус", "Собрать все записи прежних смен."],
	["nightmare_night", "Кошмар наяву", "Пережить ночь охотника на сложности «Кошмар»."],
	["finish", "Курс на материк", "Дойти до конца кампании."],
]
const STATS := [
	["nights", "Ночей пережито"], ["best_day", "Лучший день кампании"], ["runs", "Смен начато"],
	["wins", "Кампаний пройдено"], ["deaths", "Гибелей"], ["catches", "Попаданий в лапы охотника"],
	["hides", "Раз прятались"], ["flares", "Ракет выпущено"], ["ships", "Судов проведено"],
	["play_minutes", "Минут на острове"],
]
const SILENT_DIST := 3.2
const SILENT_SECONDS := 1.5

var game: Node
var path := "user://records.cfg"
var unlocked := {}                 ## id → дата/время
var stats := {}
var night := {}                    ## флаги текущей ночи: hid, caught, oil_out, hunter
var silent_clock := 0.0
var play_clock := 0.0
var toast_queue: Array = []
var toast: PanelContainer
var toast_title: Label
var toast_text: Label
var toast_time := 0.0
var panel: Control
var toasts_shown := 0

func _ready() -> void:
	load_records()
	reset_night()

func reset_night() -> void:
	night = {"hid": false, "caught": false, "oil_out": false, "hunter": false}

func load_records() -> void:
	unlocked.clear()
	stats.clear()
	for s in STATS:
		stats[s[0]] = 0
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return
	for a in LIST:
		if c.has_section_key("unlocked", a[0]):
			unlocked[a[0]] = str(c.get_value("unlocked", a[0], ""))
	for s in STATS:
		stats[s[0]] = int(c.get_value("stats", s[0], 0))

func save_records() -> void:
	var c := ConfigFile.new()
	for id in unlocked:
		c.set_value("unlocked", id, unlocked[id])
	for k in stats:
		c.set_value("stats", k, stats[k])
	c.save(path)

func title_of(id: String) -> String:
	for a in LIST:
		if a[0] == id:
			return a[1]
	return id

func has(id: String) -> bool:
	return unlocked.has(id)

## Открыть достижение (один раз за всё время) и показать плашку.
func unlock(id: String) -> bool:
	if unlocked.has(id) or _demo():
		return false
	var found := false
	for a in LIST:
		if a[0] == id:
			found = true
			toast_queue.append(a)
	if not found:
		return false
	unlocked[id] = Time.get_datetime_string_from_system(false, true)
	save_records()
	if is_instance_valid(game) and is_instance_valid(game.sound):
		game.sound.cue("chime")
	return true

func add(stat: String, amount := 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + amount
	save_records()

func best(stat: String, value: int) -> void:
	if value > int(stats.get(stat, 0)):
		stats[stat] = value
		save_records()

func _demo() -> bool:
	return is_instance_valid(game) and (game.first_shift_demo.active() or not game.campaign.enabled)

# ---------------------------------------------------------------- события игры
func note(what: String) -> void:
	match what:
		"hid":
			night.hid = true
			add("hides")
		"caught":
			night.caught = true
			add("catches")
		"oil_out":
			night.oil_out = true
		"flare":
			add("flares")
		"run":
			add("runs")
		"death":
			add("deaths")
		"ship":
			add("ships")
			unlock("ship_guided")

func on_flare_repelled() -> void:
	unlock("flare_repel")

func on_night_survived(day: int) -> void:
	if _demo():
		return
	add("nights")
	best("best_day", day + 1)
	if day == 1:
		unlock("first_night")
	if night.oil_out:
		unlock("no_oil")
	if night.hunter:
		if not night.hid:
			unlock("never_hide")
		if not night.caught:
			unlock("untouched")
		if game.difficulty == "nightmare":
			unlock("nightmare_night")
	reset_night()

func on_run_finished(won: bool) -> void:
	if _demo():
		return
	if won:
		add("wins")
		unlock("finish")
	else:
		add("deaths")

func _process(delta: float) -> void:
	_tick_toast(delta)
	if not is_instance_valid(game) or not game.playing or game.paused or game.finished:
		return
	play_clock += delta
	if play_clock >= 60.0:
		play_clock -= 60.0
		add("play_minutes")
	var h = game.hunter
	if is_instance_valid(h) and h.active and game.campaign.state.night:
		night.hunter = true
		var close := false
		if h.hiding() and h.holding:
			var p: Vector3 = game.player.global_position
			close = Vector2(p.x - h.body.global_position.x, p.z - h.body.global_position.z).length() < SILENT_DIST
		silent_clock = silent_clock + delta if close else 0.0
		if silent_clock >= SILENT_SECONDS:
			unlock("silent")
	if is_instance_valid(game.lore) and game.lore.complete():
		unlock("archivist")

# ---------------------------------------------------------------- плашка
func _ensure_toast() -> void:
	if toast != null or not is_instance_valid(game) or game.hud == null:
		return
	toast = PanelContainer.new()
	toast.name = "AchievementToast"
	toast.add_theme_stylebox_override("panel", game.hud.style(Color(0.03, 0.08, 0.1, .94), Color("deb777"), 9))
	toast.position = Vector2(1440 - 430, 108)
	toast.custom_minimum_size = Vector2(400, 74)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	toast.add_child(box)
	toast_title = Label.new()
	toast_title.add_theme_font_size_override("font_size", 17)
	toast_title.add_theme_color_override("font_color", Color("deb777"))
	box.add_child(toast_title)
	toast_text = Label.new()
	toast_text.add_theme_font_size_override("font_size", 14)
	toast_text.add_theme_color_override("font_color", Color("e9e3ce"))
	toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_text.custom_minimum_size = Vector2(380, 0)
	box.add_child(toast_text)
	game.hud.root.add_child(toast)
	toast.hide()

func _tick_toast(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if toast != null:
			toast.modulate.a = clampf(toast_time / .4, 0, 1) if toast_time < .4 else clampf((4.2 - toast_time) / .3, 0, 1)
		if toast_time <= 0 and toast != null:
			toast.hide()
		return
	if toast_queue.is_empty():
		return
	_ensure_toast()
	if toast == null:
		return
	var a: Array = toast_queue.pop_front()
	toast_title.text = "★  Достижение: " + a[1]
	toast_text.text = a[2]
	toast.show()
	toast.move_to_front()
	toast_time = 4.2
	toasts_shown += 1

func toast_visible() -> bool:
	return toast != null and toast.visible

# ---------------------------------------------------------------- экран рекордов
func open_records() -> void:
	if panel != null:
		panel.queue_free()
	var hud = game.hud
	panel = Control.new()
	panel.name = "RecordsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, .72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", hud.style(Color(0.03, 0.08, 0.1, .97), Color("deb777"), 12))
	card.position = Vector2(170, 90)
	card.size = Vector2(1100, 720)
	panel.add_child(card)
	hud.text(card, "Рекорды и достижения", Rect2(40, 26, 700, 44), 32, hud.PAPER)
	hud.text(card, "Открыто %d из %d" % [unlocked.size(), LIST.size()], Rect2(700, 38, 360, 26), 16, hud.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.text(card, "СТАТИСТИКА", Rect2(40, 92, 300, 22), 13, hud.GOLD)
	var y := 124
	for s in STATS:
		hud.text(card, s[1], Rect2(40, y, 260, 24), 16, hud.MUTED)
		hud.text(card, str(stats.get(s[0], 0)), Rect2(300, y, 80, 24), 17, hud.PAPER).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		y += 34
	hud.text(card, "ДОСТИЖЕНИЯ", Rect2(430, 92, 300, 22), 13, hud.GOLD)
	y = 120
	for a in LIST:
		var got := unlocked.has(a[0])
		hud.text(card, ("★ " if got else "☆ ") + a[1], Rect2(430, y, 300, 24), 17, hud.GOLD if got else hud.MUTED)
		var d: Label = hud.text(card, a[2], Rect2(700, y + 2, 370, 40), 13, hud.PAPER if got else Color(hud.MUTED, .7))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		y += 46
	var close: Button = hud.make_button(card, "Закрыть", Vector2(40, 650), func(): close_records())
	close.size = Vector2(180, 44)
	hud.root.add_child(panel)
	close.grab_focus()

func records_open() -> bool:
	return panel != null and is_instance_valid(panel) and panel.visible

func close_records() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null

func _input(event: InputEvent) -> void:
	if records_open() and event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		close_records()
		get_viewport().set_input_as_handled()
