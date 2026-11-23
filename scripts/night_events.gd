extends Node3D
## Особые ночи v1.3 — поверх обычной ночной обороны:
## - «storm»   шторм: посреди ночи обрывается питание, весь свет гаснет, генератор надо запустить вручную;
## - «fog»     густой туман: видимость падает до нескольких метров, глаза охотника видны только вблизи;
## - «ship»    сейнер «Кильдин» сносит на камни: у сигнального фонаря на западном берегу
##             вовремя подавайте сигнал (E), когда судно подходит к очередному камню;
## - «rescuer» ложный «спасатель» стучит в дверь хижины. Подсказки: нет огней катера у причала,
##             голос повторяет слова слово в слово, радио Берега-четыре прямо говорит «никого не посылали».
##             Откроете — за дверью никого… почти.
const KIND_EVENT := {"storm":"storm", "watcher":"fog", "silence":"ship", "echo":"ship", "double":"rescuer", "false_call":"rescuer"}
const SIGNAL_LAMP := Vector3(-17.5, 1.0, -3.0)
const SIGNAL_REACH := 2.3
const SHIP_PATH := [Vector3(-28, 0, 22), Vector3(-29, 0, 10), Vector3(-28.5, 0, -1), Vector3(-27.5, 0, -11), Vector3(-38, 0, -15.5), Vector3(-58, 0, -15.5)]
const ROCKS := [Vector3(-24.6, 0, 7.5), Vector3(-24.2, 0, -2.2), Vector3(-23.8, 0, -10.0)]
const SHIP_SPEED := 1.5
const SIGNAL_WINDOW := 5.0          ## секунд на сигнал, пока судно подходит к камню
const SHIP_START := 5.0
const STORM_OUTAGE_SHARE := .35     ## доля ночи до обрыва питания
const RESCUER_START := 6.0
const RESCUER_SECONDS := 36.0
const RESCUER_DAMAGE := 35.0
const RESCUER_SANITY := 20.0

var game: Node
var rng := RandomNumberGenerator.new()
var event := ""                     ## событие текущей ночи
var night_day := -1
var clock := 0.0
var done := false
var result := ""                    ## saved / lost / outage / restored / shut / opened
var fog := 0.0
# шторм
var outage_done := false
var flash_clock := 6.0
var flash_light: OmniLight3D
# сейнер
var ship: Node3D
var ship_light: OmniLight3D
var ship_lamp: MeshInstance3D
var ship_s := 0.0                   ## пройденный путь, м
var rocks_passed := 0
var rock_nodes: Array = []
var danger := -1                    ## индекс камня, к которому сносит
var danger_time := 0.0
var signalled := false
var signal_flash := 0.0
var lamp: Node3D
var lamp_light: OmniLight3D
var sink_time := 0.0
var path_len := 0.0
# «спасатель»
var rescuer_phase := 0
var rescuer_inside := 0.0           ## сколько секунд события смотритель провёл в хижине
var opened := false

func _ready() -> void:
	rng.randomize()
	for i in SHIP_PATH.size() - 1:
		path_len += SHIP_PATH[i].distance_to(SHIP_PATH[i + 1])

func event_for(day: int, kind: String) -> String:
	if day < 3:
		return ""
	return KIND_EVENT.get(kind, "")

func reset() -> void:
	_clear()
	event = ""
	night_day = -1
	fog = 0.0

func _clear() -> void:
	clock = 0
	done = false
	result = ""
	outage_done = false
	flash_clock = 6.0
	ship_s = 0
	rocks_passed = 0
	danger = -1
	danger_time = 0
	signalled = false
	sink_time = 0
	rescuer_phase = 0
	rescuer_inside = 0
	opened = false
	for n in [ship, lamp, flash_light]:
		if is_instance_valid(n):
			n.queue_free()
	for r in rock_nodes:
		if is_instance_valid(r):
			r.queue_free()
	rock_nodes.clear()
	ship = null
	lamp = null
	flash_light = null

## Принудительно начать событие (для тестов, превью и прогонов баланса).
func force(kind: String) -> void:
	_clear()
	event = kind
	night_day = game.day
	_begin()

func _night() -> bool:
	return game.campaign.enabled and bool(game.campaign.state.night) and not game.first_shift_demo.active()

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.paused or game.finished:
		return
	tick(delta)

