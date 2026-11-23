extends Node3D
## Журнал смены — единственное место ручного сохранения: в хижине и на первом этаже маяка.
## F9 и «Сохранить» в меню паузы работают только рядом с ним. Рассветный чекпойнт остаётся
## для повтора дня после гибели.
const Geo = preload("res://scripts/geometry.gd")
const BI = preload("res://scripts/building_interiors.gd")
const LI = preload("res://scripts/lighthouse_interior.gd")
const REACH := 1.25

var game: Node
var books: Array = []    ## {"id","title","at"}
var writes := 0          ## сколько раз сохранились у журнала (для обучения)

func setup() -> void:
	books = [
		{"id":"cabin", "title":"Журнал смены в хижине", "at": BI.ROOMS.cabin.origin + Vector3(2.15, 0, 1.25)},
		{"id":"lighthouse", "title":"Вахтенный журнал маяка", "at": LI.ORIGIN + Vector3(.25, 0, -1.45)},
	]
	for b in books:
		var root := Node3D.new()
		root.name = "Logbook_" + str(b.id)
		add_child(root)
		root.global_position = b.at
		if b.id == "lighthouse":
			Geo.box(root, "Stand", Vector3(0, .45, 0), Vector3(.42, .9, .34), Color("3a2b1f"))
		var y := .92 if b.id == "lighthouse" else .9
		Geo.box(root, "Book", Vector3(0, y, 0), Vector3(.36, .06, .27), Color("5a1f1a"))
		Geo.box(root, "Pages", Vector3(0, y + .035, 0), Vector3(.32, .015, .24), Color("d8cfb3"))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("ffcf91")
		lamp.light_energy = .45
		lamp.omni_range = 1.4
		lamp.position = Vector3(0, y + .5, 0)
		root.add_child(lamp)
		var label := Label3D.new()
		label.text = "✎ журнал смены"
		label.font_size = 24
		label.modulate = Color(.95, .87, .66, .7)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, y + .55, 0)
		root.add_child(label)

func near_book() -> Dictionary:
	if not is_instance_valid(game) or not game.playing:
		return {}
	var p: Vector3 = game.player.global_position
	for b in books:
		var at: Vector3 = b.at
		if Vector2(p.x - at.x, p.z - at.z).length() < REACH and absf(p.y - at.y) < 1.5:
			return b
	return {}

func interact() -> bool:
	var b := near_book()
	if b.is_empty():
		return false
	write(b)
	return true

func write(b: Dictionary) -> bool:
	if not game.diff("saves"):
		game.notify("Кошмар: страницы журнала слиплись от сырости. Сохранений нет.", 4, 1)
		return false
	if game.campaign.state.night and game.is_instance_valid_hunter_near():
		game.notify("Не сейчас — оно рядом. Руки дрожат, перо не пишет.", 4, 1)
		return false
	if game.save_game(true):
		writes += 1
		game.sound.interact("paper")
		game.notify("%s: запись сделана. Игра сохранена (День %d, %02d:%02d)." % [b.title, game.day, int(game.hour) % 24, int(fmod(game.hour, 1.0) * 60)], 5)
		game.hud.continue_button.show()
		return true
	game.notify("Сейчас записать не получится.", 3)
	return false
