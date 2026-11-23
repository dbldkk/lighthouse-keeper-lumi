extends Node3D
## Охотник: одно большое существо, которое ночью бродит по острову.
## Слышит шум (бег, провалы ремонта, удары) и видит свет фонаря. Состояния:
## patrol → investigate → chase → search, flee — когда его отгоняет свет маяка, костёр или ракета.
## От него прячутся: шкаф в хижине, ниша под лестницей маяка, брезент на лодке.
## В укрытии рядом с охотником нужно задержать дыхание (пробел) — запас ограничен и стоит рассудка.
const HUNTER_VISUAL = preload("res://scripts/hunter_visual.gd")
const HUNTER_PRESENCE = preload("res://scripts/hunter_presence.gd")
const Geo = preload("res://scripts/geometry.gd")
const BI = preload("res://scripts/building_interiors.gd")
const LI = preload("res://scripts/lighthouse_interior.gd")

const PATROL_SPEED := 1.9
const INVESTIGATE_SPEED := 3.1
const CHASE_SPEED := 4.9           ## медленнее бега смотрителя (6.3), быстрее шага (4.2)
const CATCH_DIST := 1.25
const DAMAGE := 45.0
const SANITY_HIT := 18.0
const SIGHT_LANTERN := 15.0        ## фонарь видно издалека
const SIGHT_DARK := 6.0
const HEAR_RUN := 19.0
const HEAR_WALK := 4.5
const LOSE_DIST := 24.0
const SEARCH_SECONDS := 9.0
const BREATH_MAX := 6.0
const BREATH_SANITY := 1.6         ## рассудка в секунду, пока дыхание задержано
const FOUND_DIST := 2.1

var game: Node
var enabled := true
var active := false
var state := "idle"                ## idle, patrol, investigate, chase, search, flee, room
var body: CharacterBody3D
var visual: Node3D                 ## модель + AnimationTree + звуки анимаций (hunter_visual.gd)
var presence: Node3D               ## отблеск глаз, свет фонаря на нём, отражение в воде (hunter_presence.gd)
var sniff_time := 0.0              ## пауза «принюхаться» в поиске
var target := Vector3.ZERO
var last_known := Vector3.ZERO
var state_time := 0.0
var step_clock := 0.0
var growl_clock := 6.0
var stuck_clock := 0.0
var stuck_from := Vector3.ZERO
var ground_clock := 0.0
var rng := RandomNumberGenerator.new()
var catches := 0
var nights_hunted := 0
var aggression := 1.0              ## растёт с каждой ночью (см. escalation)
## Комната, куда охотник вошёл за смотрителем ("" — снаружи).
var space := ""
var room_clock := 0.0
var door_clock := 0.0
## Укрытия
var spots: Array = []              ## {"id","title","at":Vector3,"room":String}
var hidden_in := ""
var hide_return := Vector3.ZERO
var breath := BREATH_MAX
var holding := false
var gasp_cooldown := 0.0
var prompt: Label
var breath_bar: ProgressBar
var announced := false
var repel_time := 0.0

func _init() -> void:
	rng.randomize()

func _ready() -> void:
	body = CharacterBody3D.new()
	body.name = "HunterBody"
	body.collision_layer = 0
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .42
	capsule.height = 2.3
	shape.shape = capsule
	shape.position.y = 1.15
	body.add_child(shape)
	visual = HUNTER_VISUAL.new()
	visual.name = "Visual"
	visual.scale = Vector3.ONE * 1.08
	body.add_child(visual)
	visual.build(self)
	# отблеск глаз: свет едет вместе с головой
	var glow := OmniLight3D.new()
	glow.name = "EyeGlow"
	glow.light_color = Color("ffcf8a")
	glow.light_energy = .9
	glow.omni_range = 2.4
	if visual.head_attach != null:
		visual.head_attach.add_child(glow)
		glow.position = Vector3(0, .05, .25)
	else:
		glow.position = Vector3(0, 2.3, .5)
		body.add_child(glow)
	# холодный контур — чтобы силуэт читался в темноте (честность)
	var rim := OmniLight3D.new()
	rim.name = "Rim"
	rim.position = Vector3(-.6, 1.8, -.8)
	rim.light_color = Color("7f9fb8")
	rim.light_energy = 1.6
	rim.omni_range = 3.6
	body.add_child(rim)
	add_child(body)
	presence = HUNTER_PRESENCE.new()
	add_child(presence)
	presence.build(self, visual)
	body.hide()

