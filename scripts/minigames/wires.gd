extends "res://scripts/minigames/mini_base.gd"
## Проводка генератора: соедините три оголённых провода с клеммами по цвету и числу полос,
## пока проводка не перегрелась. Свет мигает — в темноте цвета не различить.
const COLORS := [Color("c8453a"), Color("d8b14a"), Color("4d86c4")]
const NAMES := ["красный", "жёлтый", "синий"]
var order: Array = []          ## клемма → номер провода
var linked: Array = [-1, -1, -1]  ## провод → клемма
var selected := -1
var cursor := 0
var heat := 0.0
var limit := 13.0

func start() -> void:
	fail_kind = "shock"
	order = [0, 1, 2]
	order.shuffle()
	if order == [0, 1, 2]:
		order = [2, 0, 1]
	limit = clampf(14.0 - day * 0.25, 9.0, 14.0)

func title() -> String:
	return "Проводка генератора"

func hint() -> String:
	return "Соедините провода с клеммами по цвету и полосам: выберите провод, затем клемму. Свет мигает — не ошибитесь, второй удар током вас оглушит."

func controls() -> String:
	return "ЛКМ — провод, потом клемма   ·   ↑/↓ + пробел или 1–3   ·   Esc — отложить"

func _wire_pos(i: int, c: Vector2) -> Vector2:
	return Vector2(c.x - 190, c.y - 60 + i * 72)

func _term_pos(i: int, c: Vector2) -> Vector2:
	return Vector2(c.x + 190, c.y - 60 + i * 72)

func tick(delta: float) -> void:
	clock += delta
	if done():
		return
	heat += delta / limit
	if heat >= 1.0:
		finish(false, "Проводка вспыхнула! Генератор в дыму. Попробуйте снова (E).")
		sfx("zap", -4)
		shake(.5)

func _choose(row: int) -> void:
	if done():
		return
	if selected < 0:
		if linked[row] < 0:
			selected = row
			sfx("tick", -14, 1.2)
		return
	var wire := selected
	selected = -1
	if order[row] == wire and not linked.has(row):
		linked[wire] = row
		sfx("clank", -9, 1.3)
		burst(Color("ffe29a"), 12, _term_pos(row, host._center()))
		if not linked.has(-1):
			perfect = mistakes == 0
			finish(true, "Контакты держат. Гул генератора выровнялся." + (" Ни одной искры!" if perfect else ""))
	else:
		mistakes += 1
		heat = minf(.98, heat + .12)
		sfx("zap", -5, randf_range(.9, 1.1))
		shake(.45)
		burst(Color("9fd8ff"), 26, _term_pos(row, host._center()))
		if mistakes >= 2:
			finish(false, "Удар током! Руки трясутся. Отдышитесь и попробуйте снова (E).")

func act() -> void:
	_choose(cursor)

func key(code: int) -> bool:
	match code:
		KEY_UP, KEY_W:
			cursor = (cursor + 2) % 3
		KEY_DOWN, KEY_S:
			cursor = (cursor + 1) % 3
		KEY_1, KEY_2, KEY_3:
			cursor = code - KEY_1
			_choose(cursor)
		_:
			return false
	return true

func click(at: Vector2) -> void:
	var c: Vector2 = host._center()
	for i in 3:
		if at.distance_to(_wire_pos(i, c)) < 36 and selected < 0:
			cursor = i
			_choose(i)
			return
		if at.distance_to(_term_pos(i, c)) < 36 and selected >= 0:
			cursor = i
			_choose(i)
			return

func _stripes(at: Vector2, count: int, col: Color) -> void:
	for s in count:
		host.draw_rect(Rect2(at + Vector2(-14 + s * 11, -14), Vector2(6, 28)), col)

func draw(box: Rect2, c: Vector2) -> void:
	var light := lamp(1.0 + heat)
	var mouse: Vector2 = host.get_local_mouse_position()
	# коробка распределителя
	host.draw_rect(Rect2(c.x - 250, c.y - 110, 500, 250), Color(.08, .09, .08))
	host.draw_rect(Rect2(c.x - 250, c.y - 110, 500, 250), Color(.3, .28, .22, .6), false, 2)
	for i in 3:
		var w := _wire_pos(i, c)
		var t := _term_pos(i, c)
		var col: Color = COLORS[i].darkened(1.0 - light * .85)
		var hot: bool = cursor == i and selected < 0 and linked[i] < 0
		host.draw_line(Vector2(box.position.x + 20, w.y + sin(i * 2.0) * 20), w, col, 9)
		host.draw_circle(w, 15, col)
		_stripes(w + Vector2(0, 30), i + 1, col.lightened(.1))
		if selected == i or hot:
			host.draw_arc(w, 22, 0, TAU, 32, GOLD if selected == i else Color(GOLD, .4), 3)
		var tcol: Color = COLORS[order[i]].darkened(1.0 - light * .85)
		host.draw_rect(Rect2(t - Vector2(18, 18), Vector2(36, 36)), Color(.55, .52, .45).darkened(1.0 - light))
		_stripes(t + Vector2(48, 0), order[i] + 1, tcol)
		host.draw_circle(t, 7, Color(.15, .15, .15))
		if selected >= 0 and cursor == i:
			host.draw_arc(t, 26, 0, TAU, 32, Color(GOLD, .5), 2)
		text(str(i + 1), w + Vector2(-44, 6), 14, Color(PAPER, .5))
		text(str(i + 1), t + Vector2(84, 6), 14, Color(PAPER, .5))
		if linked[i] >= 0:
			host.draw_line(w, _term_pos(linked[i], c), COLORS[i].darkened(.4 - light * .3), 7)
	if selected >= 0:
		var from := _wire_pos(selected, c)
		host.draw_line(from, mouse if mouse.distance_to(c) < 320 else _term_pos(cursor, c), Color(COLORS[selected], .7), 5)
	# темнота при мигании света
	host.draw_rect(Rect2(c.x - 250, c.y - 110, 500, 250), Color(0, 0, 0, (1.0 - light) * .75))
	# перегрев
	var bar := Rect2(c.x - 220, c.y + 160, 440, 12)
	host.draw_rect(bar, Color(1, 1, 1, .08))
	host.draw_rect(Rect2(bar.position, Vector2(bar.size.x * heat, bar.size.y)), Color("ffb35c").lerp(RED, heat))
	text("Перегрев проводки", Vector2(c.x, bar.end.y + 20), 13, Color(PAPER, .7))
	if heat > .6 and randf() < heat * .4:
		burst(Color("ffd27a"), 2, Vector2(randf_range(c.x - 240, c.x + 240), c.y - 100))
