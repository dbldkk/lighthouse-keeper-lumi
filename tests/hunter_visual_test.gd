extends SceneTree
## Модель охотника: glb, шесть анимаций, AnimationTree, клипы по состояниям, звуки по фазам.
var game: Node
var h: Node3D
var v: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Ведём модель с заданной скоростью вручную (охотник «заморожен», чтобы ИИ не мешал).
func drive(speed: float, seconds: float, dir := Vector3(1, 0, 0)) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < seconds:
		h.body.global_position += dir * speed * dt
		h._tick_visual(dt)
		v.tree.advance(dt)
		t += dt

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_hunter_visual.json"
	game.start_shift()
	h = game.hunter
	await frames(2)
	v = h.visual
	check(v != null and v.model != null and v.model.name == "HunterModel", "Модель hunter.glb загружена вместо заглушки")
	var meshes := {}
	for m in v.model.find_children("*", "MeshInstance3D", true, false):
		meshes[String(m.name)] = m
	check(meshes.has("HunterBody") and meshes.has("HunterCloak") and meshes.has("HunterEyes") and meshes.has("HunterTeeth"), "Тело, плащ, глаза и зубы на месте")
	check(v.skeleton != null and v.skeleton.get_bone_count() >= 40, "Скелет с пальцами (%d костей)" % (v.skeleton.get_bone_count() if v.skeleton else 0))
	var all_anims := true
	for a in v.ANIMS:
		all_anims = all_anims and v.anim_player.has_animation(a)
	check(all_anims, "Есть все шесть анимаций: idle, stalk, lurch, search, grab, door_wait")
	check(v.anim_player.get_animation("stalk").loop_mode == Animation.LOOP_LINEAR and v.anim_player.get_animation("grab").loop_mode == Animation.LOOP_NONE, "Циклы зациклены, бросок — нет")
	check(v.available() and v.tree.active, "AnimationTree со state machine активен")
	var sm = v.tree.tree_root.get_node("sm")
	var xfade := 0.0
	for i in sm.get_transition_count():
		if sm.get_transition_from(i) == &"stalk" and sm.get_transition_to(i) == &"lurch":
			xfade = sm.get_transition(i).xfade_time
	check(sm is AnimationNodeStateMachine and sm.get_transition_count() == 30 and xfade > .1, "Переходы между клипами плавные (кроссфейд %.2f с)" % xfade)
	var body_mat: StandardMaterial3D = meshes["HunterBody"].material_override
	check(body_mat != null and body_mat.vertex_color_use_as_albedo and body_mat.rim_enabled and body_mat.roughness < .5, "Кожа: мокрая, вершинные цвета, rim-свет")
	var eye_mat: StandardMaterial3D = meshes["HunterEyes"].material_override
	check(eye_mat != null and eye_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Глаза светятся сами")
	var glow: Node = v.head_attach.get_node_or_null("EyeGlow") if v.head_attach else null
	check(glow is OmniLight3D, "Отблеск глаз прикреплён к кости головы")
	check(h.body.get_node_or_null("Rim") is OmniLight3D, "Контровой свет сохранён")
	# высота: ноги на земле, рост ~2.3 м
	var aabb := AABB()
	var first := true
	for m in meshes.values():
		var box: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var base_y: float = h.body.global_position.y
	check(absf(aabb.position.y - base_y) < .25 and aabb.size.y > 1.9 and aabb.size.y < 3.2, "Стоит на земле, рост %.2f м" % aabb.size.y)

	# состояния → клипы
	h.preview_freeze = true
	h.active = true
	h.body.show()
	h.space = ""
	h._set_state("patrol")
	drive(0.0, .5)
	check(v.current == "idle", "Стоит — idle")
	drive(h.PATROL_SPEED, 1.0)
	check(v.current == "stalk", "Патруль — крадущийся шаг (stalk)")
	var slow: float = v.time_scale()
	h._set_state("chase")
	drive(h.CHASE_SPEED, 1.0)
	check(v.current == "lurch", "Погоня — рваный бег (lurch)")
	check(v.time_scale() > slow, "Скорость клипа подстраивается под скорость (%.2f > %.2f)" % [v.time_scale(), slow])
	v.sounds_played.clear()
	drive(h.CHASE_SPEED, 2.0)
	check(v.sounds_played.has("hunter_step"), "Шаги звучат по фазе бега")
	h._set_state("search")
	v.sounds_played.clear()
	drive(0.0, 5.0)
	check(v.current == "search", "Поиск на месте — принюхивается (search)")
	check(v.sounds_played.has("hunter_sniff"), "Слышно принюхивание")
	h._set_state("chase")
	h.door_clock = 1.0
	v.sounds_played.clear()
	drive(0.0, 4.0)
	check(v.current == "door_wait", "У двери — ждёт и дышит (door_wait)")
	check(v.sounds_played.has("hunter_breath"), "Мокрое дыхание у двери")
	h.door_clock = 0
	drive(0.0, .5)
	check(v.current == "idle", "Отошёл от двери — снова idle")
	h._set_state("patrol")
	check(h.door_clock == 0, "Ожидание у двери сбрасывается при смене состояния")
	v.sounds_played.clear()
	v.play_grab()
	drive(0.0, .3)
	check(v.current == "grab" and v.sounds_played.has("hunter_grab") and v.sounds_played.has("hunter_crack"), "Бросок: клип grab, рёв и хруст костей")
	drive(0.0, 1.2)
	check(v.current != "grab", "После броска возвращается к обычным клипам")
	# телепорт (вход в комнату) не даёт рывка скорости
	h.body.global_position += Vector3(40, 0, 0)
	drive(0.0, .05)
	check(v.speed < 1.0, "Телепорт через дверь не включает бег")
	# превью-поза
	v.pose_for_preview("grab", .5)
	check(not v.tree.active and v.anim_player.assigned_animation == "grab", "Поза для превью ставится без дерева")
	v.resume_tree()
	check(v.tree.active, "Дерево возвращается после превью")
	# звуки существуют
	var have := true
	for n in ["hunter_step_1", "hunter_breath_1", "hunter_sniff_1", "hunter_crack_1", "hunter_grab_1"]:
		have = have and ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % n)
	check(have, "Звуки охотника лежат в assets/audio/sfx")
	h.preview_freeze = false

	print("HUNTER_VISUAL_CHECKS ", checks, " failures ", failures)
	game.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
