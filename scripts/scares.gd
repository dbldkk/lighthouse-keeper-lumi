extends Node
## Режиссёр ужаса: напряжение (сердцебиение, виньетка, глухой звук, темнота)
## и редкие «пугалки» по ритму «тишина → внезапно». Все паузы и шансы — в balance.gd.
##
## Пугалки: силуэт в луче фонаря, фигура в окне хижины, всплеск помех в эфире,
## мерцание и смерть фонаря, шаги за спиной, выпад тени при низком рассудке,
## хлопок двери и дыхание в темноте. Первые случаи на 2-й и 3-й ночь — сценарные.
const BAL = preload("res://scripts/balance.gd")
const Geo = preload("res://scripts/geometry.gd")

var game: Node
var rng := RandomNumberGenerator.new()
var tension := 0.0
var fear := 0.0                 ## вспышка испуга для шейдера (0–1)
var quiet := 0.0                ## сколько секунд не было пугалок
var cooldowns := {}             ## тип → секунды до следующего раза
var history: Array[String] = []
var hush := 0.0                 ## затишье перед пугалкой
var pending := ""
var scripted := {}              ## какие сценарные моменты уже были
var night_time := 0.0
var follow_steps := 0           ## шаги «за спиной», которые ещё прозвучат
var flicker_time := 0.0
var lantern_dead_time := 0.0
var window_strength := 0.0
var figure: Node3D
var figure_time := 0.0
var lunger: Node3D
var lunge_time := 0.0
var lunge_hit := false
var last_damage_time := -99.0

const TYPES := ["figure", "window", "radio", "flicker", "steps", "lunge", "slam", "breath", "watcher", "water", "shutter", "blackout", "displace"]
## Присутствие (вторая волна мрака): наблюдатель на краю видимости, что-то в воде, ставни,
## отключение света в помещении, сдвинутый предмет.
var watcher: Node3D
var watcher_time := 0.0
var swimmer: Node3D
var swimmer_time := 0.0

func _init() -> void:
	rng.randomize()

func reset() -> void:
	tension = 0
	fear = 0
	quiet = 0
	cooldowns.clear()
	history.clear()
	hush = 0
	pending = ""
	scripted.clear()
	night_time = 0
	follow_steps = 0
	flicker_time = 0
	lantern_dead_time = 0
	window_strength = 0
	_clear_figure()
	_clear_lunger()
	_clear_watcher()
	_clear_swimmer()

# ---------------------------------------------------------------- состояние
func running() -> bool:
	return is_instance_valid(game) and game.playing and not game.paused and not game.finished and not game.expedition.sailing and not game.fishing.is_open()

func is_night() -> bool:
	return game.is_night() or (game.campaign.enabled and game.campaign.state.night)

func indoors() -> bool:
	return game.lighthouse_interior.active or not game.building_interiors.active.is_empty()

func compute_tension() -> float:
	var t := 0.0
	if is_night():
		t += .25
		if not game.is_safe(game.player.position):
			t += .15
		if not game.player.lantern_on:
			t += .25
	t += clampf((BAL.SANITY_TENSE_AT - game.sanity) / BAL.SANITY_TENSE_AT, 0, 1) * .45
	t += clampf((BAL.LOW_HEALTH_AT + 15 - game.health) / (BAL.LOW_HEALTH_AT + 15), 0, 1) * .35
	var near := 0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.passive and enemy.global_position.distance_to(game.player.global_position) < 7:
			near += 1
	t += minf(.3, near * .12)
	if game.island_events.current == "fog":
		t += .15
	return clampf(t, 0, 1)

func heart_bpm() -> float:
	var stress := maxf(clampf((BAL.SANITY_TENSE_AT - game.sanity) / BAL.SANITY_TENSE_AT, 0, 1), clampf((BAL.LOW_HEALTH_AT + 10 - game.health) / (BAL.LOW_HEALTH_AT + 10), 0, 1))
	stress = maxf(stress, fear * .8)
	if stress <= .02:
		return 0.0
	return lerpf(62, 138, stress)

