extends Node3D
## Модель охотника (assets/models/characters/hunter/hunter.glb, исходник — assets/source_blender/hunter/)
## и её анимации: AnimationTree со state machine (плавные переходы) + масштаб времени по скорости.
## Состояние охотника → клип: idle, stalk (крадётся), lurch (рваный бег), search (принюхивается, дёргает
## головой), grab (бросок), door_wait (у двери). К фазам клипов привязаны звуки: шаги, мокрое дыхание,
## принюхивание, хруст костей, рёв броска.
const SCENE = preload("res://assets/models/characters/hunter/hunter.glb")
const ANIMS := ["idle", "stalk", "lurch", "search", "grab", "door_wait"]
const LOOPS := ["idle", "stalk", "lurch", "search", "door_wait"]
const STALK_NATIVE := 1.3      ## м/с, при которых шаг stalk не скользит
const LURCH_NATIVE := 3.1
const LURCH_FROM := 2.8
const GRAB_SECONDS := 1.2

var hunter: Node
var model: Node3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var skeleton: Skeleton3D
var head_attach: BoneAttachment3D
var current := "idle"
var speed := 0.0
var last_pos := Vector3.ZERO
var has_last := false
var door_wait := false
var sniffing := false
var grab_time := 0.0
var last_phase := 0.0
var breath_clock := 1.2
var rng := RandomNumberGenerator.new()
var sounds_played: Array[String] = []   ## для тестов: последние звуки

func build(owner_hunter: Node) -> void:
	hunter = owner_hunter
	rng.randomize()
	model = SCENE.instantiate()
	model.name = "HunterModel"
	add_child(model)
	anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	_materials()
	if anim_player != null:
		for clip in LOOPS:
			if anim_player.has_animation(clip):
				anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_build_tree()
	if skeleton != null and skeleton.find_bone("head") >= 0:
		head_attach = BoneAttachment3D.new()
		head_attach.name = "HeadAttach"
		head_attach.bone_name = "head"
		skeleton.add_child(head_attach)

func _materials() -> void:
	var skin := StandardMaterial3D.new()
	skin.vertex_color_use_as_albedo = true
	skin.albedo_color = Color(.8, .92, 1.0)   # холоднее: утопленник, а не загар под тёплым фонарём
	skin.roughness = .42             # мокрая кожа, но не пластик
	skin.metallic_specular = .45
	skin.rim_enabled = true          # силуэт читается в темноте
	skin.rim = .8
	skin.rim_tint = .4
	var cloak := StandardMaterial3D.new()
	cloak.vertex_color_use_as_albedo = true
	cloak.roughness = .5
	cloak.metallic_specular = .55
	cloak.cull_mode = BaseMaterial3D.CULL_DISABLED
	var teeth := StandardMaterial3D.new()
	teeth.vertex_color_use_as_albedo = true
	teeth.roughness = .35
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.0, .88, .6)     # отражающие, как у зверя в свете фонаря
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		match String(m.name):
			"HunterBody": m.material_override = skin
			"HunterCloak": m.material_override = cloak
			"HunterTeeth": m.material_override = teeth
			"HunterEyes": m.material_override = eye

