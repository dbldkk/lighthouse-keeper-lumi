extends SceneTree
## Скриншоты v1.3. godot --path . --script res://tools/preview_v7.gd -- /abs/dir [раздел]
var out := "/tmp/v7"
var only := ""
var game: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: only = args[1]
	call_deferred("run")

func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("Captured ", path)

func quiet() -> void:
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	game.message_time = 0
	game.message_queue.clear()
	game.radio.reset()

func place(at: Vector3, zoom := 22.0) -> void:
	game.player.position = at
	game.player.velocity = Vector3.ZERO
	game.camera_focus = at + Vector3.UP
	game.target_zoom = zoom
	game.camera_zoom = zoom

func night(day: int) -> void:
	game.day = day
	game.campaign.state.day = day
	game.campaign.state.night = true
	game.hour = 23
	game.hours_per_second = 0

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	game.checkpoints_enabled = false
	game.save_path = "user://preview_v7.json"
	game.preferences.path = "user://preview_v7_settings.cfg"
	game.preferences.tutorial_done = true
	for section in ["hunter", "menu", "events", "water", "itch", "ui"]:
		if only in ["", section]:
			await call(section + "_shots")
	quit()

func shore_point() -> Vector3:
	var cam_dir := Vector3(29, 0, 40).normalized()
	for ring in range(6, 30):
		for i in 36:
			var p := Vector3(3, 1, 4) + Vector3(cos(i * TAU / 36), 0, sin(i * TAU / 36)) * ring
			var g: Variant = game.night_raids.ground_at(p)
			if g != null and game.night_raids.ground_at(p + cam_dir * 1.2) == null and game.night_raids.ground_at(p + cam_dir * 2.2) == null and game.night_raids.ground_at(p - cam_dir * 3.0) != null:
				return (g as Vector3) - Vector3(0, .35, 0)
	return Vector3(14, 1, 9)

## Открытая точка на земле: видна из изометрической камеры (ничто не заслоняет голову).
func open_spot(center: Vector3, min_d: float, max_d: float) -> Vector3:
	var cam_dir := Vector3(29, 34, 40).normalized()
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for ring in range(int(min_d), int(max_d) + 1):
		for i in 24:
			var a := i * TAU / 24.0
			var p := center + Vector3(cos(a), 0, sin(a)) * ring
			var g: Variant = game.night_raids.ground_at(p)
			if g == null:
				continue
			var foot: Vector3 = (g as Vector3) - Vector3(0, .35, 0)
			var q := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 2.2, foot + Vector3.UP * 2.2 + cam_dir * 40)
			q.collision_mask = 0xFFFFFFFF
			if space.intersect_ray(q).is_empty():
				# не вплотную к домам
				var clear := true
				for k in 8:
					var side := Vector3(cos(k * TAU / 8), 0, sin(k * TAU / 8)) * 1.2
					var q2 := PhysicsRayQueryParameters3D.create(foot + Vector3.UP, foot + Vector3.UP + side)
					q2.collision_mask = 0xFFFFFFFF
					if not space.intersect_ray(q2).is_empty():
						clear = false
				if clear and absf(foot.y - center.y) < 1.5:
					return foot
	return center + Vector3(min_d, 0, 0)

func hunter_pose(at: Vector3, face: Vector3, anim: String, t: float) -> void:
	var h: Node3D = game.hunter
	h.preview_freeze = true
	h.active = true
	h.space = ""
	h.body.show()
	h.body.global_position = at
	h.body.look_at(Vector3(face.x, at.y, face.z), Vector3.UP, true)
	h.visual.pose_for_preview(anim, t)
	for i in 10:
		h.presence.tick(.05)

func hunter_shots() -> void:
	game.start_shift()
	game.tutorial.stop()
	night(4)
	game.lighthouse_on = false
	game.player.lantern_on = false
	var me := Vector3(4.4, 1.2, 10.4)
	place(me, 18)
	await create_timer(1.0).timeout
	quiet()
	var far := open_spot(me - Vector3(0, 1.2, 0), 11, 15)
	hunter_pose(far, me, "idle", .5)
	game.camera_focus = (far + me) * .5 + Vector3.UP
	game.hunter.presence.blink_clock = 99
	await create_timer(.3).timeout
	quiet()
	var pr = game.hunter.presence
	await shot("01_hunter_far_eyes")
	game.player.lantern_on = true
	var mid := open_spot(me - Vector3(0, 1.2, 0), 5, 7)
	game.player.get_node("Visual").rotation.y = atan2(mid.x - me.x, mid.z - me.z)
	hunter_pose(mid, me, "stalk", .4)
	for i in 30:
		game.hunter.presence.tick(.05)
	await create_timer(.3).timeout
	quiet()
	await shot("02_hunter_lantern_catch")
	if OS.get_environment("UI_TAG") == "cover":
		game.hud.visible = false
		game.target_zoom = 12
		game.camera_zoom = 12
		game.camera_focus = (mid + me) * .5 + Vector3.UP
		await create_timer(.3).timeout
		await shot("cover_raw")
		game.hud.visible = true
	var s := shore_point()
	var cam_dir := Vector3(29, 0, 40).normalized()
	game.player.lantern_on = false
	var inland := open_spot(s, 6, 9)
	place(inland + Vector3(0, .35, 0), 14)
	hunter_pose(s, s + cam_dir * 5, "idle", 1.0)
	game.camera_focus = s + Vector3(0, 1, 0) + cam_dir * 1.5
	game.hunter.presence.blink_clock = 99
	await create_timer(.4).timeout
	quiet()
	await shot("03_hunter_water_reflection")
	game.hunter.preview_freeze = false
	game.hunter.visual.resume_tree()

