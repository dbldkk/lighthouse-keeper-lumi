extends Node3D
## Охотник читается ночью издалека, но не превращается в мультяшку:
## - отблеск глаз (две маленькие точки, иногда моргают; чем дальше — тем заметнее);
## - фонарь «ловит» его: тёплый свет на лице и груди, когда он в луче или в круге фонаря;
## - отражение на воде: дрожащие полосы глаз и бледный силуэт, если между ним и камерой вода.
const EYE_COLOR := Color(1.0, .82, .5)
const CATCH_RANGE := 13.0          ## дальше этого фонарь его не достаёт
const BEAM_BONUS := 1.0            ## в луче (ПКМ) — ярче
const NEAR_SIZE := .13             ## размер отблеска вблизи, м
const FAR_SIZE := .3               ## и издалека

var hunter: Node
var visual: Node3D
var glints: Array[MeshInstance3D] = []
var reflections: Array[MeshInstance3D] = []
var silhouette: MeshInstance3D
var catch_light: OmniLight3D
var catch_level := 0.0             ## 0..1 — насколько его освещает фонарь смотрителя
var glint_size := NEAR_SIZE
var reflection_visible := false
var blink := 0.0
var blink_clock := 5.0
var eye_offsets: Array[Vector3] = []
var rng := RandomNumberGenerator.new()
var time := 0.0
var overlay: Control               ## точки глаз поверх ночной темноты экрана (но под интерфейсом)
var overlay_points: Array = []     ## [позиция на экране, сила 0..1]
var overlay_visible := false

func _init() -> void:
	rng.randomize()

func build(owner_hunter: Node, model_visual: Node3D) -> void:
	hunter = owner_hunter
	visual = model_visual
	name = "Presence"
	_find_eyes()
	var tex := _dot_texture()
	for i in 2:
		var g := _quad(tex, EYE_COLOR, 1.0, true)
		g.name = "EyeGlint%d" % i
		if visual.head_attach != null:
			visual.head_attach.add_child(g)
		else:
			hunter.body.add_child(g)
		g.position = eye_offsets[i]
		glints.append(g)
		var r := _quad(tex, EYE_COLOR, .55, true)
		r.name = "EyeReflection%d" % i
		add_child(r)
		r.top_level = true
		r.hide()
		reflections.append(r)
	silhouette = _quad(_streak_texture(), Color(.62, .7, .72), .16, false)
	silhouette.name = "WaterSilhouette"
	add_child(silhouette)
	silhouette.top_level = true
	silhouette.hide()
	catch_light = OmniLight3D.new()
	catch_light.name = "LanternCatch"
	catch_light.light_color = Color("ffc98a")
	catch_light.light_energy = 0
	catch_light.omni_range = 3.2
	catch_light.shadow_enabled = false
	hunter.body.add_child(catch_light)

## Где глаза относительно кости головы (по мешу HunterEyes в позе покоя).
func _find_eyes() -> void:
	eye_offsets = [Vector3(-.06, .05, .2), Vector3(.06, .05, .2)]
	if visual.model == null or visual.head_attach == null:
		return
	var eyes: MeshInstance3D = visual.model.find_child("HunterEyes", true, false)
	if eyes == null:
		return
	var box: AABB = eyes.get_aabb()
	var head_inv: Transform3D = visual.head_attach.global_transform.affine_inverse()
	var to_world: Transform3D = eyes.global_transform
	var half := box.size.x * .25
	for i in 2:
		var local := box.get_center() + Vector3((-1 if i == 0 else 1) * half, 0, 0)
		var p: Vector3 = head_inv * (to_world * local)
		eye_offsets[i] = p + (head_inv.basis * (to_world.basis * Vector3(0, 0, .02)))

func _dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, .35), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0, .25, 1])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(.5, .5)
	t.fill_to = Vector2(1, .5)
	t.width = 64
	t.height = 64
	return t

func _streak_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, .9), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(.5, .5)
	t.fill_to = Vector2(1, .5)
	t.width = 32
	t.height = 128
	return t