func setup() -> void:
	_build_spots()
	_build_hud()

# ---------------------------------------------------------------- укрытия
func _build_spots() -> void:
	spots.clear()
	var cabin: Vector3 = BI.ROOMS.cabin.origin
	_spot("wardrobe", "Шкаф в хижине", cabin + Vector3(.7, .04, -1.95), "cabin")
	_spot("stairs", "Ниша под лестницей маяка", LI.ORIGIN + Vector3(-1.05, 0, .95), "lighthouse")
	var boat: Node3D = game.world.find_child("FishingBoat", true, false)
	var boat_at: Vector3 = boat.global_position if is_instance_valid(boat) else Vector3(21, 1, 6)
	var tarp_spot: Variant = _tarp_point(boat_at)
	_spot("tarp", "Брезент у лодки", tarp_spot if tarp_spot != null else boat_at, "")
	for s in spots:
		_spot_visual(s)

const SPOT_REACH_OUTDOOR := 1.5
const STATION_CLEARANCE := 4.8     ## укрытие не ближе: радиус станции (2.5) + радиус укрытия (1.5) + запас

## Брезент: на берегу у лодки, но так, чтобы его зона E не пересекалась с рыбалкой и другими станциями.
func _tarp_point(boat_at: Vector3) -> Variant:
	for r in [3.0, 4.0, 5.0, 6.0, 7.0, 8.5, 10.0]:
		for i in 16:
			var p: Vector3 = boat_at + Vector3(cos(i * TAU / 16), 0, sin(i * TAU / 16)) * r
			var g: Variant = game.night_raids.ground_at(p)
			if g == null:
				continue
			var at: Vector3 = (g as Vector3) - Vector3(0, .35, 0)
			if station_clear(at):
				return at
	return _shore_near(boat_at)

func station_clear(at: Vector3) -> bool:
	for st in game.stations:
		if not is_instance_valid(st):
			continue
		if Vector2(at.x - st.position.x, at.z - st.position.z).length() < STATION_CLEARANCE:
			return false
	return true

func _shore_near(at: Vector3) -> Variant:
	for r in [0.0, 1.5, 2.5, 3.5]:
		for i in 8:
			var p: Vector3 = at + Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8)) * r
			var g: Variant = game.night_raids.ground_at(p)
			if g != null:
				return (g as Vector3) - Vector3(0, .35, 0)
	return null

func _spot(id: String, title: String, at: Vector3, room: String) -> void:
	spots.append({"id": id, "title": title, "at": at, "room": room})

func _spot_visual(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Hide_" + str(s.id)
	add_child(root)
	root.global_position = s.at
	match str(s.id):
		"wardrobe":
			Geo.box(root, "Wardrobe", Vector3(0, .95, 0), Vector3(.62, 1.9, .55), Color("2a1d15"))
			Geo.box(root, "Gap", Vector3(0, .95, .28), Vector3(.02, 1.7, .02), Color("0a0705"))
		"stairs":
			Geo.box(root, "Crate", Vector3(.2, .3, 0), Vector3(.6, .6, .5), Color("3a2c1f"))
			Geo.box(root, "Cloth", Vector3(-.2, .45, .1), Vector3(.7, .9, .08), Color("1d2422"))
		"tarp":
			Geo.box(root, "Tarp", Vector3(0, .35, 0), Vector3(1.5, .7, 1.0), Color("27322a"))
			Geo.box(root, "Fold", Vector3(.1, .72, 0), Vector3(1.3, .08, .9), Color("1f2922"))
	var label := Label3D.new()
	label.text = "◇ укрытие"
	label.font_size = 26
	label.modulate = Color(.75, .82, .8, .55)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.15 if s.id == "wardrobe" else 1.3, 0)
	label.no_depth_test = false
	root.add_child(label)

