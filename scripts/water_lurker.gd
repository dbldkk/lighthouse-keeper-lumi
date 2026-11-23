extends Node3D
## Второй враг (v1.3): что-то живёт под причалами. Ночью, если стоять у самого края настила,
## вода сначала начинает бурлить (пузыри, круги, плеск — EDGE_TRIGGER секунд у края),
## затем даёт TELEGRAPH секунд, чтобы отойти. Не отошли — хватает за ногу и утаскивает под доски:
## урон, потеря рассудка, вас выбрасывает на берег. Отошли вовремя — достижение «Не у края».
const ZONES := [
	Rect2(16.5, 2.5, 9.0, 5.0),        ## рыбацкий причал (x 16.5..25.5, z 2.5..7.5)
	Rect2(-31.5, -23.5, 13.0, 5.0),    ## пирс северной гавани
]
const EDGE_PROBE := 1.15
const EDGE_TRIGGER := 2.0
const TELEGRAPH := 2.6
const DRAG_SECONDS := 1.1
const DAMAGE := 30.0
const SANITY := 15.0
const COOLDOWN := 25.0

var game: Node
var rng := RandomNumberGenerator.new()
var state := "idle"                 ## idle / bubbling / drag / cooldown
var edge_clock := 0.0
var timer := 0.0
var water_at := Vector3.ZERO        ## точка воды у края, откуда оно поднимается
var grabs := 0
var escapes := 0
var warned_once := false
var fx: Node3D
var rings: Array = []
var bubbles: Array = []
var arm: Node3D
var drag_from := Vector3.ZERO

func _ready() -> void:
	rng.randomize()
	fx = Node3D.new()
	fx.name = "LurkerFx"
	add_child(fx)
	fx.visible = false
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(.75, .85, .88, .55)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 3:
		var r := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = .42
		t.outer_radius = .5
		r.mesh = t
		r.material_override = ring_mat
		fx.add_child(r)
		rings.append(r)
	for i in 8:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = .07
		s.height = .14
		b.mesh = s
		b.material_override = ring_mat
		fx.add_child(b)
		bubbles.append(b)
	arm = Node3D.new()
	arm.name = "LurkerArm"
	fx.add_child(arm)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("0d1416")
	skin.roughness = .25
	skin.metallic_specular = .8
	for k in 4:
		var seg := MeshInstance3D.new()
		var c := CapsuleMesh.new()
		c.radius = .14 - k * .025
		c.height = .7
		seg.mesh = c
		seg.material_override = skin
		seg.position = Vector3(k * .12, .35 + k * .55, -k * .1)
		seg.rotation.z = -.25 - k * .2
		arm.add_child(seg)
	arm.visible = false

func reset() -> void:
	state = "idle"
	edge_clock = 0
	timer = 0
	fx.visible = false
	arm.visible = false

func active_night() -> bool:
	return game.campaign.enabled and bool(game.campaign.state.night) and game.day >= 2 and not game.first_shift_demo.active()