# ---------------------------------------------------------------- кадр
func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	fear = maxf(0, fear - delta * .9)
	if not running():
		_apply_feedback(delta, false)
		return
	tension = move_toward(tension, compute_tension(), delta * .4)
	for key in cooldowns.keys():
		cooldowns[key] = maxf(0, float(cooldowns[key]) - delta)
	quiet += delta
	night_time = night_time + delta if is_night() else 0.0
	_tick_figure(delta)
	_tick_lunger(delta)
	_tick_watcher(delta)
	_tick_swimmer(delta)
	_tick_flicker(delta)
	window_strength = move_toward(window_strength, 0.0, delta * .9) if pending != "window_hold" else window_strength
	if hush > 0:
		hush -= delta
		if hush <= 0 and not pending.is_empty():
			var kind := pending
			pending = ""
			fire(kind)
	else:
		_scripted_moments()
		_maybe_scare(delta)
	_apply_feedback(delta, true)

func _apply_feedback(delta: float, live: bool) -> void:
	var calm := 0.0 if live else 1.0
	game.sound.set_tension(tension * (1.0 - calm), heart_bpm() if live else 0.0, delta)
	var mat: ShaderMaterial = game.hud.atmosphere.material
	if mat != null:
		mat.set_shader_parameter("fear", fear)
		mat.set_shader_parameter("tension", tension if live else 0.0)
		mat.set_shader_parameter("heartbeat", clampf(heart_bpm() / 140.0, 0, 1) if live else 0.0)
	if not live:
		return
	# Темнее и гуще туман, когда страшно; затишье перед пугалкой глушит море.
	var env: Environment = game.world.get_node("CoastalAtmosphere").environment
	env.ambient_light_energy *= 1.0 - tension * .35
	env.fog_density += tension * .006
	if hush > 0:
		game.sound.sea.volume_db = move_toward(game.sound.sea.volume_db, -60, delta * 40)

# ---------------------------------------------------------------- выбор пугалки
func _maybe_scare(delta: float) -> void:
	if quiet < BAL.SCARE_MIN_GAP:
		return
	if is_night() and night_time < BAL.SCARE_FIRST_DELAY:
		return
	if game.first_shift_demo.active() or game.day < 2 and not is_night():
		return
	var chance := BAL.SCARE_CHANCE_PER_SEC * (0.6 + tension * 1.4)
	if not is_night():
		chance *= BAL.SCARE_DAY_CHANCE_MULT
	if rng.randf() >= chance * delta:
		return
	var options := eligible()
	if options.is_empty():
		return
	queue(options[rng.randi_range(0, options.size() - 1)])

func eligible() -> Array:
	var list := []
	var night := is_night()
	var inside := indoors()
	for kind in TYPES:
		if float(cooldowns.get(kind, 0.0)) > 0 or (not history.is_empty() and history.back() == kind):
			continue
		match kind:
			"figure":
				if night and not inside and game.player.lantern_on:
					list.append(kind)
			"window":
				if night and game.building_interiors.active == "cabin":
					list.append(kind)
			"radio":
				if night and (game.building_interiors.active in ["cabin", "radio"] or rng.randf() < .3):
					list.append(kind)
			"flicker":
				if night and game.player.lantern_on and not inside:
					list.append(kind)
			"steps":
				if not inside and game.player.velocity.length() > 1.0:
					list.append(kind)
			"lunge":
				if night and not inside and game.sanity < BAL.SANITY_HALLUCINATE_AT:
					list.append(kind)
			"slam":
				if night and (inside and not game.lighthouse_interior.active or game.player.position.distance_to(Vector3(5, 1, 1)) < 9):
					list.append(kind)
			"breath":
				if night and not game.player.lantern_on:
					list.append(kind)
			"watcher":
				if not inside and (night or game.island_events.current == "fog" or game.day >= 5):
					list.append(kind)
			"water":
				if not inside and _near_shore():
					list.append(kind)
			"shutter":
				if night or game.day >= 6:
					list.append(kind)
			"blackout":
				if night and inside and not game.lighthouse_interior.active:
					list.append(kind)
			"displace":
				if not inside and is_instance_valid(game.dread) and game.day >= 3:
					list.append(kind)
	return list