func tick(delta: float) -> void:
	fog = move_toward(fog, 1.0 if event == "fog" and _night() else 0.0, delta / 6.0)
	if not _night():
		if not event.is_empty() or is_instance_valid(ship) or is_instance_valid(lamp):
			_clear()
			event = ""
		night_day = -1
		return
	if night_day != game.day:
		_clear()
		night_day = game.day
		event = event_for(game.day, str(game.campaign.entry().night.kind))
		_begin()
	if event.is_empty():
		return
	clock += delta
	match event:
		"storm":
			_tick_storm(delta)
		"fog":
			if clock >= 2.0 and not done:
				done = true
				game.radio.say("fog_warning", true)
				game.notify("С моря идёт густой туман. Держитесь света — в тумане оно подходит вплотную.", 7)
		"ship":
			_tick_ship(delta)
		"rescuer":
			_tick_rescuer(delta)

func _begin() -> void:
	match event:
		"ship":
			_build_ship()
			_build_lamp()
			_build_rocks()
		"storm":
			flash_light = OmniLight3D.new()
			flash_light.name = "StormFlash"
			flash_light.omni_range = 80
			flash_light.light_energy = 0
			flash_light.light_color = Color("c9d8ff")
			flash_light.shadow_enabled = false
			add_child(flash_light)
			flash_light.global_position = Vector3(-10, 30, -5)

# ---------------------------------------------------------------- шторм
func outage_at() -> float:
	return maxf(8.0, float(game.campaign.entry().night.seconds) * STORM_OUTAGE_SHARE)

func _tick_storm(delta: float) -> void:
	flash_clock -= delta
	if is_instance_valid(flash_light):
		flash_light.light_energy = maxf(0, flash_light.light_energy - delta * 22)
	if flash_clock <= 0:
		flash_clock = rng.randf_range(7, 14)
		lightning()
	if not outage_done and clock >= outage_at():
		outage()
	if outage_done and result == "outage" and game.lighthouse_on:
		result = "restored"

func lightning() -> void:
	if is_instance_valid(flash_light):
		flash_light.light_energy = 6.0
	game.camera_shake = maxf(game.camera_shake, .12)
	game.sound.sfx("thump", -6, rng.randf_range(.45, .6))

## Шторм обрывает питание: свет гаснет, ночное задание — перезапустить генератор.
func outage() -> void:
	outage_done = true
	result = "outage"
	lightning()
	game.sound.scare("static_burst", -4, .8)
	var c = game.campaign
	if game.lighthouse_on or not bool(c.state.blackout):
		c.state.blackout = true
		c.state.event_done = false
		game.lighthouse_on = false
		game.beacon.set_powered(false)
	if is_instance_valid(game.dread):
		game.dread.blackout(1.2)
	game.radio.say("storm_outage", true, true)
	game.alert("ШТОРМ ОБОРВАЛ ПИТАНИЕ", "Весь свет погас. Генератор маяка · E — запустить вручную", 7)

# ---------------------------------------------------------------- туман
func fog_strength() -> float:
	return fog

# ---------------------------------------------------------------- сейнер
func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .85
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_ship() -> void:
	ship = Node3D.new()
	ship.name = "LostSeiner"
	add_child(ship)
	var hull := _mat(Color("1d2326"))
	_box(ship, Vector3(1.7, .8, 5.0), Vector3(0, .2, 0), hull)
	_box(ship, Vector3(1.2, .35, 1.3), Vector3(0, .75, 2.4), hull)
	_box(ship, Vector3(1.3, 1.0, 1.6), Vector3(0, 1.1, -.8), _mat(Color("2c3134")))
	_box(ship, Vector3(1.0, .25, .05), Vector3(0, 1.25, 0.02), _mat(Color("ffcf7a"), 1.6))   # окна рубки
	_box(ship, Vector3(.12, 3.2, .12), Vector3(0, 2.0, .9), hull)
	ship_lamp = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = .16
	s.height = .32
	ship_lamp.mesh = s
	ship_lamp.position = Vector3(0, 3.6, .9)
	ship_lamp.material_override = _mat(Color("ffd08a"), 4.0)
	ship.add_child(ship_lamp)
	ship_light = OmniLight3D.new()
	ship_light.light_color = Color("ffc27a")
	ship_light.light_energy = 2.2
	ship_light.omni_range = 9
	ship_light.position = Vector3(0, 2.5, 0)
	ship.add_child(ship_light)
	_place_ship(0)