func spot_near(at: Vector3) -> Dictionary:
	for s in spots:
		var reach := 1.5 if str(s.room).is_empty() else 1.0
		if Vector2(at.x - s.at.x, at.z - s.at.z).length() < reach and absf(at.y - s.at.y) < 1.6:
			return s
	return {}

func hiding() -> bool:
	return not hidden_in.is_empty()

## E рядом с укрытием: спрятаться / выйти.
func interact() -> bool:
	if hiding():
		leave_hiding()
		return true
	var s := spot_near(game.player.global_position)
	if s.is_empty():
		return false
	# если ближе станция (рыбалка, верстак…) — E достаётся ей
	if str(s.room).is_empty() and is_instance_valid(game.nearest_station) and game.building_interiors.active.is_empty():
		var p: Vector3 = game.player.global_position
		var spot_d := Vector2(p.x - s.at.x, p.z - s.at.z).length()
		if game.station_distance(game.nearest_station) < spot_d:
			return false
	hide_in(str(s.id))
	return true

func hide_in(id: String) -> void:
	for s in spots:
		if s.id == id:
			hidden_in = id
			hide_return = game.player.global_position
			game.player.enabled = false
			game.player.velocity = Vector3.ZERO
			game.player.visible = false
			if game.player.lantern_on:
				game.toggle_lantern()
			breath = BREATH_MAX
			holding = false
			game.sound.interact("wood")
			game.notify("Вы спрятались: %s. Пробел — задержать дыхание, когда он рядом. E — выйти." % s.title, 6, 1)
			return

func leave_hiding() -> void:
	if not hiding():
		return
	hidden_in = ""
	holding = false
	game.player.visible = true
	game.player.enabled = not game.paused and not game.finished
	game.sound.interact("wood")

func _hidden_spot() -> Dictionary:
	for s in spots:
		if s.id == hidden_in:
			return s
	return {}

# ---------------------------------------------------------------- жизненный цикл
func reset() -> void:
	leave_hiding()
	_despawn()
	catches = 0
	nights_hunted = 0
	announced = false

func should_hunt() -> bool:
	if not enabled or not is_instance_valid(game) or not game.playing or game.finished:
		return false
	if game.first_shift_demo.active() or game.expedition.sailing or not game.campaign.enabled:
		return false
	return bool(game.campaign.state.night) and game.day >= 2

func _spawn() -> void:
	var far := _far_point(28.0)
	body.global_position = far
	body.show()
	active = true
	space = ""
	state = "patrol"
	state_time = 0
	target = _patrol_point()
	nights_hunted += 1
	if is_instance_valid(game.escalation):
		aggression = game.escalation.hunter_aggression()
	game.sound.sfx("groan", -6, .62, far + Vector3.UP * 2)
	if not announced:
		announced = true
		game.notify("Где-то на острове что-то большое ломится сквозь кусты. Оно идёт на шум и на свет. Не бегайте без нужды; укрытия — E.", 9, 1)

func _despawn() -> void:
	if presence != null:
		presence.clear()
	active = false
	state = "idle"
	space = ""
	if is_instance_valid(body):
		body.hide()
		body.global_position = Vector3(0, -50, 0)

func _far_point(min_dist: float) -> Vector3:
	var p: Vector3 = game.player.global_position if space.is_empty() else game.map_player_position()
	var best := Vector3(-20, 1, 20)
	var best_d := -1.0
	for point in game.night_raids.EDGE_POINTS:
		var d := Vector2(point.x - p.x, point.z - p.z).length()
		if d >= min_dist and rng.randf() < .6:
			return point
		if d > best_d:
			best_d = d
			best = point
	return best

func _patrol_point() -> Vector3:
	var pts: Array = []
	for st in game.stations:
		if is_instance_valid(st) and st.global_position.y < 6 and absf(st.global_position.x) < 150:
			pts.append(st.global_position)
	pts.append_array(game.night_raids.EDGE_POINTS)
	# чаще бродит там, где смотритель
	if rng.randf() < .45 * aggression:
		var p: Vector3 = game.map_player_position()
		var near: Variant = game.night_raids.ground_at(p + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9)))
		if near != null:
			return near
	return pts[rng.randi_range(0, pts.size() - 1)]

