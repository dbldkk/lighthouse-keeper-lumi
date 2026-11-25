extends SceneTree
## Model before/after renders. godot --path . --script res://tools/model_compare.gd -- /abs/model.glb /abs/out prefix
var cam: Camera3D
var model_path := ""
var out := ""
var prefix := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	model_path = a[0]; out = a[1]; prefix = a[2]
	call_deferred("run")

func shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(prefix + name + ".png"))
	print("Captured ", prefix + name)

func look(target: Vector3, yaw_deg: float, dist: float, h: float, fov := 30.0) -> void:
	var y := deg_to_rad(yaw_deg)
	cam.fov = fov
	cam.global_position = target + Vector3(sin(y) * dist, h, cos(y) * dist)
	cam.look_at(target, Vector3.UP)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var w := Node3D.new(); root.add_child(w)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.42, .44, .46)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.6, .6, .62)
	env.environment.ambient_light_energy = .7
	w.add_child(env)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 30, 0); key.light_energy = 1.25; w.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-15, -60, 0); fill.light_energy = .35; w.add_child(fill)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(6, 6); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(.32, .33, .35); floor.material_override = fm; w.add_child(floor)
	cam = Camera3D.new(); w.add_child(cam); cam.current = true
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	if doc.append_from_file(model_path, st) != OK:
		push_error("load failed"); quit(1); return
	var model := doc.generate_scene(st) as Node3D
	w.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and m.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR:
				mat.vertex_color_use_as_albedo = true
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := model.find_child("*", true, false)
	for n in model.find_children("*", "Skeleton3D", true, false):
		skel = n
	var poses := [["idle", .5, 0, "front"], ["idle", .5, 90, "side"], ["idle", .5, 180, "back"],
		["cast", .4, 35, "3q"], ["interact", .35, 35, "3q"], ["run", .15, 35, "3q"], ["walk", .2, 90, "side"],
		["lantern", .35, 90, "side"], ["lantern", .35, 35, "3q"], ["lantern", .5, 90, "side"]]
	for p in poses:
		ap.play(p[0], 0); ap.seek(p[1], true); ap.advance(0)
		look(Vector3(0, .95, 0), p[2], 4.3, .25)
		await shot("%s_%.2f_%s" % [p[0], p[1], p[3]])
	# arm close-ups for the skinning
	for p in [["cast", .4], ["interact", .35], ["run", .15], ["lantern", .35]]:
		ap.play(p[0], 0); ap.seek(p[1], true); ap.advance(0)
		var hand := (skel as Skeleton3D).get_bone_global_pose((skel as Skeleton3D).find_bone("Forearm.R")).origin
		look(hand + Vector3(0, 0, 0), 40, 1.25, .1)
		await shot("arm_%s" % p[0])
	ap.play("idle", 0); ap.seek(.5, true); ap.advance(0)
	look(Vector3(0, 1.66, 0), 0, .9, .02)
	await shot("face_front")
	look(Vector3(0, 1.64, 0), 30, 1.3, .05)
	await shot("face_3q")
	quit()