## Крупные пугалки идут после короткого затишья — так «внезапно» срабатывает сильнее.
func queue(kind: String) -> void:
	quiet = 0
	cooldowns[kind] = BAL.SCARE_TYPE_COOLDOWN
	history.append(kind)
	if history.size() > 8:
		history.pop_front()
	if kind in ["figure", "lunge", "slam", "window"]:
		pending = kind
		hush = rng.randf_range(1.8, 3.0)
	else:
		fire(kind)

func _scripted_moments() -> void:
	if not game.campaign.enabled or game.first_shift_demo.active():
		return
	var night: bool = game.campaign.state.night
	# Ночь 2: первый раз, когда игрок светит лучом, в нём на миг стоит фигура.
	if night and game.day == 2 and not scripted.has("beam2") and game.lantern_beam.focusing and night_time > 8:
		scripted["beam2"] = true
		pending = "figure"
		hush = 0.35
		quiet = 0
	# Ночь 3: эфир взрывается помехами и чужим голосом.
	elif night and game.day == 3 and not scripted.has("radio3") and night_time > 14:
		scripted["radio3"] = true
		queue("radio")
	# Ночь 4: шаги за спиной по дороге к генератору.
	elif night and game.day == 4 and not scripted.has("steps4") and night_time > 10 and game.player.velocity.length() > 1:
		scripted["steps4"] = true
		queue("steps")

# ---------------------------------------------------------------- исполнение
func fire(kind: String) -> void:
	if not running():
		return
	match kind:
		"figure": _figure()
		"window": _window()
		"radio": _radio_burst()
		"flicker": _flicker(rng.randf() < .45)
		"steps": follow_steps = rng.randi_range(4, 7)
		"lunge": _lunge()
		"slam": _slam()
		"breath":
			game.sound.scare("breath", -10, rng.randf_range(.9, 1.0), game.player.global_position - _facing() * 1.6 + Vector3.UP * 1.5)
			game.sanity = maxf(0, game.sanity - 2)
		"watcher": _watcher()
		"water": _water()
		"shutter": _shutter()
		"blackout": _blackout()
		"displace":
			if game.dread.displace_gull():
				game.sound.sfx("creak", -16, .75)

func _facing() -> Vector3:
	var yaw: float = game.player.get_node("Visual").rotation.y
	return Vector3(sin(yaw), 0, cos(yaw))

func jolt(amount: float) -> void:
	fear = maxf(fear, amount)
	game.camera_shake = maxf(game.camera_shake, amount * .45)

func _silhouette(at: Vector3, tall := 2.3) -> Node3D:
	var root := Node3D.new()
	root.name = "Apparition"
	game.add_child(root)
	root.global_position = at
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.012, 0.018)
	var body := Geo.sphere(root, "Body", Vector3(0, tall * .48, 0), Vector3(.62, tall * .95, .42), Color(0.01, 0.012, 0.018))
	body.material_override = mat
	var head := Geo.sphere(root, "Head", Vector3(0, tall * .98, 0), Vector3(.34, .42, .34), Color(0.01, 0.012, 0.018))
	head.material_override = mat
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(0.95, 0.93, 0.82)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.95, 0.9, 0.75)
	eye_mat.emission_energy_multiplier = 3.0
	for side in [-.09, .09]:
		var eye := Geo.sphere(root, "Eye", Vector3(side, tall * 1.0, .17), Vector3(.07, .045, .03), Color.WHITE)
		eye.material_override = eye_mat
	# Холодный контровой свет за спиной: чёрный силуэт читается на ночном фоне.
	var rim := OmniLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color("9fb8d8")
	rim.light_energy = 2.4
	rim.omni_range = 3.4
	rim.position = Vector3(0, tall * .75, -.9)
	root.add_child(rim)
	return root

func _figure() -> void:
	var aim: Vector3 = game.lantern_beam.aim if game.lantern_beam.focusing else _facing()
	var spot: Variant = game.night_raids.ground_at(game.player.global_position + aim.normalized() * rng.randf_range(5.5, 7.0))
	if spot == null:
		_flicker(false)
		return
	_clear_figure()
	figure = _silhouette(spot - Vector3(0, .35, 0))
	figure.look_at(Vector3(game.player.global_position.x, figure.global_position.y, game.player.global_position.z), Vector3.UP, true)
	figure_time = .55
	game.sound.scare("stinger", -3)
	jolt(.9)
	_glitch(.6)
	game.sanity = maxf(0, game.sanity - 6)

