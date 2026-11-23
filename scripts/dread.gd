extends Node
## Мрак: общий «страшный» слой поверх освещения и режиссёра ужаса (scares.gd).
##  * экран: видимость вокруг смотрителя (тёмное тонет во мраке, свет пробивает), клочья тумана,
##    зерно, цветокоррекция и короткие сбои кадра — параметры шейдера screen_atmosphere;
##  * свет: мерцание ламп в помещениях и у построек, редкие провалы и «отключения»;
##  * звук: далёкие скрипы, стуки и стоны вокруг, чаще при высоком напряжении;
##  * следы прошлого: борозды у крыльца, волочащийся след к воде, мёртвые чайки, круг свечей,
##    записки и надписи — короткая строка при первом приближении.
## Все числа — в balance.gd, раздел «мрак».
const BAL = preload("res://scripts/balance.gd")
const Geo = preload("res://scripts/geometry.gd")

var game: Node
var rng := RandomNumberGenerator.new()
var clock := 0.0
var glitch := 0.0
var blackout_time := 0.0
var ambient_clock := 12.0
var lights: Array = []          ## {"light": OmniLight3D, "base": float, "seed": float}
var lights_clock := 0.0
var props_root: Node3D
var stories: Array = []         ## {"at": Vector3, "radius": float, "text": String, "id": String}
var found := {}
var sight := 1.0
var level := 0.0                ## 0 — светлый день, 1 — глухая ночь
var gulls: Array[Node3D] = []

func _init() -> void:
	rng.randomize()

func reset() -> void:
	found.clear()
	glitch = 0
	blackout_time = 0
	ambient_clock = BAL.DREAD_AMBIENT_GAP_MAX

func running() -> bool:
	return is_instance_valid(game) and game.playing and not game.paused and not game.finished

func night_amount() -> float:
	return clampf(float(game.coastal_life.night_strength), 0, 1) if is_instance_valid(game.coastal_life) else 0.0

func indoors() -> bool:
	return game.lighthouse_interior.active or not game.building_interiors.active.is_empty()

# ---------------------------------------------------------------- экран
## Короткий сбой кадра: рвутся строки, расходятся каналы. Используется пугалками.
func glitch_pulse(strength := .6) -> void:
	glitch = maxf(glitch, strength)

func blackout(seconds: float) -> void:
	blackout_time = maxf(blackout_time, seconds)
	game.sound.sfx("tick", -8, .6)

func target_sight() -> float:
	if not game.playing:
		return 0.9
	if indoors():
		return 3.0
	var night := night_amount()
	var day_sight := BAL.DREAD_SIGHT_DAY
	var night_sight := BAL.DREAD_SIGHT_LANTERN if game.player.lantern_on else BAL.DREAD_SIGHT_DARK
	var s := lerpf(day_sight, night_sight, night)
	if is_instance_valid(game.island_events) and game.island_events.current == "fog":
		s = minf(s, BAL.DREAD_SIGHT_FOG)
	if game.lighthouse_on and game.is_safe(game.player.position):
		s *= 1.25
	return s * (1.0 - float(game.scares.tension) * .18)

func _update_screen(delta: float) -> void:
	var mat: ShaderMaterial = game.hud.atmosphere.material
	if mat == null:
		return
	var night := night_amount()
	level = lerpf(BAL.DREAD_DAY_LEVEL, 1.0, night)
	if not game.playing:
		level = .9
	elif indoors():
		level *= .7
	sight = move_toward(sight, target_sight(), delta * .6)
	var view: Vector2 = game.get_viewport().get_visible_rect().size
	var focus := Vector2(.5, .5)
	if game.playing and is_instance_valid(game.camera) and view.x > 0:
		var p: Vector2 = game.camera.unproject_position(game.player.global_position + Vector3.UP * .8)
		focus = Vector2(clampf(p.x / view.x, 0, 1), clampf(p.y / view.y, 0, 1))
	var mist := lerpf(BAL.DREAD_MIST_DAY, BAL.DREAD_MIST_NIGHT, night)
	if is_instance_valid(game.island_events) and game.island_events.current == "fog":
		mist = maxf(mist, .9)
	if indoors():
		mist = 0.0
	# При низком рассудке кадр иногда «сбоит» сам.
	if running() and game.sanity < BAL.SANITY_HALLUCINATE_AT and rng.randf() < delta * BAL.DREAD_GLITCH_RATE * (1.0 - game.sanity / BAL.SANITY_HALLUCINATE_AT):
		glitch_pulse(rng.randf_range(.3, .7))
	glitch = move_toward(glitch, 0, delta * 3.5)
	mat.set_shader_parameter("dread", level)
	mat.set_shader_parameter("sight", sight)
	mat.set_shader_parameter("focus", focus)
	mat.set_shader_parameter("mist", mist)
	mat.set_shader_parameter("glitch", glitch)
	mat.set_shader_parameter("menu", 0.0 if game.playing else 1.0)

