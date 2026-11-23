extends Node3D
## Мелкие страхи:
## - зеркало в хижине: отражение иногда запаздывает на секунду, а потом замирает и смотрит на вас;
## - собственный голос по радио ночью («Это я. Открой дверь»);
## - утром вещи стоят не там, где вы их оставили.
const VISUAL = preload("res://scripts/character_visual.gd")
const MOTION = preload("res://scripts/character_motion.gd")
const Geo = preload("res://scripts/geometry.gd")
const BI = preload("res://scripts/building_interiors.gd")
const MIRROR_LAYER := 1 << 19        ## слой двойника — его видит только камера зеркала
const PLAYER_LAYER := 1 << 18        ## слой смотрителя — камера зеркала его не видит
const LAG := 1.0
const LAG_SECONDS := 7.0
const STARE_SECONDS := 1.6

var game: Node
var rng := RandomNumberGenerator.new()
# зеркало
var mirror_root: Node3D
var viewport: SubViewport
var mirror_cam: Camera3D
var double: Node3D
var double_motion := MOTION.new()
var history: Array = []              ## [{t, pos, yaw, moving}]
var clock := 0.0
var lag_time := 0.0
var stare_time := 0.0
var mirror_clock := 20.0
var mirror_scares := 0
# голос
var voice_used := {}
var voice_clock := 30.0
# утро
var night_was := false
var moved_today: Array = []

func _init() -> void:
	rng.randomize()

func setup() -> void:
	_build_mirror()
	_tag_player()

func reset() -> void:
	lag_time = 0
	stare_time = 0
	mirror_clock = 20.0
	mirror_scares = 0
	voice_used.clear()
	voice_clock = 30.0
	night_was = false
	moved_today.clear()
	history.clear()

# ---------------------------------------------------------------- зеркало
func mirror_at() -> Vector3:
	return BI.ROOMS.cabin.origin + Vector3(-2.93, 1.5, 1.0)