func _build_lamp() -> void:
	lamp = Node3D.new()
	lamp.name = "SignalLamp"
	add_child(lamp)
	lamp.global_position = _ground(SIGNAL_LAMP)
	_box(lamp, Vector3(.16, 1.5, .16), Vector3(0, .75, 0), _mat(Color("2a2a28")))
	_box(lamp, Vector3(.45, .4, .45), Vector3(0, 1.65, 0), _mat(Color("6a5a3a")))
	_box(lamp, Vector3(.3, .26, .05), Vector3(-.24, 1.65, 0).rotated(Vector3.UP, 0), _mat(Color("ffd9a0"), 2.5))
	lamp_light = OmniLight3D.new()
	lamp_light.light_color = Color("ffd9a0")
	lamp_light.light_energy = .9
	lamp_light.omni_range = 4.5
	lamp_light.position = Vector3(0, 1.8, 0)
	lamp.add_child(lamp_light)

func _build_rocks() -> void:
	for i in ROCKS.size():
		var r := Node3D.new()
		r.name = "ShoalRock%d" % i
		add_child(r)
		r.global_position = ROCKS[i]
		for k in 3:
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = .9 - k * .22
			s.height = (.9 - k * .22) * 1.6
			mi.mesh = s
			mi.position = Vector3(k * .7 - .6, -.15 + k * .1, k * .5 - .4)
			mi.scale = Vector3(1.2, .8, 1)
			mi.material_override = _mat(Color("15191a"))
			r.add_child(mi)
		var foam := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 1.5
		t.outer_radius = 1.8
		foam.mesh = t
		foam.position = Vector3(0, .05, 0)
		var fm := _mat(Color(.8, .88, .9, .35))
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		foam.material_override = fm
		r.add_child(foam)
		var warn := OmniLight3D.new()
		warn.name = "Warn"
		warn.light_color = Color("ff5a3a")
		warn.light_energy = 0
		warn.omni_range = 5
		warn.position = Vector3(0, 1.4, 0)
		r.add_child(warn)
		rock_nodes.append(r)

func _ocean_y() -> float:
	var ocean: Node3D = game.world.get_node_or_null("Ocean")
	return ocean.global_position.y if ocean != null else 0.0

func _ground(p: Vector3) -> Vector3:
	var g: Variant = game.night_raids.ground_at(p)
	return (g - Vector3.UP * .35) if g != null else p

## Точка на пути сейнера: s — пройденные метры. Возвращает [позиция, направление].
func path_point(s: float) -> Array:
	var left := s
	for i in SHIP_PATH.size() - 1:
		var a: Vector3 = SHIP_PATH[i]
		var b: Vector3 = SHIP_PATH[i + 1]
		var l := a.distance_to(b)
		if left <= l or i == SHIP_PATH.size() - 2:
			return [a.lerp(b, clampf(left / l, 0, 1)), (b - a).normalized()]
		left -= l
	return [SHIP_PATH[-1], Vector3.FORWARD]

## Метр пути, на котором сейнер ближе всего к камню i.
func rock_s(i: int) -> float:
	var best := 0.0
	var bd := INF
	var s := 0.0
	while s < path_len:
		var d: float = (path_point(s)[0] as Vector3).distance_to(ROCKS[i])
		if d < bd:
			bd = d
			best = s
		s += .5
	return best

func _place_ship(drift: float) -> void:
	if not is_instance_valid(ship):
		return
	var pd := path_point(ship_s)
	var at: Vector3 = pd[0]
	var dir: Vector3 = pd[1]
	# сносит к камню, если сигнала нет; после сигнала уводит мористее
	var side := Vector3(dir.z, 0, -dir.x)
	if danger >= 0:
		var to_rock: Vector3 = ROCKS[danger] - at
		side = side if side.dot(to_rock) > 0 else -side
		at += side * drift
	var t := Time.get_ticks_msec() / 1000.0
	ship.global_position = Vector3(at.x, _ocean_y() + .1, at.z) + Vector3.UP * (sin(t * 1.3) * .08)
	if dir.length() > .1:
		ship.look_at(ship.global_position - dir, Vector3.UP)
	ship.rotation.z = sin(t * .9) * .05 + sink_time * .25