# ---------------------------------------------------------------- свет
func _collect_lights() -> void:
	lights = lights.filter(func(e): return is_instance_valid(e.light))
	var known := {}
	for e in lights:
		known[e.light] = true
	var candidates: Array = []
	if is_instance_valid(game.building_interiors):
		candidates.append_array(game.building_interiors.find_children("*", "OmniLight3D", true, false))
	if is_instance_valid(game.lighthouse_interior):
		candidates.append_array(game.lighthouse_interior.lamps)
	for path in ["PathLantern", "CabinWindowGlow", "IslandGeometry/KeeperCabin/EntryLanternLight"]:
		var n: Node = game.world.get_node_or_null(path)
		if n is OmniLight3D:
			candidates.append(n)
	for l in candidates:
		if l is OmniLight3D and not known.has(l):
			lights.append({"light": l, "base": l.light_energy, "seed": rng.randf() * 100.0})

## Множитель мерцания для лампы с номером/зерном seed: 1 — ровно, 0 — погасла.
func flicker(seed: float) -> float:
	if blackout_time > 0:
		return .04
	var t := clock * (1.0 + float(game.scares.tension))
	var n := .5 + .5 * sin(t * 13.0 + seed) * sin(t * 3.7 + seed * 1.3)
	var amount := BAL.DREAD_FLICKER * lerpf(.4, 1.0, night_amount())
	var f := 1.0 - amount * n * n
	# редкий провал на долю секунды
	if fmod(t * .21 + seed, 7.3) < .09 * (1.0 + float(game.scares.tension) * 2.0):
		f *= .15
	return clampf(f, 0, 1)

func _update_lights(delta: float) -> void:
	lights_clock -= delta
	if lights_clock <= 0:
		lights_clock = 3.0
		_collect_lights()
	for e in lights:
		if is_instance_valid(e.light):
			e.light.light_energy = float(e.base) * flicker(float(e.seed))

# ---------------------------------------------------------------- звук вокруг
func _update_ambient(delta: float) -> void:
	if not running():
		return
	ambient_clock -= delta * (1.0 + float(game.scares.tension) * 1.5 + night_amount() * .6)
	if ambient_clock > 0:
		return
	ambient_clock = rng.randf_range(BAL.DREAD_AMBIENT_GAP_MIN, BAL.DREAD_AMBIENT_GAP_MAX)
	var pool := ["creak", "knock_far", "groan"]
	if night_amount() > .5:
		pool.append_array(["whisper", "creak", "knock_far"])
	var angle := rng.randf() * TAU
	var at: Vector3 = game.player.global_position + Vector3(cos(angle), .5, sin(angle)) * rng.randf_range(12, 26)
	game.sound.sfx(pool[rng.randi_range(0, pool.size() - 1)], BAL.DREAD_AMBIENT_DB, rng.randf_range(.8, 1.0), at)

