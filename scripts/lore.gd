extends Node3D
## Сюжет: кто был прежним смотрителем и кто говорит в эфире.
## Записки, страницы дневника и кассеты лежат по острову (появляются по дням), читаются в журнале (J).
## Последняя ночь — выбор: зажечь маяк, оставить тьму или (если собраны все записи) сжечь журнал.
const Geo = preload("res://scripts/geometry.gd")

const ITEMS := [
	{"id":"roster","kind":"note","day":2,"at":Vector3(-3.5,1,8.5),"title":"Ведомость смены, 1979",
	 "text":"«Маяк „Северный“. Смотритель: С. Лагин. Смена — 14 суток. Сменщик — по прибытии катера».\n\nВнизу приписка карандашом: «Если не вернусь — не гасите свет. Что бы ни говорили по радио»."},
	{"id":"diary_1","kind":"diary","day":2,"at":Vector3(12.5,1,-8.5),"title":"Дневник Лагина · стр. 3",
	 "text":"Третья ночь. По острову кто-то ходит. Большой — кусты ломаются, как под лосем, только лосей здесь нет.\n\nОн идёт на шум. И на свет фонаря. Я погасил фонарь и сидел в шкафу, пока не рассвело. Дышать старался через раз.\n\nМаяка он боится. Пока горит линза, он не подходит к башне."},
	{"id":"tape_1","kind":"tape","day":3,"at":Vector3(-12.5,1,-13.5),"voice":"tape_1","title":"Кассета № 1 · С. Лагин",
	 "text":"«Если ты это слушаешь, значит, тебя тоже высадили. Меня зовут Семён Лагин, я смотритель маяка „Северный“. Ночью по острову ходит кто-то большой. Он идёт на шум и на свет фонаря. Маяка он боится»."},
	{"id":"crew","kind":"note","day":4,"at":Vector3(15.5,1,-1.5),"title":"Список экипажа «Северного», 1961",
	 "text":"Шесть фамилий. Напротив пяти — крестики и одно слово: «утонул».\n\nШестая строка пустая. Но в графе «подпись» стоит росчерк — ваш. Вы узнаёте его, потому что так расписываетесь сами."},
	{"id":"diary_2","kind":"diary","day":5,"at":Vector3(1.5,1,-26.5),"title":"Дневник Лагина · стр. 9",
	 "text":"Почерк в журнале — мой. Даже те записи, что сделаны до моей высадки.\n\nКажется, я понял. Остров держит смотрителя, пока горит свет. Свет — это договор. Погасишь — останешься здесь навсегда, только уже не человеком.\n\nТот, кто ходит, тоже когда-то был смотрителем."},
	{"id":"tape_2","kind":"tape","day":6,"at":Vector3(-9.5,1,-31.5),"voice":"tape_2","title":"Кассета № 2 · Берег-четыре",
	 "text":"«Говорит Берег-четыре. Это автоматическая запись. Станция закрыта осенью семьдесят девятого года. Если на этой частоте вам отвечает живой голос, не верьте ему»."},
	{"id":"drawing","kind":"note","day":7,"at":Vector3(-15.5,1,-21.5),"title":"Детский рисунок",
	 "text":"Маяк, море, человечек в жёлтом плаще. Подпись печатными буквами: «ПАПА НА МАЯКЕ».\n\nНа обороте, другой рукой: «Папа не вернулся. За ним ходил высокий»."},
	{"id":"diary_3","kind":"diary","day":8,"at":Vector3(18.5,1,7.5),"title":"Дневник Лагина · стр. 12",
	 "text":"Видел его близко. Он в плаще. В моём плаще — я узнал заплату на локте.\n\nОн не злой. Он ищет, кто зажжёт свет вместо него. Голос в эфире — его. Он учится говорить нашими голосами.\n\nЕсли услышишь по радио себя — не отвечай."},
	{"id":"diary_4","kind":"diary","day":10,"at":Vector3(-6.5,1,2.5),"title":"Дневник Лагина · последняя страница",
	 "text":"Журнал — это якорь. Каждый смотритель пишет в нём, и круг идёт дальше: один зажигает свет, другой ходит в темноте.\n\nВыход один: в последнюю ночь сжечь журнал вместе со всеми записями. Тогда некому будет зажигать свет. И некому будет ходить.\n\nУ меня не хватило духу. Может, хватит у тебя."},
	{"id":"tape_3","kind":"tape","day":11,"at":Vector3(4.5,1,-17.5),"voice":"tape_3","title":"Кассета № 3 · без подписи",
	 "text":"«Это я. Ты. Мы уже были здесь, и не один раз. Журнал держит нас на острове. В последнюю ночь сожги журнал. Тогда некому будет зажигать свет. И некому будет ходить в темноте»."},
]