func _quad(tex: Texture2D, color: Color, alpha: float, additive: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func _ocean_y() -> float:
	var ocean: Node3D = hunter.game.world.get_node_or_null("Ocean") if hunter.game != null else null
	return ocean.global_position.y if ocean != null else 0.0

func night_factor() -> float:
	var g = hunter.game
	if g == null:
		return 1.0
	return 1.0 if g.is_night() else .25

func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	var hud = hunter.game.hud if hunter.game != null else null
	if hud == null or hud.root == null or hud.atmosphere == null:
		return
	overlay = Control.new()
	overlay.name = "HunterEyesOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	hud.root.add_child(overlay)
	hud.root.move_child(overlay, hud.atmosphere.get_index() + 1)

func clear() -> void:
	overlay_points.clear()
	overlay_visible = false
	catch_level = 0
	if catch_light != null:
		catch_light.light_energy = 0
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_redraw()

func _draw_overlay() -> void:
	var g = hunter.game
	if g == null or g.paused or g.hud.menu.visible or not hunter.body.visible:
		return
	for pt in overlay_points:
		var at: Vector2 = pt[0]
		var k: float = pt[1]
		overlay.draw_circle(at, 10.0, Color(1, .6, .28, .05 * k))
		overlay.draw_circle(at, 5.2, Color(1, .7, .38, .16 * k))
		overlay.draw_circle(at, 2.7, Color(1, .85, .58, .8 * k))
		overlay.draw_circle(at, 1.4, Color(1, .97, .85, 1.0 * k))

## Глаза видны издалека сквозь ночную темноту экрана, если их ничто не заслоняет.
func _update_overlay(d: float, open: float, night: float) -> void:
	_ensure_overlay()
	overlay_points.clear()
	overlay_visible = false
	var g = hunter.game
	if overlay != null and hunter.body.visible and night > .5 and open > 0 and g.playing and not g.paused and not g.hud.menu.visible:
		var cam: Camera3D = g.camera
		var space: PhysicsDirectSpaceState3D = hunter.get_world_3d().direct_space_state
		var back := cam.global_transform.basis.z
		var k := clampf((d - 3.0) / 6.0, .35, 1.0) * (.8 + .2 * sin(time * 2.3))
		# густой туман особой ночи прячет глаза дальше ~9 м — он выходит из молока вплотную
		var fog: float = g.night_events.fog_strength() if "night_events" in g and is_instance_valid(g.night_events) else 0.0
		k *= lerpf(1.0, clampf(1.0 - (d - 6.0) / 3.0, 0, 1), fog)
		for gl in glints:
			var eye: Vector3 = gl.global_position
			if cam.is_position_behind(eye):
				continue
			var q := PhysicsRayQueryParameters3D.create(eye + back * .15, eye + back * 45.0)
			q.collision_mask = 1
			if not space.intersect_ray(q).is_empty():
				continue
			overlay_points.append([cam.unproject_position(eye), k])
		if k <= .01:
			overlay_points.clear()
		overlay_visible = not overlay_points.is_empty()
	if overlay != null:
		overlay.queue_redraw()

func tick(delta: float) -> void:
	time += delta
	var g = hunter.game
	if g == null or not is_instance_valid(g.player):
		return
	var here: Vector3 = hunter.body.global_position
	var p: Vector3 = g.player.global_position
	var d := Vector2(p.x - here.x, p.z - here.z).length()
	var night := night_factor()
	# моргание
	blink_clock -= delta
	if blink_clock <= 0:
		blink = .16
		blink_clock = rng.randf_range(3.5, 8.5)
	blink = maxf(0, blink - delta)
	var open := 0.0 if blink > 0 else 1.0
	glint_size = lerpf(NEAR_SIZE, FAR_SIZE, clampf((d - 4.0) / 14.0, 0, 1))
	var pulse := .85 + .15 * sin(time * 2.3)
	for gl in glints:
		gl.visible = hunter.body.visible and night > .5
		gl.scale = Vector3(glint_size, glint_size * open, 1) * pulse
	_update_overlay(d, open, night)
	# фонарь ловит его
	var want := 0.0
	if g.player.lantern_on and d < CATCH_RANGE:
		var fwd: Vector3 = Vector3(0, 0, 1).rotated(Vector3.UP, g.player.get_node("Visual").rotation.y)
		var to := Vector3(here.x - p.x, 0, here.z - p.z).normalized()
		var facing := clampf((fwd.dot(to) + .2) / 1.2, 0, 1)
		want = facing * clampf(1.0 - (d - 3.0) / (CATCH_RANGE - 3.0), 0, 1)
	if is_instance_valid(g.lantern_beam) and g.lantern_beam.focusing and g.lantern_beam.in_cone(here + Vector3.UP):
		want = minf(1.0, want + BEAM_BONUS)
	catch_level = move_toward(catch_level, want * night, delta * 2.5)
	catch_light.light_energy = 1.7 * catch_level
	var toward := Vector3(p.x - here.x, 0, p.z - here.z)
	if toward.length() > .1:
		catch_light.global_position = here + toward.normalized() * 1.1 + Vector3.UP * 1.7
	# отражение на воде — между ним и камерой
	reflection_visible = false
	if hunter.body.visible and night > .5:
		var cam_dir := Vector3(29, 0, 40).normalized()
		var water_y := _ocean_y()
		for step in [1.2, 2.2, 3.4]:
			var probe: Vector3 = here + cam_dir * step
			if g.night_raids.ground_at(probe) == null and here.y - water_y < 4.0:
				reflection_visible = true
				var wob := sin(time * 3.1) * .03
				for i in 2:
					var eye: Vector3 = glints[i].global_position
					var r := reflections[i]
					r.global_position = Vector3(eye.x, water_y + .03, eye.z) + cam_dir * step + Vector3(wob, 0, 0)
					r.scale = Vector3(glint_size * .9, glint_size * 3.2 * open, 1)
				silhouette.global_position = Vector3(here.x, water_y + .02, here.z) + cam_dir * (step + .3)
				silhouette.scale = Vector3(.9, 2.4 + sin(time * 1.7) * .12, 1)
				break
	for r in reflections:
		r.visible = reflection_visible
	silhouette.visible = reflection_visible