# ---------------------------------------------------------------- слух и свет
## Шум в точке: громкость 0..1 (1 ≈ слышно через пол-острова).
func noise(at: Vector3, loudness: float) -> void:
	if not active or state in ["flee", "chase"] or not space.is_empty():
		return
	var d := Vector2(at.x - body.global_position.x, at.z - body.global_position.z).length()
	if d <= loudness * 34.0 * aggression:
		last_known = at
		_set_state("investigate")
		target = at
		growl_clock = minf(growl_clock, .6)

## Отпугнуть: ракета, костёр, луч маяка.
func repel(at: Vector3, radius: float, seconds := 14.0) -> bool:
	if not active:
		return false
	if body.global_position.distance_to(at) > radius:
		return false
	repel_time = seconds
	_set_state("flee")
	target = _far_point(22.0)
	game.sound.sfx("groan", -3, .5, body.global_position + Vector3.UP * 2)
	return true

func _set_state(next: String) -> void:
	if state == next:
		return
	state = next
	state_time = 0
	sniff_time = 0.0
	if next not in ["chase", "search"]:
		door_clock = 0

## Клип модели следует за состоянием: у двери — door_wait, в поиске на месте — search, бросок — grab.
func _tick_visual(delta: float) -> void:
	if visual == null:
		return
	visual.door_wait = door_clock > 0 and space.is_empty()
	visual.sniffing = state == "search" or (not space.is_empty() and hiding())
	visual.tick(delta)
	if presence != null:
		presence.tick(delta)

func _in_light(at: Vector3) -> bool:
	if game.lighthouse_on and Vector2(at.x + 9, at.z + 7).length() < 8.5:
		return true
	if int(game.expedition.state.fire_day) > 0 and int(game.expedition.state.fire_day) >= int(game.expedition.state.last_dawn) and at.distance_to(Vector3(-16, 1, -28)) < 6.5:
		return true
	# укреплённая хижина держит его только первые ночи
	if game.barricade_built and Vector2(at.x - 5, at.z - 1).length() < 6.0 and aggression < 1.5:
		return true
	return false

func _player_outside() -> bool:
	return not game.lighthouse_interior.active and game.building_interiors.active.is_empty()

func _can_see_player() -> bool:
	if hiding() or not _player_outside():
		return false
	var p: Vector3 = game.player.global_position
	var d := Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length()
	var sight := (SIGHT_LANTERN if game.player.lantern_on else SIGHT_DARK) * lerpf(1.0, 1.3, clampf(aggression - 1.0, 0, 1))
	if game.island_events.current == "fog" or is_instance_valid(game.escalation) and game.escalation.fog:
		sight *= .7
	return d <= sight

func _player_noise() -> float:
	if hiding() or not _player_outside():
		return 0.0
	var v: Vector3 = game.player.velocity
	if Vector2(v.x, v.z).length() < .3:
		return 0.0
	return HEAR_RUN if game.player.is_running else HEAR_WALK

# ---------------------------------------------------------------- кадр
var preview_freeze := false

func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	if preview_freeze:
		if presence != null and active:
			presence.tick(delta)
		return
	_update_hud()
	if game.paused:
		return
	if not should_hunt():
		if active:
			_despawn()
		# дыхание работает и без охотника — для учебной сцены в первый день
		gasp_cooldown = maxf(0, gasp_cooldown - delta)
		_tick_breath(delta)
		return
	if not active:
		_spawn()
	state_time += delta
	repel_time = maxf(0, repel_time - delta)
	gasp_cooldown = maxf(0, gasp_cooldown - delta)
	_tick_breath(delta)
	if space.is_empty():
		_tick_outside(delta)
	else:
		_tick_room(delta)
	_tick_audio(delta)
	_tick_visual(delta)