const ENDINGS := {
	"light": {"title":"Курс\nна материк", "stamp":"КОНЦОВКА 1 ИЗ 3   /   СВЕТ",
		"subtitle":"Вы удержали маяк и ушли на рассвете.",
		"text":"Катер «Северный» уходит к материку. За кормой ровно вращается луч — вы оставили генератор полным.\n\nНа берегу у буя вас встречает человек в жёлтом плаще. Он пожимает вам руку, берёт журнал и садится в вашу лодку.\n\n— Моя смена, — говорит он вашим голосом.\n\nКруг продолжается. Но свет горит."},
	"dark": {"title":"Тьма", "stamp":"КОНЦОВКА 2 ИЗ 3   /   ТЬМА",
		"subtitle":"Вы позволили маяку погаснуть.",
		"text":"Генератор затихает. Луч гаснет, и шторм накрывает остров целиком.\n\nОн выходит из темноты и останавливается рядом. Больше не охотится — ждёт. Плащ на нём сухой.\n\nУтром на остров высадится новый смотритель. Он найдёт журнал, исписанный вашим почерком, и услышит по радио голос, очень похожий на свой.\n\nТеперь в темноте ходите вы."},
	"truth": {"title":"Последний\nсмотритель", "stamp":"КОНЦОВКА 3 ИЗ 3   /   КРУГ РАЗОРВАН",
		"subtitle":"Вы сожгли журнал и все записи.",
		"text":"Страницы горят быстро — тридцать лет почерка, одинакового в каждой строке.\n\nМаяк гаснет сам. Радио замолкает на полуслове. Шаги в темноте останавливаются — и больше не возобновляются.\n\nНа рассвете к острову подходит катер. На берегу никого. Только пепел на камнях и пустая башня, в которую больше никто не придёт.\n\nКруг разорван."},
}

var game: Node
var found: Array = []
var ending := ""
var root3d: Node3D
var props := {}
var choice_layer: CanvasLayer
var choice_panel: Control
var choice_buttons := {}
var card_layer: CanvasLayer
var card_title: Label
var card_text: Label

func setup() -> void:
	_build_choice()
	_build_card()

func reset() -> void:
	found.clear()
	ending = ""
	for id in props.keys():
		if is_instance_valid(props[id]):
			props[id].queue_free()
	props.clear()
	close_choice()
	if is_instance_valid(card_layer):
		card_layer.hide()

func total() -> int:
	return ITEMS.size()

func count() -> int:
	return found.size()

func complete() -> bool:
	return found.size() >= ITEMS.size()

func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}

func available(it: Dictionary) -> bool:
	return game.campaign.enabled and game.day >= int(it.day) and it.id not in found

# ---------------------------------------------------------------- предметы на острове
func _process(_delta: float) -> void:
	if not is_instance_valid(game) or not game.playing:
		return
	for it in ITEMS:
		var show: bool = available(it)
		if show and not props.has(it.id):
			props[it.id] = _spawn_prop(it)
		elif not show and props.has(it.id):
			if is_instance_valid(props[it.id]):
				props[it.id].queue_free()
			props.erase(it.id)

func _ground_near(at: Vector3) -> Vector3:
	for r in [0.0, 1.0, 2.0, 3.0, 4.5]:
		for i in 8:
			var g: Variant = game.night_raids.ground_at(at + Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8)) * r)
			if g != null:
				return (g as Vector3) - Vector3(0, .35, 0)
	return at