# ---------------------------------------------------------------- следы прошлого
func ensure_props() -> void:
	if is_instance_valid(props_root) or not is_instance_valid(game.night_raids):
		return
	props_root = Node3D.new()
	props_root.name = "DreadProps"
	game.world.add_child(props_root)
	stories.clear()
	gulls.clear()
	var claws := _decal_texture("claws")
	var blood := _decal_texture("blood")
	var paper := _decal_texture("paper")
	# борозды у крыльца хижины
	_ground_decal(Vector3(5.6, 0, 5.6), Vector2(1.6, 1.2), claws, .3)
	_ground_decal(Vector3(4.3, 0, 6.3), Vector2(1.3, 1.0), claws, -.5)
	_story("claws", Vector3(5.0, 1, 5.8), 2.6, "Глубокие борозды в земле у крыльца — будто кто-то тащил когти к двери. Следы обрываются у порога.")
	# волочащийся след к причалу
	for i in 7:
		var p := Vector3(13.5, 0, 3.8).lerp(Vector3(21.5, 0, 5.0), i / 6.0) + Vector3(0, 0, sin(i * 1.3) * .35)
		_ground_decal(p, Vector2(1.3, .8), blood, .14 + rng.randf_range(-.2, .2), .8 - i * .06)
	_story("trail", Vector3(16.5, 1, 4.3), 2.8, "Тёмный волочащийся след тянется к причалу и уходит в воду.")
	# мёртвые чайки
	for at in [Vector3(18.5, 0, 1.5), Vector3(12.5, 0, -11.5), Vector3(-2.5, 0, 9.0)]:
		var bird := _dead_bird(at)
		if bird != null:
			gulls.append(bird)
	_story("gulls", Vector3(18.5, 1, 1.5), 2.4, "Мёртвые чайки. Ни ран, ни перьев вокруг — только пустые глазницы.")
	# записка у колодца
	_ground_decal(Vector3(2.7, 0, -20.4), Vector2(.5, .6), paper, .4)
	_story("well", Vector3(2.4, 1, -20.8), 2.2, "Записка прежнего смотрителя: «Не пей из колодца после полуночи. Вода отвечает, когда в неё смотришь».")
	# надпись у маяка
	_ground_decal(Vector3(-6.7, 0, -4.6), Vector2(1.4, .7), _decal_texture("words"), -.3)
	_story("words", Vector3(-6.9, 1, -4.8), 2.2, "На камне у маяка нацарапано: НЕ ГАСИ СВЕТ. НЕ ГАСИ. НЕ ГАСИ.")
	# круг свечей у валежника на севере
	_candles(Vector3(-4.0, 0, -24.5))
	_story("candles", Vector3(-4.0, 1, -24.5), 2.4, "Круг из оплывших свечей. Воск ещё тёплый.")
	# разбитый фонарь у каменоломни
	_broken_lantern(Vector3(9.8, 0, -13.8))
	_story("lantern", Vector3(9.8, 1, -13.8), 2.0, "Разбитый фонарь прежней смены. Стекло изнутри в копоти — и в отпечатках пальцев.")

func _story(id: String, at: Vector3, radius: float, text: String) -> void:
	stories.append({"id": id, "at": at, "radius": radius, "text": text})

func _update_stories() -> void:
	if not running() or indoors():
		return
	var p: Vector3 = game.player.global_position
	for s in stories:
		if found.has(s.id):
			continue
		if Vector2(p.x - s.at.x, p.z - s.at.z).length() <= float(s.radius):
			found[s.id] = true
			game.notify(String(s.text), 6.5, 1)
			game.sanity = maxf(0, game.sanity - BAL.DREAD_STORY_SANITY)
			game.sound.sfx("creak", -14, .8)
			glitch_pulse(.25)

func _ground(at: Vector3) -> Variant:
	var hit: Variant = game.night_raids.ground_at(at)
	return null if hit == null else (hit as Vector3) - Vector3(0, .35, 0)

func _ground_decal(at: Vector3, size: Vector2, tex: Texture2D, yaw: float, alpha := 1.0) -> void:
	var g: Variant = _ground(at)
	if g == null:
		return
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	quad.orientation = PlaneMesh.FACE_Y
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(mesh)
	mesh.global_position = (g as Vector3) + Vector3(0, .03, 0)
	mesh.rotation.y = yaw