func _tick_outside(delta: float) -> void:
	var here := body.global_position
	var p: Vector3 = game.player.global_position
	var d := Vector2(p.x - here.x, p.z - here.z).length()
	if _player_outside():
		door_clock = 0
	# Свет отгоняет
	if state != "flee" and _in_light(here):
		repel_time = 6.0
		_set_state("flee")
		target = _far_point(18.0)
	# Луч фонаря в упор — вздрагивает и замирает (но теперь знает, где вы).
	if state != "flee" and game.lantern_beam.focusing and game.lantern_beam.in_cone(here + Vector3.UP):
		last_known = p
		if state_time > .8 and rng.randf() < delta * 1.5:
			game.sound.sfx("groan", -4, .55, here + Vector3.UP * 2)
	match state:
		"patrol":
			if _can_see_player():
				_set_state("chase")
			elif _player_noise() > 0 and d < _player_noise() * aggression:
				last_known = p
				target = p
				_set_state("investigate")
			elif _flat(here, target) < 1.5 or state_time > 22:
				target = _patrol_point()
				state_time = 0
			_move(target, PATROL_SPEED * aggression, delta)
		"investigate":
			if _can_see_player():
				_set_state("chase")
			elif _flat(here, target) < 1.4 or state_time > 14:
				_set_state("search")
				last_known = target
			_move(target, INVESTIGATE_SPEED * aggression, delta)
		"chase":
			if _can_see_player() or (d < 9 and not hiding() and _player_outside()):
				last_known = p
				target = p
			elif not _player_outside():
				target = game.map_player_position()
			else:
				_set_state("search")
			if d > LOSE_DIST * aggression:
				_set_state("search")
			if _player_outside() and not hiding() and d < CATCH_DIST:
				_catch()
				return
			_move(target, CHASE_SPEED * minf(aggression, 1.25), delta)
			if not _player_outside():
				_try_follow_inside(delta)
		"search":
			if _can_see_player():
				_set_state("chase")
			elif state_time > SEARCH_SECONDS:
				_set_state("patrol")
				target = _patrol_point()
			elif sniff_time > 0:
				# замер и принюхивается (клип search), потом идёт дальше
				sniff_time -= delta
				body.velocity = Vector3.ZERO
				_sniff_hiding()
			else:
				if _flat(here, target) < 1.2:
					sniff_time = 2.4
					target = last_known + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
					var g: Variant = game.night_raids.ground_at(target)
					if g != null:
						target = g
				_move(target, INVESTIGATE_SPEED * .8, delta)
				_sniff_hiding()
				if not _player_outside():
					_try_follow_inside(delta)
		"flee":
			_move(target, CHASE_SPEED, delta)
			if repel_time <= 0 and not _in_light(body.global_position):
				_set_state("patrol")
				target = _patrol_point()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _move(to: Vector3, speed: float, delta: float) -> void:
	var here := body.global_position
	var dir := Vector3(to.x - here.x, 0, to.z - here.z)
	if dir.length() < .2:
		body.velocity = Vector3.ZERO
		return
	dir = dir.normalized()
	# не заходит в воду: пробует обойти
	var ahead: Variant = game.night_raids.ground_at(here + dir * 1.2)
	if ahead == null:
		for turn in [.7, -.7, 1.4, -1.4, 2.1, -2.1]:
			var alt := dir.rotated(Vector3.UP, turn)
			if game.night_raids.ground_at(here + alt * 1.2) != null:
				dir = alt
				break
	body.velocity = dir * speed
	body.move_and_slide()
	ground_clock -= delta
	if ground_clock <= 0:
		ground_clock = .2
		var g: Variant = game.night_raids.ground_at(body.global_position)
		if g != null:
			body.global_position.y = (g as Vector3).y - .35
	body.look_at(body.global_position - dir, Vector3.UP)
	stuck_clock += delta
	if stuck_clock > 1.5:
		if body.global_position.distance_to(stuck_from) < speed * .35 and state != "chase":
			target = _patrol_point()
		stuck_clock = 0
		stuck_from = body.global_position

func _catch() -> void:
	catches += 1
	if visual != null:
		visual.play_grab()
	game.sound.scare("stinger", 0, .82)
	game.sound.sfx("groan", 0, .7, game.player.global_position + Vector3.UP)
	if is_instance_valid(game.scares):
		game.scares.jolt(1.0)
	if is_instance_valid(game.dread):
		game.dread.glitch_pulse(1.0)
	game.sanity = maxf(0, game.sanity - SANITY_HIT)
	game.take_damage(DAMAGE, "hunter")
	if game.health > 0:
		game.notify("Оно схватило вас и отшвырнуло в темноту. Ещё раз — и вы не встанете. Прячьтесь или бегите к свету.", 7, 2)
	# уходит, чтобы игрок успел опомниться
	repel_time = 12.0
	_set_state("flee")
	target = _far_point(24.0)
	space = ""