func _build_mirror() -> void:
	mirror_root = Node3D.new()
	mirror_root.name = "CabinMirror"
	add_child(mirror_root)
	mirror_root.global_position = mirror_at()
	Geo.box(mirror_root, "Frame", Vector3(0, 0, 0), Vector3(.05, 1.0, .72), Color("2b2018"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(192, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.transparent_bg = false
	add_child(viewport)
	mirror_cam = Camera3D.new()
	mirror_cam.fov = 62
	mirror_cam.cull_mask = (0xFFFFF & ~PLAYER_LAYER) | MIRROR_LAYER
	viewport.add_child(mirror_cam)
	mirror_cam.current = true
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = Vector2(.62, .88)
	glass.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.albedo_color = Color(.92, .97, 1.0)
	mat.uv1_scale = Vector3(-1, 1, 1)
	mat.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = mat
	glass.position = Vector3(.03, 0, 0)
	glass.rotation.y = PI / 2
	mirror_root.add_child(glass)
	# камера зеркала смотрит в комнату из плоскости стекла
	mirror_cam.position = mirror_at() + Vector3(.05, 0, 0)
	mirror_cam.look_at_from_position(mirror_cam.position, mirror_cam.position + Vector3(1, -.12, 0), Vector3.UP)
	# двойник — модель смотрителя, видна только в зеркале
	double = Node3D.new()
	double.name = "Reflection"
	add_child(double)
	var model := VISUAL.install(double, "keeper")
	if model != null:
		double_motion.bind(model)
		for mesh in model.find_children("*", "VisualInstance3D", true, false):
			(mesh as VisualInstance3D).layers = MIRROR_LAYER
	double.hide()

func _tag_player() -> void:
	for mesh in game.player.find_children("*", "VisualInstance3D", true, false):
		var v := mesh as VisualInstance3D
		if not v is Light3D:
			v.layers = (v.layers | PLAYER_LAYER)
	if is_instance_valid(game.camera):
		game.camera.cull_mask = game.camera.cull_mask & ~MIRROR_LAYER

func in_cabin() -> bool:
	return game.building_interiors.active == "cabin"

func lagging() -> bool:
	return lag_time > 0

func start_lag() -> void:
	lag_time = LAG_SECONDS
	stare_time = 0
	mirror_scares += 1

func _tick_mirror(delta: float) -> void:
	var on: bool = in_cabin() and game.playing
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on and mirror_cam.environment == null and game.building_interiors.room_env != null:
		mirror_cam.environment = game.building_interiors.room_env
	double.visible = on
	if not on:
		history.clear()
		lag_time = 0
		return
	var p: Vector3 = game.player.global_position
	var yaw: float = game.player.get_node("Visual").global_rotation.y if game.player.has_node("Visual") else game.player.global_rotation.y
	var moving: bool = Vector2(game.player.velocity.x, game.player.velocity.z).length() > .3
	history.append({"t": clock, "pos": p, "yaw": yaw, "moving": moving})
	while history.size() > 2 and float(history[1].t) < clock - LAG - .2:
		history.pop_front()
	# решаем, когда отражению «опоздать»
	if lag_time <= 0 and stare_time <= 0:
		mirror_clock -= delta
		var near: bool = p.distance_to(mirror_at()) < 3.2
		if mirror_clock <= 0 and near and (game.is_night() or game.sanity < 70):
			start_lag()
			mirror_clock = rng.randf_range(60, 120)
	var src: Dictionary = history.back()
	if lag_time > 0:
		lag_time -= delta
		src = _sample(clock - LAG)
		if lag_time <= 0:
			stare_time = STARE_SECONDS
			game.sound.sfx("whisper", -14, .8, mirror_at())
			game.sanity = maxf(0, game.sanity - 4)
			if is_instance_valid(game.dread):
				game.dread.glitch_pulse(.35)
	if stare_time > 0:
		stare_time -= delta
		# двойник стоит и смотрит в зеркало — на вас
		double.global_position.y = p.y
		double.rotation.y = -PI / 2
		double_motion.play("idle", .2)
	else:
		double.global_position = src.pos
		double.rotation.y = float(src.yaw)
		double_motion.play("walk" if bool(src.moving) else "idle", .15)
	double_motion.tick(delta)

func _sample(t: float) -> Dictionary:
	for h in history:
		if float(h.t) >= t:
			return h
	return history.back()

# ---------------------------------------------------------------- голос
func _tick_voice(delta: float) -> void:
	if not game.campaign.enabled or not bool(game.campaign.state.night) or game.day < 6:
		return
	voice_clock -= delta
	if voice_clock > 0:
		return
	voice_clock = rng.randf_range(40, 70)
	play_own_voice()

func play_own_voice() -> bool:
	for id in ["own_1", "own_2"]:
		if not voice_used.has(id):
			voice_used[id] = true
			game.radio.say(id, false, true)
			game.sanity = maxf(0, game.sanity - 5)
			game.notify("Из приёмника звучит ваш собственный голос.", 5, 1)
			if is_instance_valid(game.hunter):
				game.hunter.noise(game.map_player_position() + Vector3(4, 0, 4), .6)
			return true
	return false

# ---------------------------------------------------------------- утро
func _tick_dawn() -> void:
	var night: bool = game.campaign.enabled and bool(game.campaign.state.night)
	if night_was and not night and game.day >= 3:
		move_things()
	night_was = night

func move_things() -> Array:
	moved_today.clear()
	var options: Array = []
	if is_instance_valid(game.save_points):
		options.append("logbook")
	if is_instance_valid(game.supplies):
		options.append("barrel")
		options.append("crate")
	options.append("gull")
	options.shuffle()
	var count := 1 if game.day < 7 else 2
	for i in mini(count, options.size()):
		var what: String = options[i]
		if _move(what):
			moved_today.append(what)
	if not moved_today.is_empty():
		var words := {"logbook":"журнал смены раскрыт на чужой странице", "barrel":"бочка с маслом отодвинута к двери", "crate":"ящик ракет перевёрнут", "gull":"мёртвая чайка лежит на крыльце"}
		var parts := PackedStringArray()
		for w in moved_today:
			parts.append(words[w])
		game.notify("Утром вещи стоят не там, где вы их оставили: %s." % ", ".join(parts), 8, 1)
		game.sanity = maxf(0, game.sanity - 2)
	return moved_today

func _move(what: String) -> bool:
	match what:
		"logbook":
			var book: Node3D = game.save_points.get_node_or_null("Logbook_cabin")
			if book == null:
				return false
			book.rotation.y = rng.randf_range(.6, 2.4)
			return true
		"barrel", "crate":
			var node: Node3D = game.supplies.get_node_or_null("Supply_" + ("oil_barrel" if what == "barrel" else "flare_crate"))
			if node == null:
				return false
			node.rotation.y = rng.randf_range(-1, 1)
			node.rotation.z = .25 if what == "crate" else 0.0
			node.global_position += Vector3(rng.randf_range(-.8, -.3), 0, rng.randf_range(.3, .8))
			return true
		"gull":
			if not is_instance_valid(game.dread) or game.dread.gulls.is_empty():
				return false
			var bird: Node3D = game.dread.gulls[0]
			if not is_instance_valid(bird):
				return false
			bird.global_position = Vector3(5.4, bird.global_position.y if bird.global_position.y > .3 else 1.0, 4.4)
			var g: Variant = game.night_raids.ground_at(Vector3(5.4, 1, 4.4))
			if g != null:
				bird.global_position = (g as Vector3) - Vector3(0, .33, 0)
			return true
	return false

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.finished:
		if is_instance_valid(viewport):
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	clock += delta
	if game.paused:
		return
	_tick_mirror(delta)
	_tick_voice(delta)
	_tick_dawn()

func save_data() -> Dictionary:
	return {"voice_used": voice_used.keys(), "mirror_scares": mirror_scares}

func restore(data: Variant) -> void:
	reset()
	if data is Dictionary:
		for id in data.get("voice_used", []):
			voice_used[str(id)] = true
		mirror_scares = int(data.get("mirror_scares", 0))