func _decal_texture(kind: String) -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind)
	match kind:
		"claws":
			for k in 4:
				var x0 := 30.0 + k * 18.0
				for y in range(10, 118):
					var x := x0 + sin(y * .05 + k) * 6.0 + (y - 10) * .12
					var w := 2.5 * (1.0 - absf(y - 64.0) / 64.0) + .6
					for dx in range(-3, 4):
						var a := clampf(1.0 - absf(dx) / w, 0, 1)
						if a > 0:
							img.set_pixel(clampi(int(x) + dx, 0, size - 1), y, Color(.05, .035, .025, a * .9))
		"blood":
			for b in 22:
				var c := Vector2(r.randf_range(20, 108), 64 + r.randf_range(-18, 18))
				var rad := r.randf_range(4, 16)
				for y in range(int(c.y - rad), int(c.y + rad)):
					for x in range(int(c.x - rad), int(c.x + rad)):
						if x < 0 or y < 0 or x >= size or y >= size:
							continue
						var d := Vector2(x, y).distance_to(c) / rad
						if d < 1.0:
							var old := img.get_pixel(x, y)
							img.set_pixel(x, y, Color(.22, .02, .02, maxf(old.a, (1.0 - d * d) * .85)))
		"paper":
			for y in range(16, 112):
				for x in range(24, 104):
					var torn := x > 96 and (y * 7 + x) % 11 < 4
					if not torn:
						var line := (y - 28) % 9 == 0 and y > 26 and y < 100 and x > 32 and x < 92 + (y % 5) * 2
						img.set_pixel(x, y, Color(.12, .1, .09, .95) if line else Color(.72, .68, .58, .95))
		"words":
			# грубые процарапанные штрихи, похожие на буквы
			for k in 9:
				var x0 := 10 + k * 12
				for s in 3:
					var a := Vector2(x0 + r.randf_range(0, 8), 40 + r.randf_range(0, 40))
					var b := a + Vector2(r.randf_range(-6, 8), r.randf_range(-24, 24))
					for t in 24:
						var p := a.lerp(b, t / 23.0)
						for dx in range(-1, 2):
							var px := clampi(int(p.x) + dx, 0, size - 1)
							var py := clampi(int(p.y), 0, size - 1)
							img.set_pixel(px, py, Color(.75, .72, .66, .85))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _dead_bird(at: Vector3) -> Node3D:
	var g: Variant = _ground(at)
	if g == null:
		return null
	var root := Node3D.new()
	root.name = "DeadGull"
	props_root.add_child(root)
	root.global_position = g
	root.rotation.y = rng.randf() * TAU
	var grey := Color(.55, .56, .55)
	Geo.sphere(root, "Body", Vector3(0, .08, 0), Vector3(.22, .12, .38), grey)
	Geo.sphere(root, "Head", Vector3(0, .07, .24), Vector3(.11, .1, .12), grey)
	var wing_l := Geo.box(root, "WingL", Vector3(-.2, .04, 0), Vector3(.34, .02, .2), Color(.4, .41, .42))
	wing_l.rotation.z = .25
	var wing_r := Geo.box(root, "WingR", Vector3(.2, .03, .02), Vector3(.32, .02, .18), Color(.4, .41, .42))
	wing_r.rotation.z = -.4
	Geo.sphere(root, "Eye", Vector3(.035, .1, .29), Vector3(.025, .025, .02), Color(.02, .0, .0))
	_ground_decal(at + Vector3(.05, 0, .1), Vector2(.6, .5), _decal_texture("blood"), rng.randf() * TAU, .55)
	return root

func _candles(at: Vector3) -> void:
	for i in 7:
		var a := i * TAU / 7
		var p: Variant = _ground(at + Vector3(cos(a), 0, sin(a)) * 1.1)
		if p == null:
			continue
		var h := rng.randf_range(.08, .22)
		Geo.cylinder(props_root, "Candle", (p as Vector3) + Vector3(0, h * .5, 0), .045, h, Color(.78, .74, .62))
		if i % 3 == 0:
			var flame := OmniLight3D.new()
			flame.light_color = Color("ff9a4a")
			flame.light_energy = .5
			flame.omni_range = 1.6
			props_root.add_child(flame)
			flame.global_position = (p as Vector3) + Vector3(0, h + .1, 0)
			lights.append({"light": flame, "base": .5, "seed": rng.randf() * 100.0})
	_ground_decal(at, Vector2(2.4, 2.4), _decal_texture("claws"), 1.2, .5)

func _broken_lantern(at: Vector3) -> void:
	var g: Variant = _ground(at)
	if g == null:
		return
	var body := Geo.cylinder(props_root, "BrokenLantern", (g as Vector3) + Vector3(0, .12, 0), .12, .3, Color(.18, .17, .15))
	body.rotation.z = PI * .5
	for i in 6:
		Geo.box(props_root, "Shard", (g as Vector3) + Vector3(rng.randf_range(-.4, .4), .01, rng.randf_range(-.4, .4)), Vector3(.06, .01, .04), Color(.6, .65, .62))

## «Предмет сдвинулся»: мёртвая чайка, которую смотритель давно не видел, оказывается ближе.
func displace_gull() -> bool:
	var p: Vector3 = game.player.global_position
	for bird in gulls:
		if is_instance_valid(bird) and bird.global_position.distance_to(p) > 14:
			var angle := rng.randf() * TAU
			var g: Variant = _ground(p + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(6, 8))
			if g != null:
				bird.global_position = g
				bird.rotation.y = rng.randf() * TAU
				return true
	return false

# ---------------------------------------------------------------- кадр
func _process(delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.hud):
		return
	clock += delta
	blackout_time = maxf(0, blackout_time - delta)
	if game.playing:
		ensure_props()
	_update_screen(delta)
	_update_lights(delta)
	_update_ambient(delta)
	_update_stories()
