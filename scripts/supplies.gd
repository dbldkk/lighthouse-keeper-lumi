extends Node3D
## Скудные запасы: масло для фонаря берётся из запаса (а не из воздуха), ракетница с парой ракет,
## тайники на острове (каждый день новые) и обмен у хижины: топливо — на масло или на ракету.
## Топливо нужно и генератору, и катеру — каждый обмен это выбор.
const Geo = preload("res://scripts/geometry.gd")
const OIL_START := 90.0          ## запас масла в начале смены (литры «процентов» фонаря)
const OIL_MAX := 300.0
const OIL_PER_FUEL := 80.0
const FLARES_START := 1
const FLARES_MAX := 3
const FLARE_SECONDS := 14.0
const FLARE_RADIUS := 16.0
const REACH := 1.2
const CACHE_SPOTS := [
	Vector3(-4.5,1,10.5), Vector3(10.5,1,-3.5), Vector3(-11.5,1,-6.5), Vector3(14.5,1,-11.5), Vector3(-1.5,1,-31.5),
	Vector3(8.5,1,-27.5), Vector3(-17.5,1,-30.5), Vector3(19.5,1,2.5), Vector3(-7.5,1,-18.5), Vector3(3.5,1,-12.5),
]
const LOOT := {
	"oil": {"title":"Фляга масла", "text":"+50 масла в запас"},
	"flare": {"title":"Сигнальная ракета", "text":"+1 ракета (X — выстрелить)"},
	"food": {"title":"Сухой паёк", "text":"+1 паёк"},
	"wood": {"title":"Сухие доски", "text":"+2 дерева"},
	"scrap": {"title":"Ящик с деталями", "text":"+1 деталь"},
}

var game: Node
var rng := RandomNumberGenerator.new()
var oil_reserve := OIL_START
var flares := FLARES_START
var caches: Array = []          ## {"at":Vector3, "loot":String, "taken":bool}
var caches_day := 0
var cache_props := {}
var stations: Array = []        ## обмен у хижины: {"id","title","at"}
var flare_node: Node3D
var flare_time := 0.0
var flare_light: OmniLight3D

func _init() -> void:
	rng.randomize()

func setup() -> void:
	stations = [
		{"id":"oil_barrel", "title":"Бочка с маслом: 1 топливо → +80 масла в запас", "at": _ground_near(Vector3(8.3, 1, 3.9))},
		{"id":"flare_crate", "title":"Ящик ракетницы: 1 топливо + 1 деталь → ракета", "at": _ground_near(Vector3(8.6, 1, 1.6))},
	]
	for s in stations:
		var root := Node3D.new()
		root.name = "Supply_" + str(s.id)
		add_child(root)
		root.global_position = s.at
		if s.id == "oil_barrel":
			Geo.box(root, "Barrel", Vector3(0, .45, 0), Vector3(.55, .9, .55), Color("3b3326"))
			Geo.box(root, "Band", Vector3(0, .62, 0), Vector3(.58, .06, .58), Color("1d1a15"))
		else:
			Geo.box(root, "Crate", Vector3(0, .25, 0), Vector3(.8, .5, .5), Color("5b2a1f"))
			Geo.box(root, "Stripe", Vector3(0, .51, 0), Vector3(.82, .02, .12), Color("c9b48a"))
		var label := Label3D.new()
		label.text = "◆ масло" if s.id == "oil_barrel" else "◆ ракеты"
		label.font_size = 22
		label.modulate = Color(.92, .84, .62, .7)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 1.25, 0)
		root.add_child(label)

func reset() -> void:
	oil_reserve = OIL_START
	flares = FLARES_START
	caches.clear()
	caches_day = 0
	_clear_props()
	flare_time = 0
	if is_instance_valid(flare_node):
		flare_node.queue_free()

func _clear_props() -> void:
	for k in cache_props.keys():
		if is_instance_valid(cache_props[k]):
			cache_props[k].queue_free()
	cache_props.clear()