func _tick_figure(delta: float) -> void:
	if not is_instance_valid(figure):
		return
	figure_time -= delta
	# Фигура не выдерживает прямого луча — исчезает быстрее.
	if game.lantern_beam.focusing and game.lantern_beam.in_cone(figure.global_position):
		figure_time -= delta * 3
	if figure_time <= 0:
		_clear_figure()
		_flicker(false)

func _clear_figure() -> void:
	if is_instance_valid(figure):
		figure.queue_free()
	figure = null

func _window() -> void:
	window_strength = 1.0
	pending = "window_hold"
	game.sound.horror_cue("knock", game.player.global_position + Vector3(-1.5, .5, -2))
	jolt(.6)
	game.sanity = maxf(0, game.sanity - 4)
	await get_tree().create_timer(1.1).timeout
	if pending == "window_hold":
		pending = ""

func _radio_burst() -> void:
	game.sound.scare("static", -2, rng.randf_range(.95, 1.05))
	game.sound.scare("whisper_long", -9, .82)
	if is_instance_valid(game.radio):
		game.radio.say(["static_voice", "alone"][rng.randi_range(0, 1)], false, false)
	jolt(.55)
	_flicker(false)
	game.sanity = maxf(0, game.sanity - 4)

func _flicker(kill: bool) -> void:
	flicker_time = rng.randf_range(1.2, 1.9)
	game.sound.cue("flicker")
	if kill and game.player.lantern_on:
		lantern_dead_time = rng.randf_range(1.4, 2.2)

func _tick_flicker(delta: float) -> void:
	var lantern := game.player.get_node_or_null("HandLantern") as OmniLight3D
	if lantern == null:
		return
	if lantern_dead_time > 0:
		lantern_dead_time -= delta
		lantern.light_energy = 0.0
		if lantern_dead_time <= 0:
			lantern.light_energy = BAL.LANTERN_ENERGY
			game.sound.cue("flicker")
		return
	if flicker_time > 0:
		flicker_time -= delta
		var on := rng.randf() < .55
		lantern.light_energy = BAL.LANTERN_ENERGY * (rng.randf_range(.6, 1.2) if on else .05)
		if is_instance_valid(game.beacon):
			var beam := game.beacon.get_node_or_null("BeamPivot") as Node3D
			if beam != null and game.lighthouse_on:
				beam.visible = on or flicker_time < .2
		if flicker_time <= 0:
			lantern.light_energy = BAL.LANTERN_ENERGY
			var beam2 := game.beacon.get_node_or_null("BeamPivot") as Node3D
			if beam2 != null:
				beam2.visible = game.lighthouse_on
	elif game.lantern_oil < BAL.LANTERN_OIL_LOW and game.player.lantern_on:
		# Масло на исходе: фонарь сам по себе неровно горит.
		lantern.light_energy = BAL.LANTERN_ENERGY * (.55 + .45 * absf(sin(Time.get_ticks_msec() * .011)) * (.6 + rng.randf() * .4))
	else:
		lantern.light_energy = BAL.LANTERN_ENERGY

func _lunge() -> void:
	var side := _facing().rotated(Vector3.UP, rng.randf_range(1.9, 4.4))
	var spot: Variant = game.night_raids.ground_at(game.player.global_position + side * 4.0)
	if spot == null:
		_radio_burst()
		return
	_clear_lunger()
	lunger = _silhouette(spot - Vector3(0, .35, 0), 2.0)
	lunge_time = .9
	lunge_hit = false
	game.sound.scare("tell", -4)