# ---------------------------------------------------------------- внутри помещений
func _room_of_player() -> String:
	if game.lighthouse_interior.active:
		return "lighthouse"
	return game.building_interiors.active

func _try_follow_inside(delta: float) -> void:
	var room := _room_of_player()
	if room.is_empty() or room == "ship" or room == "radio":
		return
	if room == "lighthouse" and game.lighthouse_on:
		return
	var door: Vector3 = LI.OUTSIDE_DOOR if room == "lighthouse" else game.building_interiors.exit_at(room)
	if _flat(body.global_position, door) > 3.0:
		target = door
		door_clock = 0
		return
	door_clock += delta
	if door_clock == delta:
		game.sound.sfx("knock", -2, .7, game.player.global_position + Vector3(0, 1, 2))
		game.notify("Дверь скрипнула. Оно входит. Спрячьтесь!", 4, 2)
	if door_clock > 2.2:
		door_clock = 0
		space = room
		room_clock = 0
		var inside: Vector3 = (LI.ORIGIN + LI.INSIDE_DOOR) if room == "lighthouse" else (BI.ROOMS[room].origin + BI.ROOMS[room].spawn)
		body.global_position = inside
		target = _room_point()
		game.sound.sfx("creak", -2, .7, inside + Vector3.UP)
		if is_instance_valid(game.dread):
			game.dread.blackout(1.4)

func _room_point() -> Vector3:
	if space == "lighthouse":
		var a := rng.randf() * TAU
		return LI.ORIGIN + Vector3(cos(a) * 1.3, 0, sin(a) * 1.3)
	var info: Dictionary = BI.ROOMS[space]
	return info.origin + Vector3(rng.randf_range(-.4, .4) * info.size.x, .04, rng.randf_range(-.4, .4) * info.size.y)

func _tick_room(delta: float) -> void:
	room_clock += delta
	var here := body.global_position
	var p: Vector3 = game.player.global_position
	if _room_of_player() != space:
		# смотритель вышел — охотник следует обратно
		_leave_room()
		return
	if not hiding():
		target = p
		if _flat(here, p) < CATCH_DIST:
			_catch()
			return
		_room_step(CHASE_SPEED * .55, delta)
	else:
		if _flat(here, target) < .3:
			target = _room_point()
			if rng.randf() < .45:
				target = (_hidden_spot().at as Vector3) + Vector3(rng.randf_range(-.6, .6), 0, .8)
		_room_step(1.3, delta)
		_sniff_hiding()
	if room_clock > 13.0 and hiding():
		game.notify("Шаги удаляются. Дверь хлопнула.", 4)
		_leave_room()

func _room_step(speed: float, delta: float) -> void:
	var here := body.global_position
	var dir := Vector3(target.x - here.x, 0, target.z - here.z)
	if dir.length() > .05:
		body.global_position += dir.normalized() * minf(dir.length(), speed * delta)
		body.look_at(body.global_position - dir.normalized(), Vector3.UP)

func _leave_room() -> void:
	var door: Vector3 = LI.OUTSIDE_DOOR if space == "lighthouse" else game.building_interiors.exit_at(space)
	space = ""
	body.global_position = door + Vector3(1.5, 0, 1.5)
	_set_state("search")
	last_known = door
	target = door

# ---------------------------------------------------------------- дыхание
func _tick_breath(delta: float) -> void:
	if not hiding():
		breath = minf(BREATH_MAX, breath + delta)
		return
	holding = Input.is_physical_key_pressed(breath_key) or holding_forced
	if holding and breath > 0:
		breath = maxf(0, breath - delta)
		game.sanity = maxf(0, game.sanity - BREATH_SANITY * delta)
		if breath <= 0 and gasp_cooldown <= 0:
			_gasp()
	else:
		breath = minf(BREATH_MAX, breath + delta * .45)

var holding_forced := false
var breath_key := KEY_SPACE          ## переназначается в настройках