func near_lamp() -> bool:
	if event != "ship" or not is_instance_valid(lamp) or not game.building_interiors.active.is_empty() or game.lighthouse_interior.active:
		return false
	var p: Vector3 = game.player.global_position
	return Vector2(p.x - SIGNAL_LAMP.x, p.z - SIGNAL_LAMP.z).length() < SIGNAL_REACH

func _tick_ship(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	if is_instance_valid(lamp_light):
		signal_flash = maxf(0, signal_flash - delta * 1.6)
		lamp_light.light_energy = .9 + 6.0 * signal_flash
		lamp_light.omni_range = 4.5 + 10 * signal_flash
	if result == "lost":
		sink_time += delta
		ship.global_position += Vector3.DOWN * delta * .25
		if is_instance_valid(ship_light):
			ship_light.light_energy = maxf(0, ship_light.light_energy - delta)
		if sink_time > 9:
			ship.queue_free()
		return
	if clock < SHIP_START:
		_place_ship(0)
		return
	if clock - delta < SHIP_START:
		game.radio.say("ship_call", true, true)
		game.alert("СЕЙНЕР У КАМНЕЙ", "Сигнальный фонарь на западном берегу · E, когда судно подходит к камню", 7)
	var speed := SHIP_SPEED
	if danger >= 0:
		danger_time += delta
		speed *= .55
		var warn: OmniLight3D = rock_nodes[danger].get_node("Warn")
		warn.light_energy = 1.4 + sin(clock * 9) * 1.0
		ship_lamp.material_override.albedo_color = Color("ff4030") if fmod(clock, .6) < .3 else Color("ffd08a")
		ship_lamp.material_override.emission = ship_lamp.material_override.albedo_color
		if fmod(clock, 1.2) < delta:
			game.sound.sfx("clank", -8, .6, ship.global_position + Vector3.UP * 3)
		if danger_time >= SIGNAL_WINDOW:
			_crash()
			return
	ship_s = minf(path_len, ship_s + speed * delta)
	_place_ship(clampf(danger_time / SIGNAL_WINDOW, 0, 1) * 1.6 if danger >= 0 else 0.0)
	if danger < 0 and rocks_passed < ROCKS.size() and ship_s >= rock_s(rocks_passed) - SHIP_SPEED * SIGNAL_WINDOW * .6:
		danger = rocks_passed
		danger_time = 0
		game.notify("Сейнер сносит на камень! Сигнал с фонаря на берегу · E", 4, 1)
	if ship_s >= path_len - .5 and result.is_empty():
		result = "saved"
		done = true
		game.radio.say("ship_saved", true, true)
		game.notify("«Кильдин» ушёл в открытое море. Огни мигнули вам на прощание.", 6)
		if is_instance_valid(game.achievements):
			game.achievements.note("ship")
		ship.queue_free()

## E у сигнального фонаря.
func signal_ship() -> bool:
	if not near_lamp():
		return false
	signal_flash = 1.0
	game.sound.interact("beacon")
	if result == "lost" or result == "saved":
		game.notify("Море пустое. Сигналить некому.", 3)
		return true
	if danger < 0:
		game.notify("Сейнер идёт ровно. Сигнал нужен, когда его сносит к камню (камень вспыхнет красным).", 4)
		return true
	var warn: OmniLight3D = rock_nodes[danger].get_node("Warn")
	warn.light_energy = 0
	rocks_passed += 1
	danger = -1
	danger_time = 0
	ship_lamp.material_override.albedo_color = Color("ffd08a")
	ship_lamp.material_override.emission = Color("ffd08a")
	game.notify("Сейнер отвернул от камня (%d/%d)." % [rocks_passed, ROCKS.size()], 3)
	return true

func _crash() -> void:
	result = "lost"
	done = true
	danger = -1
	for r in rock_nodes:
		(r.get_node("Warn") as OmniLight3D).light_energy = 0
	game.sound.sfx("hunter_crack", -2, .5, ship.global_position)
	game.sound.cue("splash")
	game.radio.say("ship_lost", true, true)
	game.sanity = maxf(0, game.sanity - 12)
	game.notify("Сейнер сел на камни. Огни гаснут один за другим…", 6, 1)

# ---------------------------------------------------------------- «спасатель»
func rescuer_active() -> bool:
	return event == "rescuer" and rescuer_phase > 0 and not done

func _door() -> Vector3:
	return game.building_interiors.exit_at("cabin")

func _knock() -> void:
	var inside: bool = game.building_interiors.active == "cabin"
	var at: Vector3 = (game.player.global_position + Vector3(0, 1, 1.6)) if inside else _door() + Vector3.UP
	game.sound.sfx("knock", -1, rng.randf_range(.8, .95), at)
	game.camera_shake = maxf(game.camera_shake, .1 if inside else .03)

func _tick_rescuer(delta: float) -> void:
	if done:
		return
	var t := clock - RESCUER_START
	if t < 0:
		return
	if game.building_interiors.active == "cabin":
		rescuer_inside += delta
	if rescuer_phase == 0:
		rescuer_phase = 1
		_knock()
		game.radio.say("rescuer_1", true, true)
		game.notify("Кто-то стучит в дверь хижины и называет себя спасателем." if game.building_interiors.active == "cabin" else "У хижины стучат в дверь. Кто-то зовёт смотрителя.", 6, 1)
	elif rescuer_phase == 1 and t >= 8:
		rescuer_phase = 2
		game.notify("Странно: у причала нет ни огней катера, ни шума мотора.", 5)
	elif rescuer_phase == 2 and t >= 13:
		rescuer_phase = 3
		_knock()
		game.radio.say("rescuer_2", true)
		game.notify("Он повторяет одно и то же — слово в слово, тем же голосом.", 5)
	elif rescuer_phase == 3 and t >= 20:
		rescuer_phase = 4
		game.radio.say("rescue_warning", true, true)
	elif rescuer_phase == 4 and t >= 28:
		rescuer_phase = 5
		game.radio.say("rescuer_3", true)
		game.sound.sfx("creak", -2, .55, _door() + Vector3.UP)
		game.notify("Голос за дверью сорвался — в нём больше нет ничего человеческого.", 5, 1)
	elif rescuer_phase >= 1 and fmod(t, 4.0) < delta and t < RESCUER_SECONDS - 4:
		_knock()
	if t >= RESCUER_SECONDS:
		done = true
		result = "shut"
		game.notify("Стук стих. За дверью — только ветер.", 5)
		if rescuer_inside >= 10 and is_instance_valid(game.achievements):
			game.achievements.unlock("door_shut")

## Смотритель открывает дверь хижины, пока «спасатель» стучит.
func open_door_trap() -> bool:
	if not rescuer_active() or game.building_interiors.active != "cabin":
		return false
	if game.building_interiors.door_at(game.player.position) != "cabin":
		return false
	opened = true
	done = true
	result = "opened"
	game.exit_building()
	game.sound.scare("stinger", 0, .75)
	game.sound.sfx("hunter_grab", 0, .8, game.player.global_position + Vector3.UP)
	if is_instance_valid(game.dread):
		game.dread.blackout(1.0)
	if is_instance_valid(game.scares):
		game.scares.jolt(1.0)
	game.sanity = maxf(0, game.sanity - RESCUER_SANITY)
	game.take_damage(RESCUER_DAMAGE, "rescuer")
	if is_instance_valid(game.hunter) and game.hunter.active:
		game.hunter.noise(game.map_player_position(), 1.0)
	game.notify("За дверью никого не было. Только мокрые следы, ведущие из моря, — и чьё-то дыхание совсем рядом.", 7, 2)
	return true

# ---------------------------------------------------------------- ввод и подсказки
func interact() -> bool:
	if open_door_trap():
		return true
	return signal_ship()

func prompt() -> String:
	if rescuer_active() and game.building_interiors.active == "cabin" and game.building_interiors.door_at(game.player.position) == "cabin":
		return "[E] Открыть дверь «спасателю»   ·   подумайте ещё раз"
	if near_lamp():
		return "[E] Дать сигнал сейнеру" + ("  ·  СЕЙЧАС!" if danger >= 0 else "")
	return ""