func _tick_lunger(delta: float) -> void:
	if not is_instance_valid(lunger):
		return
	lunge_time -= delta
	var target: Vector3 = game.player.global_position
	var flat := Vector3(target.x - lunger.global_position.x, 0, target.z - lunger.global_position.z)
	if lunge_time < .6:
		lunger.global_position += flat.normalized() * minf(flat.length(), delta * 11.0)
	flat = Vector3(target.x - lunger.global_position.x, 0, target.z - lunger.global_position.z)
	if flat.length() > .05:
		lunger.look_at(Vector3(target.x, lunger.global_position.y, target.z), Vector3.UP, true)
	if not lunge_hit and flat.length() < .9:
		lunge_hit = true
		game.sound.scare("stinger", -1, 1.08)
		jolt(1.0)
		game.sanity = maxf(0, game.sanity - 8)
		game.take_damage(3.0, "phantom")
		_clear_lunger()
		return
	if lunge_time <= 0:
		_clear_lunger()

func _clear_lunger() -> void:
	if is_instance_valid(lunger):
		lunger.queue_free()
	lunger = null

func _slam() -> void:
	var at: Vector3 = game.player.global_position + _facing() * -2.5 + Vector3.UP
	game.sound.scare("slam", -1, rng.randf_range(.92, 1.05), at)
	jolt(.8)
	_flicker(false)
	game.sanity = maxf(0, game.sanity - 5)

# ---------------------------------------------------------------- присутствие
func _glitch(amount: float) -> void:
	if is_instance_valid(game.dread):
		game.dread.glitch_pulse(amount)

## Наблюдатель: стоит на краю видимости и смотрит. Исчезает, если подойти, навести луч
## или просто подождать. Почти не пугает «в лоб» — пугает тем, что был.
func _watcher() -> void:
	var p: Vector3 = game.player.global_position
	for attempt in 6:
		var angle := rng.randf() * TAU
		var spot: Variant = game.night_raids.ground_at(p + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(BAL.WATCHER_MIN_DIST, BAL.WATCHER_MAX_DIST))
		if spot == null:
			continue
		_clear_watcher()
		watcher = _silhouette((spot as Vector3) - Vector3(0, .35, 0), rng.randf_range(2.2, 2.7))
		watcher.name = "Watcher"
		var rim := watcher.get_node_or_null("Rim") as OmniLight3D
		if rim != null:
			rim.light_energy = 1.2
		watcher.look_at(Vector3(p.x, watcher.global_position.y, p.z), Vector3.UP, true)
		watcher_time = BAL.WATCHER_SECONDS
		game.sound.sfx("whisper", -16, .8, watcher.global_position)
		return

func _tick_watcher(delta: float) -> void:
	if not is_instance_valid(watcher):
		return
	watcher_time -= delta
	var p: Vector3 = game.player.global_position
	var flat := Vector2(watcher.global_position.x - p.x, watcher.global_position.z - p.z).length()
	var lit: bool = game.lantern_beam.focusing and game.lantern_beam.in_cone(watcher.global_position)
	if flat < BAL.WATCHER_VANISH_DIST or lit or watcher_time <= 0:
		var seen := flat < BAL.WATCHER_VANISH_DIST or lit
		_clear_watcher()
		if seen:
			_glitch(.7)
			jolt(.45)
			game.sanity = maxf(0, game.sanity - 3)
			game.sound.scare("stinger", -12, .9)

func _clear_watcher() -> void:
	if is_instance_valid(watcher):
		watcher.queue_free()
	watcher = null

func _near_shore() -> bool:
	return _water_spot() != null

func _water_spot() -> Variant:
	var p: Vector3 = game.player.global_position
	for i in 10:
		var angle := i * TAU / 10 + rng.randf() * .3
		for dist in [11.0, 15.0, 19.0]:
			var at: Vector3 = p + Vector3(cos(angle), 0, sin(angle)) * dist
			if game.night_raids.ground_at(at) == null and game.night_raids.ground_at(at.lerp(p, .35)) != null:
				return Vector3(at.x, 0, at.z)
	return null