func _ground_near(at: Vector3) -> Vector3:
	if not is_instance_valid(game) or not is_instance_valid(game.night_raids):
		return at
	for r in [0.0, 1.0, 2.0, 3.0, 4.5]:
		for i in 8:
			var g: Variant = game.night_raids.ground_at(at + Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8)) * r)
			if g != null:
				return (g as Vector3) - Vector3(0, .35, 0)
	return at

# ---------------------------------------------------------------- масло
## Сколько масла реально долить (из запаса).
func draw_oil(amount: float) -> float:
	var got := minf(amount, oil_reserve)
	oil_reserve -= got
	return got

# ---------------------------------------------------------------- тайники
func roll_caches() -> void:
	caches_day = game.day
	caches.clear()
	_clear_props()
	var spots := CACHE_SPOTS.duplicate()
	spots.shuffle()
	var n := 3 if game.day < 8 else 2      # к концу кампании находок меньше
	var pool := ["oil", "oil", "flare", "food", "wood", "scrap"]
	if game.day >= 8:
		pool = ["oil", "flare", "food", "scrap"]
	for i in n:
		caches.append({"at": _ground_near(spots[i]), "loot": pool[rng.randi_range(0, pool.size() - 1)], "taken": false})

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing:
		return
	if game.campaign.enabled and game.day != caches_day and not game.first_shift_demo.active():
		roll_caches()
	for i in caches.size():
		var c: Dictionary = caches[i]
		if not c.taken and not cache_props.has(i):
			cache_props[i] = _cache_prop(c)
		elif c.taken and cache_props.has(i):
			if is_instance_valid(cache_props[i]):
				cache_props[i].queue_free()
			cache_props.erase(i)
	_tick_flare(delta)

func _cache_prop(c: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Cache"
	add_child(root)
	root.global_position = c.at
	Geo.box(root, "Box", Vector3(0, .18, 0), Vector3(.5, .36, .36), Color("4a3a28"))
	Geo.box(root, "Lid", Vector3(0, .37, 0), Vector3(.54, .04, .4), Color("2c2318"))
	var label := Label3D.new()
	label.text = "▪"
	label.font_size = 26
	label.modulate = Color(.85, .8, .62, .6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, .8, 0)
	root.add_child(label)
	return root

func near() -> Dictionary:
	if not game.lighthouse_interior.active and game.building_interiors.active.is_empty():
		var p: Vector3 = game.player.global_position
		for s in stations:
			if Vector2(p.x - s.at.x, p.z - s.at.z).length() < REACH:
				return {"kind":"station", "id": s.id, "title": s.title}
		for i in caches.size():
			var c: Dictionary = caches[i]
			if not c.taken and Vector2(p.x - c.at.x, p.z - c.at.z).length() < REACH:
				return {"kind":"cache", "index": i}
	return {}

func interact() -> bool:
	var n := near()
	if n.is_empty():
		return false
	if n.kind == "cache":
		take_cache(int(n.index))
	else:
		trade(str(n.id))
	return true

func take_cache(i: int) -> void:
	var c: Dictionary = caches[i]
	if c.taken:
		return
	c.taken = true
	match str(c.loot):
		"oil": oil_reserve = minf(OIL_MAX, oil_reserve + 50)
		"flare": flares = mini(FLARES_MAX, flares + 1)
		"food": game.campaign.resources({"food": 1})
		"wood": game.inventory.wood += 2
		"scrap": game.expedition.state.scrap += 1
	game.sound.interact("wood")
	game.notify("Тайник: %s — %s." % [LOOT[c.loot].title, LOOT[c.loot].text], 5)
	if is_instance_valid(game.hunter):
		game.hunter.noise(c.at, .25)

func trade(id: String) -> bool:
	match id:
		"oil_barrel":
			if int(game.inventory.fuel) < 1:
				game.notify("Нужна канистра топлива. Топливо нужно и маяку, и катеру — решайте.", 5)
				return false
			if oil_reserve >= OIL_MAX - 1:
				game.notify("Запас масла полон.", 3)
				return false
			game.inventory.fuel -= 1
			oil_reserve = minf(OIL_MAX, oil_reserve + OIL_PER_FUEL)
			game.sound.interact("metal")
			game.notify("Топливо перелито в масляный запас: %d. Канистр осталось: %d." % [roundi(oil_reserve), game.inventory.fuel], 5)
			return true
		"flare_crate":
			if flares >= FLARES_MAX:
				game.notify("Ракетница полна (%d)." % flares, 3)
				return false
			if int(game.inventory.fuel) < 1 or int(game.expedition.state.scrap) < 1:
				game.notify("Для ракеты нужны 1 топливо и 1 деталь.", 4)
				return false
			game.inventory.fuel -= 1
			game.expedition.state.scrap -= 1
			flares += 1
			game.sound.interact("metal")
			game.notify("Снаряжена ракета. Ракет: %d (X — выстрелить)." % flares, 5)
			return true
	return false

# ---------------------------------------------------------------- ракетница
func fire_flare() -> bool:
	if flares <= 0:
		game.notify("Ракет нет. Тайники на острове или ящик у хижины.", 3)
		return false
	if not game.lighthouse_interior.active and not game.building_interiors.active.is_empty():
		game.notify("В помещении стрелять нельзя.", 3)
		return false
	flares -= 1
	var at: Vector3 = game.player.global_position
	if is_instance_valid(flare_node):
		flare_node.queue_free()
	flare_node = Node3D.new()
	flare_node.name = "Flare"
	add_child(flare_node)
	flare_node.global_position = at + Vector3(0, 1.5, 0)
	flare_light = OmniLight3D.new()
	flare_light.light_color = Color("ff5a3c")
	flare_light.light_energy = 6.0
	flare_light.omni_range = FLARE_RADIUS
	flare_node.add_child(flare_light)
	var core := Geo.sphere(flare_node, "Core", Vector3.ZERO, Vector3(.25, .25, .25), Color("ffb08a"))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, .55, .4)
	core.material_override = mat
	flare_time = FLARE_SECONDS
	game.sound.sfx("zap", -2, .55, at + Vector3.UP * 3)
	game.camera_shake = maxf(game.camera_shake, .2)
	# отгоняет охотника и выжигает тени рядом
	if is_instance_valid(game.hunter):
		game.hunter.repel(at, FLARE_RADIUS + 4, 18.0)
	for e in game.enemies:
		if is_instance_valid(e) and e.global_position.distance_to(at) < FLARE_RADIUS * .7 and e.has_method("burn"):
			e.burn(1000)
	game.sanity = minf(100, game.sanity + 4)
	game.notify("Ракета вспыхнула красным. Ракет осталось: %d." % flares, 4)
	return true