func _gasp() -> void:
	gasp_cooldown = 3.0
	holding = false
	game.sound.sfx("cough", -4, .9, game.player.global_position + Vector3.UP)
	game.notify("Вы судорожно вдохнули.", 3, 1)
	var s := _hidden_spot()
	if not s.is_empty() and active and _same_space(s) and _flat(body.global_position, s.at) < 6.0:
		_found(s)

func _same_space(s: Dictionary) -> bool:
	return str(s.room) == space

func _sniff_hiding() -> void:
	if not hiding():
		return
	var s := _hidden_spot()
	if s.is_empty() or not _same_space(s):
		return
	if _flat(body.global_position, s.at) < FOUND_DIST and not (holding and breath > 0):
		_found(s)

func _found(s: Dictionary) -> void:
	leave_hiding()
	game.notify("Оно услышало дыхание и вытащило вас из укрытия!", 5, 2)
	_catch()

# ---------------------------------------------------------------- звук
func _tick_audio(delta: float) -> void:
	if not active:
		return
	var here := body.global_position
	var listener: Vector3 = game.player.global_position
	var d := here.distance_to(listener)
	step_clock -= delta
	var moving := body.velocity.length() > .4 or not space.is_empty()
	if moving and step_clock <= 0 and d < 30 and (visual == null or not visual.available()):
		step_clock = .34 if state == "chase" else .62
		game.sound.phantom_step(here, "wood" if not space.is_empty() else "grass")
	growl_clock -= delta
	if growl_clock <= 0 and d < 34:
		growl_clock = rng.randf_range(5.0, 9.0) if state == "chase" else rng.randf_range(9.0, 16.0)
		game.sound.sfx("groan", -5 if state == "chase" else -11, rng.randf_range(.55, .7), here + Vector3.UP * 2)
	# близость давит: сердце и страх
	if is_instance_valid(game.scares):
		var near := clampf(1.0 - d / 16.0, 0, 1)
		if state == "chase":
			near = maxf(near, .55)
		game.scares.fear = maxf(float(game.scares.fear), near * .8)
	if hiding() and d < 5.5 and rng.randf() < delta * .4:
		game.sound.scare("breath", -8, .72, here + Vector3.UP * 2)

# ---------------------------------------------------------------- подсказка
func _build_hud() -> void:
	prompt = Label.new()
	prompt.name = "HidePrompt"
	prompt.add_theme_font_size_override("font_size", 17)
	prompt.add_theme_color_override("font_color", Color("d9e2dc"))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.anchor_left = .3
	prompt.anchor_right = .7
	prompt.anchor_top = .62
	prompt.anchor_bottom = .62
	game.hud.root.add_child(prompt)
	breath_bar = ProgressBar.new()
	breath_bar.name = "BreathBar"
	breath_bar.max_value = BREATH_MAX
	breath_bar.show_percentage = false
	breath_bar.anchor_left = .42
	breath_bar.anchor_right = .58
	breath_bar.anchor_top = .665
	breath_bar.anchor_bottom = .665
	breath_bar.offset_bottom = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("9fc3c9")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, .55)
	breath_bar.add_theme_stylebox_override("fill", fill)
	breath_bar.add_theme_stylebox_override("background", bg)
	game.hud.root.add_child(breath_bar)
	prompt.hide()
	breath_bar.hide()

func _update_hud() -> void:
	if prompt == null:
		return
	if not game.playing or game.finished or game.paused:
		prompt.hide()
		breath_bar.hide()
		return
	if hiding():
		var near := active and _same_space(_hidden_spot()) and _flat(body.global_position, _hidden_spot().at) < 7.0
		prompt.text = ("ОНО РЯДОМ · держите ПРОБЕЛ — не дышать" if near else "Вы в укрытии · E — выйти") if breath > 0 else "Нечем дышать…"
		prompt.add_theme_color_override("font_color", Color("ffb1a1") if near else Color("d9e2dc"))
		prompt.show()
		breath_bar.value = breath
		breath_bar.show()
		return
	breath_bar.hide()
	var s := spot_near(game.player.global_position)
	if not s.is_empty():
		prompt.text = "[E] Спрятаться · " + str(s.title)
		prompt.add_theme_color_override("font_color", Color("d9e2dc"))
		prompt.show()
	else:
		prompt.hide()