func prop_position(id: String) -> Vector3:
	return props[id].global_position if props.has(id) and is_instance_valid(props[id]) else _ground_near(item(id).at)

func _spawn_prop(it: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Lore_" + str(it.id)
	game.world.add_child(root)
	root.global_position = _ground_near(it.at)
	match str(it.kind):
		"tape":
			Geo.box(root, "Cassette", Vector3(0, .05, 0), Vector3(.26, .06, .17), Color("1b1b1d"))
			Geo.box(root, "Label", Vector3(0, .085, 0), Vector3(.2, .01, .08), Color("d9cfae"))
		"diary":
			Geo.box(root, "Page", Vector3(0, .03, 0), Vector3(.3, .02, .38), Color("cfc3a2"))
			Geo.box(root, "Ink", Vector3(0, .045, 0), Vector3(.22, .005, .26), Color("6b6252"))
		_:
			Geo.box(root, "Note", Vector3(0, .03, 0), Vector3(.28, .02, .22), Color("e0d6bc"))
	root.rotation.y = hash(it.id) % 628 / 100.0
	# без OmniLight: в Compatibility у одного меша не больше 8 источников, а остров — один меш
	for child in root.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = ((child.material_override as StandardMaterial3D).albedo_color if child.material_override is StandardMaterial3D else Color("e0d6bc"))
			mat.emission_enabled = true
			mat.emission = Color("f3dcae")
			mat.emission_energy_multiplier = .35
			child.material_override = mat
	var label := Label3D.new()
	label.text = "◆"
	label.font_size = 30
	label.modulate = Color(.95, .86, .62, .8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, .7, 0)
	root.add_child(label)
	return root

func near_item() -> String:
	if not game.lighthouse_interior.active and game.building_interiors.active.is_empty():
		var p: Vector3 = game.player.global_position
		for id in props:
			if is_instance_valid(props[id]):
				var at: Vector3 = props[id].global_position
				if Vector2(p.x - at.x, p.z - at.z).length() < 1.5:
					return id
	return ""

func interact() -> bool:
	var id := near_item()
	if id.is_empty():
		return false
	collect(id)
	return true

func collect(id: String) -> void:
	if id in found or item(id).is_empty():
		return
	var it := item(id)
	found.append(id)
	var jid := "l:" + id
	if jid not in game.journal_entries:
		game.journal_entries.append(jid)
	if props.has(id) and is_instance_valid(props[id]):
		props[id].queue_free()
	props.erase(id)
	game.sound.interact("paper")
	game.sanity = maxf(0, game.sanity - 2)
	if str(it.kind) == "tape":
		game.radio.say(str(it.voice), false, true)
		game.notify("%s. Кассета играет в диктофоне. (J — журнал, %d из %d записей)" % [it.title, count(), total()], 8, 1)
	else:
		game.notify("%s.  (J — журнал, %d из %d записей)" % [it.title, count(), total()], 8, 1)
	if complete():
		game.notify("Вы собрали все записи прежних смен. Последняя ночь может закончиться иначе.", 9, 1)

func journal_entry(jid: String) -> Dictionary:
	if not jid.begins_with("l:"):
		return {}
	var it := item(jid.trim_prefix("l:"))
	if it.is_empty():
		return {}
	var kind: String = {"tape":"КАССЕТА · Пробел — прослушать","diary":"СТРАНИЦА ДНЕВНИКА","note":"ЗАПИСКА"}.get(it.kind, "")
	return {"title": it.title, "text": it.text + "\n\n— " + kind + " · записи %d из %d" % [count(), total()]}

## Пробел в журнале на странице кассеты — прослушать ещё раз.
func replay(jid: String) -> bool:
	var it := item(jid.trim_prefix("l:"))
	if it.is_empty() or str(it.kind) != "tape":
		return false
	game.radio.say(str(it.voice), false, true)
	return true

# ---------------------------------------------------------------- последняя ночь
func final_night_now() -> bool:
	return game.campaign.enabled and game.campaign.state.night and game.day == game.campaign.final_night()

func _build_choice() -> void:
	choice_layer = CanvasLayer.new()
	choice_layer.layer = 40
	add_child(choice_layer)
	choice_panel = ColorRect.new()
	(choice_panel as ColorRect).color = Color(0, 0, 0, .72)
	choice_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	choice_layer.add_child(choice_panel)
	var box := VBoxContainer.new()
	box.anchor_left = .3
	box.anchor_right = .7
	box.anchor_top = .28
	box.anchor_bottom = .8
	box.add_theme_constant_override("separation", 14)
	choice_panel.add_child(box)
	var title := Label.new()
	title.text = "Генератор маяка"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("efe3c6"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := Label.new()
	body.text = "Последняя ночь. Шторм ломится в башню. За дверью ждёт тот, кто ходит.\nРешение нельзя будет отменить."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", Color("b9c4bf"))
	box.add_child(body)
	for key in ["light", "dark", "truth"]:
		var b := Button.new()
		b.text = {"light":"Зажечь маяк и дождаться утра","dark":"Оставить маяк тёмным","truth":"Сжечь журнал и все записи"}[key]
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(choose.bind(key))
		box.add_child(b)
		choice_buttons[key] = b
	choice_layer.hide()

func choice_open() -> bool:
	return is_instance_valid(choice_layer) and choice_layer.visible

func open_final_choice() -> void:
	choice_buttons.truth.visible = complete()
	choice_layer.show()
	game.player.enabled = false
	game.paused = true

func close_choice() -> void:
	if is_instance_valid(choice_layer) and choice_layer.visible:
		choice_layer.hide()
		game.paused = false
		game.player.enabled = not game.finished and not game.hunter.hiding()

func choose(key: String) -> void:
	close_choice()
	match key:
		"light":
			ending = "light"
			game.campaign.restore_beacon()
		"dark":
			ending = "dark"
			game.lighthouse_on = false
			game.beacon.set_powered(false)
			game.notify("Вы опускаете рубильник. Шторм накрывает остров.", 4, 2)
			game.finish_shift(true)
		"truth":
			if not complete():
				return
			ending = "truth"
			game.notify("Страницы вспыхивают одна за другой.", 4, 2)
			game.finish_shift(true)

# ---------------------------------------------------------------- финальный экран
func _build_card() -> void:
	card_layer = CanvasLayer.new()
	card_layer.layer = 55
	add_child(card_layer)
	var bg := ColorRect.new()
	bg.color = Color("040608")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_layer.add_child(bg)
	card_title = Label.new()
	card_title.add_theme_font_size_override("font_size", 54)
	card_title.add_theme_color_override("font_color", Color("efe3c6"))
	card_title.anchor_left = .12
	card_title.anchor_right = .88
	card_title.anchor_top = .1
	card_title.anchor_bottom = .1
	bg.add_child(card_title)
	card_text = Label.new()
	card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_text.add_theme_font_size_override("font_size", 19)
	card_text.add_theme_color_override("font_color", Color("b9c4bf"))
	card_text.anchor_left = .12
	card_text.anchor_right = .7
	card_text.anchor_top = .36
	card_text.anchor_bottom = .86
	bg.add_child(card_text)
	var b := Button.new()
	b.text = "Продолжить"
	b.anchor_left = .12
	b.anchor_top = .88
	b.anchor_bottom = .88
	b.offset_right = 220
	b.offset_bottom = 44
	b.pressed.connect(func(): card_layer.hide())
	bg.add_child(b)
	card_layer.hide()

func show_card() -> void:
	if not ENDINGS.has(ending):
		return
	card_title.text = ENDINGS[ending].title
	card_text.text = ENDINGS[ending].text + "\n\nЗаписи прежних смен: %d из %d." % [count(), total()]
	card_layer.show()

func card_visible() -> bool:
	return is_instance_valid(card_layer) and card_layer.visible

# ---------------------------------------------------------------- сохранение
func save_data() -> Dictionary:
	return {"found": found.duplicate(), "ending": ending}

func restore(data: Variant) -> void:
	reset()
	if data is Dictionary:
		for id in data.get("found", []):
			if not item(str(id)).is_empty() and str(id) not in found:
				found.append(str(id))
		ending = str(data.get("ending", ""))