func flare_active() -> bool:
	return flare_time > 0

func _tick_flare(delta: float) -> void:
	if flare_time <= 0 or not is_instance_valid(flare_node):
		return
	flare_time -= delta
	flare_node.global_position.y = minf(flare_node.global_position.y + delta * 2.5, game.player.global_position.y + 9)
	flare_light.light_energy = 6.0 * clampf(flare_time / 3.0, 0, 1) * (0.85 + randf() * .3)
	# пока горит — держит охотника подальше
	if is_instance_valid(game.hunter) and game.hunter.active:
		var fat := flare_node.global_position
		game.hunter.repel(Vector3(fat.x, game.player.global_position.y, fat.z), FLARE_RADIUS * .8, 3.0)
	if flare_time <= 0:
		flare_node.queue_free()

# ---------------------------------------------------------------- сохранение
func save_data() -> Dictionary:
	var list: Array = []
	for c in caches:
		list.append({"at":[c.at.x, c.at.y, c.at.z], "loot":c.loot, "taken":c.taken})
	return {"oil_reserve": oil_reserve, "flares": flares, "caches_day": caches_day, "caches": list}

func restore(data: Variant) -> void:
	reset()
	if not data is Dictionary:
		return
	oil_reserve = clampf(float(data.get("oil_reserve", OIL_START)), 0, OIL_MAX)
	flares = clampi(int(data.get("flares", FLARES_START)), 0, FLARES_MAX)
	caches_day = int(data.get("caches_day", 0))
	for c in data.get("caches", []):
		var a: Array = c.get("at", [0, 0, 0])
		caches.append({"at": Vector3(a[0], a[1], a[2]), "loot": str(c.get("loot", "oil")), "taken": bool(c.get("taken", false))})