func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	var sm := AnimationNodeStateMachine.new()
	for i in ANIMS.size():
		var node := AnimationNodeAnimation.new()
		node.animation = ANIMS[i]
		sm.add_node(ANIMS[i], node, Vector2(200 * i, 0))
	for a in ANIMS:
		for b in ANIMS:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = .12 if b == "grab" else (.35 if a == "grab" else .28)
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			sm.add_transition(a, b, t)
	var root := AnimationNodeBlendTree.new()
	root.add_node("sm", sm, Vector2(0, 0))
	root.add_node("speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	root.connect_node("speed", 0, "sm")
	root.connect_node("output", 0, "speed")
	tree.tree_root = root
	tree.active = true
	playback = tree.get("parameters/sm/playback")
	tree.set("parameters/speed/scale", 1.0)

func available() -> bool:
	return tree != null and playback != null

## Какой клип нужен сейчас (по состоянию охотника и скорости).
func desired() -> String:
	if grab_time > 0:
		return "grab"
	if door_wait:
		return "door_wait"
	if speed >= LURCH_FROM:
		return "lurch"
	if speed > .25:
		return "stalk"
	if sniffing:
		return "search"
	return "idle"

func time_scale() -> float:
	match current:
		"lurch": return clampf(speed / LURCH_NATIVE, .8, 2.0)
		"stalk": return clampf(speed / STALK_NATIVE, .6, 1.9)
	return 1.0

func play_grab() -> void:
	grab_time = GRAB_SECONDS
	_travel("grab", true)
	_sound("hunter_grab", 0.0, .95)
	_sound("hunter_crack", -4.0, 1.0)

func tick(delta: float) -> void:
	if delta <= 0:
		return
	var p := global_position
	if has_last:
		var v := Vector2(p.x - last_pos.x, p.z - last_pos.z).length() / delta
		if v > 20.0:       # телепорт (вход в комнату)
			v = 0.0
		speed = lerpf(speed, v, 1.0 - exp(-delta * 10.0))
	last_pos = p
	has_last = true
	grab_time = maxf(0.0, grab_time - delta)
	if not available():
		return
	var want := desired()
	if want != current:
		_travel(want)
	tree.set("parameters/speed/scale", time_scale())
	_phase_sounds(delta)

func _travel(anim: String, restart := false) -> void:
	current = anim
	last_phase = 0.0
	if restart:
		playback.start(anim, true)
	else:
		playback.travel(anim)

func phase() -> float:
	if not available():
		return 0.0
	var length := playback.get_current_length()
	return fposmod(playback.get_current_play_position() / length, 1.0) if length > 0 else 0.0

func _crossed(a: float, b: float, mark: float) -> bool:
	if b >= a:
		return a < mark and mark <= b
	return mark > a or mark <= b       # переход через конец цикла

func _phase_sounds(delta: float) -> void:
	var ph := phase()
	var prev := last_phase
	last_phase = ph
	match current:
		"stalk", "lurch":
			var loud := current == "lurch"
			for mark in [0.02, 0.52]:
				if _crossed(prev, ph, mark):
					_sound("hunter_step", -1.0 if loud else -8.0, rng.randf_range(.9, 1.06))
					if loud and rng.randf() < .12:
						_sound("hunter_crack", -9.0, rng.randf_range(.9, 1.1))
		"search":
			for k in 5:
				if _crossed(prev, ph, k * .2 + .02) and rng.randf() < .7:
					_sound("hunter_crack", -6.0, rng.randf_range(.85, 1.1))
			for mark in [.12, .55]:
				if _crossed(prev, ph, mark):
					_sound("hunter_sniff", -5.0, rng.randf_range(.85, 1.0))
		"idle", "door_wait":
			breath_clock -= delta
			if breath_clock <= 0:
				breath_clock = rng.randf_range(2.6, 3.4)
				_sound("hunter_breath", -6.0 if current == "door_wait" else -9.0, rng.randf_range(.85, 1.0))
			if current == "door_wait" and rng.randf() < delta * .35:
				_sound("hunter_crack", -12.0, rng.randf_range(1.0, 1.2))

func _sound(name: String, volume_db: float, pitch: float) -> void:
	sounds_played.append(name)
	if sounds_played.size() > 24:
		sounds_played.pop_front()
	var game = hunter.game if hunter != null else null
	if game == null or not is_instance_valid(game.sound):
		return
	var listener: Vector3 = game.player.global_position
	if global_position.distance_to(listener) > 34.0:
		return
	game.sound.sfx(name, volume_db, pitch, global_position + Vector3.UP * 1.6)

## Для превью и тестов: поставить конкретную позу без AnimationTree.
func pose_for_preview(anim: String, at_seconds: float) -> void:
	if anim_player == null:
		return
	if tree != null:
		tree.active = false
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	anim_player.play(anim)
	anim_player.seek(at_seconds, true)
	anim_player.pause()

func resume_tree() -> void:
	if tree != null:
		anim_player.stop()
		tree.active = true

func _exit_tree() -> void:
	# AnimationTree, созданный из кода, держит циклические ссылки на узлы графа — разрываем их явно.
	playback = null
	if tree != null:
		tree.active = false
		tree.tree_root = null