func menu_shots() -> void:
	if game.playing:
		game.return_to_title()
	game.preferences.difficulty = "nightmare"
	game.hud.show_menu("title")
	await create_timer(.5).timeout
	await shot("10_menu_difficulty_nightmare")
	game.preferences.difficulty = "normal"
	game.hud.show_menu("title")

func ev_night(day: int, kind: String) -> Node:
	if not game.playing:
		game.start_shift()
		game.tutorial.stop()
	game.hunter.reset()
	game.hunter.enabled = false
	game.night_raids.set_process(false)
	game.clear_enemies()
	night(day)
	game.campaign.state.night_clock = 0
	var ev: Node = game.night_events
	ev.force(kind)
	return ev

func events_shots() -> void:
	# шторм: обрыв питания
	var ev := ev_night(5, "storm")
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	place(Vector3(-4.5, 1.2, -3.0), 20)
	game.player.lantern_on = true
	await create_timer(.6).timeout
	quiet()
	ev.outage()
	ev.flash_light.light_energy = 3.5
	game.radio.reset()
	await create_timer(.25).timeout
	await shot("04_storm_outage")
	# туман
	ev = ev_night(3, "fog")
	ev.fog = 1.0
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	place(Vector3(4.4, 1.2, 9.4), 18)
	game.player.lantern_on = true
	await create_timer(1.0).timeout
	quiet()
	await shot("05_thick_fog")
	ev.fog = 0
	# сейнер у камней: смотритель у сигнального фонаря, камень вспыхнул
	ev = ev_night(6, "ship")
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	ev.clock = ev.SHIP_START + .1
	ev.ship_s = ev.rock_s(0) - 5.0
	place(ev.SIGNAL_LAMP + Vector3(.6, .3, .4), 26)
	game.player.lantern_on = true
	await create_timer(2.5).timeout
	game.camera_focus = ev.SIGNAL_LAMP.lerp(ev.ship.global_position, .6) + Vector3.UP
	game.clear_enemies()
	quiet()
	ev.signal_flash = .6
	await shot("06_ship_guiding")
	# ложный спасатель: у двери изнутри
	ev = ev_night(11, "rescuer")
	game.enter_building("cabin")
	await create_timer(.3).timeout
	game.player.position = game.building_interiors.spawn_at("cabin")
	ev.clock = ev.RESCUER_START + 13.5
	ev.rescuer_phase = 3
	await create_timer(.5).timeout
	quiet()
	game.notify("Он повторяет одно и то же — слово в слово, тем же голосом.", 8)
	for i in 6:
		game.hud.overlay.card_time = 0
		game.hud.overlay.alert_time = 0
		await process_frame
	await create_timer(.15).timeout
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	await process_frame
	await shot("07_fake_rescuer_door")
	game.exit_building()
	game.hunter.enabled = true

func water_shots() -> void:
	ev_night(6, "")
	game.night_events.reset()
	var lk: Node = game.water_lurker
	var edge := Vector3(18.5, 1.45, 7.0)
	place(edge, 14)
	game.player.lantern_on = true
	game.lighthouse_on = true
	await create_timer(.8).timeout
	quiet()
	lk._start_bubbling()
	lk.timer = 99
	await create_timer(.8).timeout
	await shot("08_pier_water_bubbling")
	lk._grab()
	lk.timer = lk.DRAG_SECONDS * .55
	lk.set_process(false)
	lk._animate(.016)
	game.player.global_position = edge
	await create_timer(.2).timeout
	await shot("09_pier_lurker_grab")
	lk.reset()
	lk.set_process(true)