func in_zone(p: Vector3) -> bool:
	for z in ZONES:
		if (z as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false

## Вода рядом с ногами: точка без земли в EDGE_PROBE метрах. Возвращает её или null.
func water_near(p: Vector3) -> Variant:
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
		var q: Vector3 = p + dir * EDGE_PROBE
		if game.night_raids.ground_at(q) == null:
			return Vector3(q.x, _ocean_y(), q.z)
	return null

func at_edge() -> bool:
	if not game.building_interiors.active.is_empty() or game.lighthouse_interior.active or game.expedition.sailing:
		return false
	var p: Vector3 = game.player.global_position
	if not in_zone(p) or p.y < .5:
		return false
	return water_near(p) != null

func _ocean_y() -> float:
	var ocean: Node3D = game.world.get_node_or_null("Ocean")
	return ocean.global_position.y if ocean != null else 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.paused or game.finished:
		return
	tick(delta)

func telegraph_seconds() -> float:
	return TELEGRAPH * (.8 if game.difficulty == "nightmare" else 1.0)

func tick(delta: float) -> void:
	_animate(delta)
	if not active_night():
		if state != "idle":
			reset()
		return
	var p: Vector3 = game.player.global_position
	if not warned_once and in_zone(p) and game.building_interiors.active.is_empty():
		warned_once = true
		game.radio.say("pier_warning", true)
	match state:
		"idle":
			if at_edge():
				edge_clock += delta
				if edge_clock >= EDGE_TRIGGER:
					_start_bubbling()
			else:
				edge_clock = maxf(0, edge_clock - delta * 2)
		"bubbling":
			timer -= delta
			if not at_edge() or Vector2(p.x - water_at.x, p.z - water_at.z).length() > EDGE_PROBE + 1.6:
				escapes += 1
				state = "cooldown"
				timer = COOLDOWN * .5
				game.notify("Вы отошли от края. Под досками что-то разочарованно плеснуло.", 4)
				game.sound.cue("splash")
				if is_instance_valid(game.achievements):
					game.achievements.unlock("pier_escape")
			elif timer <= 0:
				_grab()
		"drag":
			timer -= delta
			var k := clampf(1.0 - timer / DRAG_SECONDS, 0, 1)
			game.player.global_position = drag_from.lerp(Vector3(water_at.x, drag_from.y - .6 * k, water_at.z), k * .8)
			if timer <= 0:
				_release()
		"cooldown":
			timer -= delta
			edge_clock = 0
			if timer <= 0:
				state = "idle"
				fx.visible = false

func _start_bubbling() -> void:
	var w: Variant = water_near(game.player.global_position)
	if w == null:
		return
	water_at = w
	state = "bubbling"
	timer = telegraph_seconds()
	edge_clock = 0
	fx.visible = true
	arm.visible = false
	fx.global_position = water_at
	game.sound.cue("splash")
	game.sound.sfx("hunter_breath", -8, .5, water_at)
	game.alert("ВОДА БУРЛИТ", "Отойдите от края причала — сейчас же!", 3)
	game.camera_shake = maxf(game.camera_shake, .08)

func _grab() -> void:
	grabs += 1
	state = "drag"
	timer = DRAG_SECONDS
	drag_from = game.player.global_position
	arm.visible = true
	if game.fishing.is_open():
		game.close_fishing()
	game.player.reset_motion()
	game.sound.scare("stinger", -2, .7)
	game.sound.sfx("splash", 0, .7, water_at)
	if is_instance_valid(game.dread):
		game.dread.glitch_pulse(.9)
	game.camera_shake = maxf(game.camera_shake, .5)

func _release() -> void:
	arm.visible = false
	state = "cooldown"
	timer = COOLDOWN
	game.sanity = maxf(0, game.sanity - SANITY)
	game.take_damage(DAMAGE, "water")
	var at: Vector3 = game.last_safe_position
	if at.y < .5 or in_zone(at):
		at = Vector3(16, 1.3, 7.5) if water_at.x > 0 else Vector3(-24, 1.3, -17)
	game.player.global_position = at
	game.player.reset_motion()
	game.camera_focus = game.player.position + Vector3.UP
	if game.health > 0:
		game.notify("Что-то схватило за ногу и утащило под доски. Вы вырвались и выползли на берег — едва.", 7, 2)

func _animate(delta: float) -> void:
	if not fx.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var strength := 1.0 if state in ["bubbling", "drag"] else maxf(0, timer / COOLDOWN - .6)
	for i in rings.size():
		var ph := fmod(t * .9 + i / 3.0, 1.0)
		(rings[i] as MeshInstance3D).scale = Vector3.ONE * (.4 + ph * 2.2 * strength)
		(rings[i] as MeshInstance3D).position = Vector3(0, .04, 0)
		(rings[i] as MeshInstance3D).visible = strength > .05
	for i in bubbles.size():
		var ph := fmod(t * 1.7 + i * .37, 1.0)
		var a := i * 2.4
		(bubbles[i] as MeshInstance3D).position = Vector3(cos(a) * .5 * (1 - ph), ph * .35, sin(a) * .5 * (1 - ph))
		(bubbles[i] as MeshInstance3D).visible = strength > .05
	if arm.visible:
		var k := clampf(1.0 - timer / DRAG_SECONDS, 0, 1)
		arm.position = Vector3(0, -1.6 + 1.8 * minf(1, k * 3), 0)
		var to: Vector3 = game.player.global_position - fx.global_position
		arm.rotation.y = atan2(to.x, to.z) + PI * .5