## Что-то в воде: тёмная голова медленно поднимается у берега и уходит под воду.
func _water() -> void:
	var spot: Variant = _water_spot()
	if spot == null:
		return
	_clear_swimmer()
	swimmer = Node3D.new()
	swimmer.name = "Swimmer"
	game.add_child(swimmer)
	swimmer.global_position = (spot as Vector3) + Vector3(0, -.6, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.012, 0.018)
	var head := Geo.sphere(swimmer, "Head", Vector3(0, .25, 0), Vector3(.42, .55, .42), Color.BLACK)
	head.material_override = mat
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(0.9, 0.88, 0.78)
	for side in [-.09, .09]:
		var eye := Geo.sphere(swimmer, "Eye", Vector3(side, .36, .19), Vector3(.06, .035, .03), Color.WHITE)
		eye.material_override = eye_mat
	var p: Vector3 = game.player.global_position
	swimmer.look_at(Vector3(p.x, swimmer.global_position.y, p.z), Vector3.UP, true)
	swimmer_time = BAL.SWIMMER_SECONDS
	game.sound.sfx("splash", -9, .7, swimmer.global_position)

func _tick_swimmer(delta: float) -> void:
	if not is_instance_valid(swimmer):
		return
	swimmer_time -= delta
	var k := 1.0 - swimmer_time / BAL.SWIMMER_SECONDS
	# поднимается за первую треть, смотрит, уходит под воду
	var rise := smoothstep(0.0, .3, k) * (1.0 - smoothstep(.75, 1.0, k))
	swimmer.global_position.y = lerpf(-.7, .05, rise)
	if swimmer_time <= 0:
		game.sound.sfx("splash", -14, .6, swimmer.global_position)
		_clear_swimmer()

func _clear_swimmer() -> void:
	if is_instance_valid(swimmer):
		swimmer.queue_free()
	swimmer = null

## Ставни/дверь хлопают у ближайшей постройки.
func _shutter() -> void:
	var p: Vector3 = game.player.global_position
	var spots := [Vector3(5, 2, 0), Vector3(0.3, 2, 0.8), Vector3(-9, 2, -7), Vector3(-12, 2, -35.9), Vector3(1.5, 2, -21.7)]
	spots.sort_custom(func(a, b): return a.distance_to(p) < b.distance_to(p))
	var nearest: Vector3 = spots[0]
	var at: Vector3 = nearest if nearest.distance_to(p) < 30 else p + _facing() * -6.0
	game.sound.sfx("knock", -4, rng.randf_range(.8, .95), at)
	await get_tree().create_timer(.35).timeout
	if is_instance_valid(game):
		game.sound.sfx("knock", -7, rng.randf_range(.75, .9), at)
	jolt(.35)
	game.sanity = maxf(0, game.sanity - 2)

## Внутри гаснет свет: лампы проваливаются в темноту, в тишине кто-то дышит.
func _blackout() -> void:
	game.dread.blackout(rng.randf_range(1.2, 2.2))
	_glitch(.4)
	await get_tree().create_timer(.5).timeout
	if is_instance_valid(game):
		game.sound.scare("breath", -12, .85, game.player.global_position - _facing() * 1.4 + Vector3.UP * 1.5)
		game.sanity = maxf(0, game.sanity - 3)
		jolt(.4)

## Для превью и тестов: показать наблюдателя и что-то в воде прямо сейчас.
func force_presence() -> void:
	_watcher()
	_water()

# ---------------------------------------------------------------- обратные вызовы
func on_player_step() -> void:
	if follow_steps <= 0 or not running():
		return
	follow_steps -= 1
	var behind: Vector3 = game.player.global_position - _facing() * rng.randf_range(3.5, 5.0)
	var surface: String = game.step_surface()
	await get_tree().create_timer(rng.randf_range(.16, .24)).timeout
	if not is_instance_valid(game):
		return
	game.sound.phantom_step(behind, surface)
	if follow_steps == 0:
		# Последний шаг — ближе и громче. Потом тишина.
		await get_tree().create_timer(.7).timeout
		game.sound.phantom_step(game.player.global_position - _facing() * 1.6, surface)
		game.sanity = maxf(0, game.sanity - 3)
		fear = maxf(fear, .35)

func on_damage(amount: float) -> void:
	fear = maxf(fear, clampf(amount / 25.0, .2, .7))
	last_damage_time = Time.get_ticks_msec() * .001

func on_lantern_died() -> void:
	fear = maxf(fear, .5)
	quiet = minf(quiet, BAL.SCARE_MIN_GAP * .5)
	cooldowns["breath"] = 0.0