var frame_no := 0
func frame(n := 1, gap := .1) -> void:
	for i in n:
		await create_timer(gap).timeout
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(640, 400, Image.INTERPOLATE_BILINEAR)
		DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
		img.save_png(out.path_join("frames/f%03d.png" % frame_no))
		frame_no += 1

## Кадры для трейлера-GIF и обложки itch.io (out = /workspace/games/itch-kit).
func itch_shots() -> void:
	game.hud.show_menu("title")
	await frame(6, .15)
	# охотник приближается в темноте
	game.start_shift()
	game.tutorial.stop()
	game.night_raids.set_process(false)
	night(4)
	game.lighthouse_on = false
	game.player.lantern_on = false
	var me := Vector3(4.4, 1.2, 10.4)
	place(me, 18)
	await create_timer(1.0).timeout
	quiet()
	var far := open_spot(me - Vector3(0, 1.2, 0), 11, 15)
	for i in 14:
		var at := far.lerp(me - Vector3(0, 1.2, 0), i / 22.0)
		hunter_pose(at, me, "stalk", .1 * i)
		game.camera_focus = (far + me) * .5 + Vector3.UP
		quiet()
		await frame(1, .06)
	# фонарь ловит его
	game.player.lantern_on = true
	for i in 6:
		await frame(1, .1)
	game.hunter.preview_freeze = false
	game.hunter.reset()
	game.hunter.enabled = false
	# шторм
	var ev := ev_night(5, "storm")
	game.lighthouse_on = true
	game.beacon.set_powered(true)
	place(Vector3(-4.5, 1.2, -3.0), 20)
	game.player.lantern_on = true
	await create_timer(.5).timeout
	quiet()
	await frame(3, .1)
	ev.outage()
	for i in 8:
		if i % 3 == 0:
			ev.flash_light.light_energy = 4.0
		await frame(1, .08)
	# туман
	ev = ev_night(3, "fog")
	ev.fog = 1.0
	place(Vector3(4.4, 1.2, 9.4), 18)
	game.lighthouse_on = true
	await create_timer(.8).timeout
	quiet()
	await frame(6, .12)
	ev.fog = 0
	# сейнер
	ev = ev_night(6, "ship")
	ev.clock = ev.SHIP_START + .1
	ev.ship_s = ev.rock_s(0) - 6.0
	place(ev.SIGNAL_LAMP + Vector3(.6, .3, .4), 26)
	await create_timer(1.5).timeout
	game.camera_focus = ev.SIGNAL_LAMP.lerp(ev.ship.global_position, .6) + Vector3.UP
	quiet()
	await frame(8, .12)
	# причал
	ev_night(6, "")
	game.night_events.reset()
	var lk: Node = game.water_lurker
	var edge := Vector3(18.5, 1.45, 7.0)
	place(edge, 14)
	await create_timer(.6).timeout
	quiet()
	lk._start_bubbling()
	lk.timer = 99
	await frame(6, .1)
	lk._grab()
	lk.timer = lk.DRAG_SECONDS
	for i in 6:
		lk.tick(.12)
		await frame(1, .05)
	game.hud.show_menu("title")
	await frame(4, .15)

## Интерфейс до/после переделки (UI_TAG=before|after).
func ui_shots() -> void:
	var tag := OS.get_environment("UI_TAG")
	if tag.is_empty():
		tag = "after"
	game.hud.show_menu("title")
	await create_timer(.5).timeout
	await shot("ui_%s_1_menu" % tag)
	game.hud.settings_panel.open()
	await create_timer(.3).timeout
	await shot("ui_%s_2_settings" % tag)
	game.hud.settings_panel.close()
	game.achievements.open_records()
	await create_timer(.3).timeout
	await shot("ui_%s_3_records" % tag)
	game.achievements.close_records()
	game.start_or_resume()
	game.tutorial.stop()
	await create_timer(.6).timeout
	quiet()
	place(Vector3(2.2, 1.2, 4.6), 18.0)
	game.hour = 17.5
	game.hours_per_second = 0
	game.notify("Генератору нужно топливо. Проверьте ящики на тропе.", 30)
	game.achievements.unlocked.erase("first_night")
	game.achievements.unlock("first_night")
	await create_timer(.8).timeout
	await shot("ui_%s_4_hud_day" % tag)
	quiet()
	night(5)
	game.lighthouse_on = false
	game.player.lantern_on = false
	place(Vector3(12, 1.2, 8), 18.0)
	game.darkness.level = 1.0
	for i in 10:
		game.darkness.tick(.1)
		game.update_drain_feedback(.1)
		await process_frame
	await shot("ui_%s_5_hud_night_drain" % tag)
	game.paused = true
	game.hud.show_menu("pause")
	await create_timer(.3).timeout
	await shot("ui_%s_6_pause" % tag)
