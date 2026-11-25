extends SceneTree
## v1.3.2: правки модели смотрителя (на основе модели v1.3.1): веса рук, фонарь в руке, лицо, цвета, подсветка ночью.
const VISUAL = preload("res://scripts/character_visual.gd")
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

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var model: Node3D = VISUAL.install(holder, "keeper")
	check(model != null, "Keeper model loads")
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var decal := model.find_child("FaceDecal", true, false) as MeshInstance3D
	var lantern := model.find_child("OilLantern", true, false) as MeshInstance3D
	var skel: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		skel = n
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(body != null and decal != null and lantern != null and skel != null and ap != null, "Body, face decal, lantern, skeleton and animations are present")
	check(body.mesh.get_surface_count() == 1 and (body.mesh.surface_get_material(0) as BaseMaterial3D).vertex_color_use_as_albedo, "Body keeps one surface with painted vertex colours")
	# лицо: декаль на кости Head, с текстурой и прозрачностью
	var dm := decal.mesh.surface_get_material(0) as BaseMaterial3D
	check(dm != null and dm.albedo_texture != null and dm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "Face decal has a texture with transparency")
	var darr := decal.mesh.surface_get_arrays(0)
	var dbones: PackedInt32Array = darr[Mesh.ARRAY_BONES]
	var head_bind := -1
	for i in decal.skin.get_bind_count():
		if decal.skin.get_bind_name(i) == &"Head":
			head_bind = i
	var all_head := head_bind >= 0
	for k in range(0, dbones.size(), 4):
		all_head = all_head and dbones[k] == head_bind
	check(all_head, "Face decal is bound entirely to the Head bone")
	# веса рук: на кистях/предплечьях нет таза и позвоночника
	var arr := body.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var names := {}
	for i in body.skin.get_bind_count():
		names[i] = String(body.skin.get_bind_name(i))
	var bad := 0
	var arm_verts := 0
	var per := bones.size() / (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var has_arm := false
		var has_torso := false
		for k in per:
			var w := weights[v * per + k]
			if w < .05:
				continue
			var n: String = names.get(bones[v * per + k], "")
			if n.begins_with("Forearm") or n.begins_with("Hand"):
				has_arm = true
			if n == "Pelvis" or n == "Spine":
				has_torso = true
		if has_arm:
			arm_verts += 1
			if has_torso:
				bad += 1
	check(arm_verts > 2000 and bad < arm_verts * .01, "Forearm/hand vertices carry no pelvis/spine weight (%d of %d)" % [bad, arm_verts])
	# фонарь: ручка остаётся в ладони во всём клипе «lantern»
	var hand := skel.find_bone("Hand.R")
	var lb := skel.find_bone("Lantern")
	var aabb := lantern.mesh.get_aabb()
	var top_world := Vector3(aabb.get_center().x, aabb.end.y - .012, aabb.get_center().z)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.play("idle", 0); ap.seek(0, true); ap.advance(0)
	var grip_l := skel.get_bone_global_rest(lb).affine_inverse() * top_world
	var grip_h0 := skel.get_bone_global_rest(hand).affine_inverse() * top_world
	var worst := 0.0
	var clip := ap.get_animation("lantern")
	var t := 0.0
	while t <= clip.length:
		ap.play("lantern", 0); ap.seek(t, true); ap.advance(0)
		var gh := skel.get_bone_global_pose(hand).affine_inverse() * (skel.get_bone_global_pose(lb) * grip_l)
		worst = maxf(worst, gh.distance_to(grip_h0))
		t += .05
	check(worst < .02, "Lantern handle stays in the palm through the raise clip (max drift %.3f m)" % worst)
	# пальто светлее (серо-зелёное), а не почти чёрное
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sum := Color(0, 0, 0)
	var n_coat := 0
	for v in verts.size():
		var p := verts[v]
		if p.z < -.12 and p.y > .8 and p.y < 1.4:
			sum += cols[v]
			n_coat += 1
	sum = sum / maxf(1, n_coat)
	check(n_coat > 500 and sum.g > .1 and sum.g >= sum.r and sum.g >= sum.b, "Coat back is lifted to grey-green (avg %.3f %.3f %.3f)" % [sum.r, sum.g, sum.b])
	# подсветка смотрителя ночью
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_keeper_model.json"
	game.start_shift()
	await process_frame
	game.hour = 12.0
	game.update_atmosphere()
	var day_e: float = game.player.fill_light.light_energy
	game.hour = 23.0
	game.update_atmosphere()
	check(day_e < .05 and game.player.fill_light.light_energy > .9 and game.player.rim_light.light_energy > 1.0, "Soft fill/rim light on the keeper only at night")
	print("KEEPER_MODEL_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
