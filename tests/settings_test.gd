extends SceneTree
## Меню настроек: шины громкости, мышь, яркость/гамма с калибровкой, пресеты качества, окно,
## поле зрения, переназначение клавиш, субтитры; сохранение в settings.cfg и применение при старте.
var game: Node
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

func tap(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(1)

func bus_db(name: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(name))

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(2)
	game.checkpoints_enabled = false
	var prefs = game.preferences
	check(prefs.SETTINGS_FILE == "user://settings.cfg", "Settings live in user://settings.cfg")
	prefs.path = "user://automated_settings_test.cfg"
	if FileAccess.file_exists(prefs.path):
		DirAccess.remove_absolute(prefs.path)
	var hud = game.hud
	var panel = hud.settings_panel
	hud.settings_button.pressed.emit()
	await frames(1)
	check(panel.visible and panel.tabs.get_tab_count() == 3, "Settings open from the main menu with three tabs")
	check(panel.sliders.size() == 4 and prefs.CHANNELS.has("Master"), "Four volume buses: master, effects, voice, music")
	# звук
	panel.sliders[3].value = .5
	panel.sliders[0].value = .4
	panel.sliders[1].value = .3
	panel.sliders[2].value = .2
	panel.subtitles.button_pressed = false
	# изображение
	panel.quality.select(0)
	panel.brightness.value = 1.3
	check(is_equal_approx(float((panel.calibration.material as ShaderMaterial).get_shader_parameter("brightness")), 1.3), "The calibration image previews brightness live")
	panel.gamma.value = 1.2
	panel.fov.value = 90
	panel.vsync.button_pressed = false
	# управление
	panel.sensitivity.value = 2.0
	panel.invert_y.button_pressed = true
	panel._start_capture("lantern")
	check(panel.key_buttons["lantern"].text == "…", "Rebinding waits for a key")
	panel.capture_key(KEY_W)
	check(panel.capturing == "lantern" and int(panel.pending["lantern"]) == KEY_F, "Movement keys cannot be taken")
	panel.capture_key(KEY_G)
	check(int(panel.pending["lantern"]) == KEY_G and panel.key_buttons["lantern"].text == "G", "Lantern rebinds to G")
	panel._start_capture("flare")
	panel.capture_key(KEY_G)
	check(int(panel.pending["flare"]) == KEY_G and int(panel.pending["lantern"]) == KEY_X, "A taken key swaps actions")
	panel._start_capture("flare")
	panel.capture_key(KEY_ESCAPE)
	check(panel.capturing.is_empty() and int(panel.pending["flare"]) == KEY_G, "Esc cancels capture")
	panel._start_capture("lantern")
	panel.capture_key(KEY_V)
	panel._start_capture("sprint")
	panel.capture_key(KEY_CTRL)
	panel.apply_settings()
	panel.close()
	await frames(2)
	check(is_equal_approx(bus_db("Master"), linear_to_db(.5)) and is_equal_approx(bus_db("Environment"), linear_to_db(.4)) and is_equal_approx(bus_db("Dialogue"), linear_to_db(.3)) and is_equal_approx(bus_db("Music"), linear_to_db(.2)), "Each slider drives its own audio bus")
	var preset: Dictionary = prefs.QUALITY[0]
	check(not game.world.get_node("Sun").shadow_enabled and is_equal_approx(root.scaling_3d_scale, preset.scale) and root.msaa_3d == Viewport.MSAA_DISABLED, "Low preset: no shadows, reduced 3D resolution, no MSAA")
	var mat := hud.atmosphere.material as ShaderMaterial
	check(is_equal_approx(float(mat.get_shader_parameter("brightness")), 1.3) and is_equal_approx(float(mat.get_shader_parameter("gamma")), 1.2), "Brightness and gamma go into the dark screen shader")
	check(is_equal_approx(float(mat.get_shader_parameter("grain_scale")), preset.grain), "Low preset softens film grain")
	game.start_shift()
	await frames(2)
	var env: Environment = game.world.get_node("CoastalAtmosphere").environment
	game.update_atmosphere()
	var low_fog: float = env.fog_density
	prefs.quality = 2
	prefs.apply()
	game.update_atmosphere()
	check(env.fog_density > low_fog * 1.5 and game.world.get_node("Sun").shadow_enabled and is_equal_approx(root.scaling_3d_scale, 1.0), "High preset: full fog, shadows and resolution")
	check(is_equal_approx(float(mat.get_shader_parameter("grain_scale")), 1.0), "High preset: full grain")
	prefs.quality = 1
	prefs.apply()
	check(is_equal_approx(root.scaling_3d_scale, prefs.QUALITY[1].scale) and game.world.get_node("Sun").shadow_enabled, "Medium preset sits in between")
	prefs.quality = 0
	prefs.apply()
	game.update_camera(0.0)
	check(is_equal_approx(game.camera.size, game.camera_zoom * 90.0 / 75.0), "Field of view widens the isometric frame")
	# клавиши в игре
	check(prefs.translate(KEY_V) == KEY_F and prefs.translate(KEY_F) == KEY_NONE, "Bound key maps to its action; the old key goes silent")
	var lantern: bool = game.player.lantern_on
	await tap(KEY_F)
	check(game.player.lantern_on == lantern, "Old lantern key no longer toggles the lantern")
	await tap(KEY_V)
	check(game.player.lantern_on != lantern, "New lantern key toggles it")
	var flares: int = game.supplies.flares
	await tap(KEY_G)
	check(game.supplies.flares == flares - 1, "Flare fires from its new key")
	check(game.player.sprint_key == KEY_CTRL, "Sprint uses the rebound key")
	check(game.hunter.breath_key == KEY_SPACE, "Breath key follows its binding")
	hud.refresh()
	check(hud.movement_help.text.contains("V фонарь") and hud.movement_help.text.contains("G ракета"), "Help line shows the rebound keys")
	game.tutorial.enabled = true
	game.tutorial.begin()
	game.tutorial.step = 1
	check(game.tutorial.text_for("lantern").begins_with("V"), "Tutorial prompts show the rebound keys")
	game.tutorial.stop()
	# мышь (фоторежим)
	var photo = game.photo
	photo.active = true
	photo.selfie = false
	photo.pitch = 0.0
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(0, 10)
	photo.handle(mm)
	check(photo.pitch > 0 and is_equal_approx(photo.pitch, 10 * .0035 * 2.0), "Mouse sensitivity and invert Y drive the free camera")
	photo.active = false
	# субтитры
	check(not prefs.subtitles, "Subtitles can be switched off")
	# пауза
	await tap(KEY_ESCAPE)
	check(game.paused and hud.settings_button.visible, "Settings are reachable from pause")
	hud.settings_button.pressed.emit()
	await frames(1)
	check(panel.visible and int(panel.pending["lantern"]) == KEY_V and panel.quality.selected == 0, "Pause settings show the current values")
	await tap(KEY_ESCAPE)
	check(not panel.visible and game.paused, "Esc closes settings back to pause")
	await tap(KEY_ESCAPE)
	# сохранение / загрузка
	prefs.reset_bindings()
	prefs.volumes = [1.0, 1.0, 1.0, 1.0]
	prefs.brightness = 1.0
	prefs.subtitles = true
	prefs.mouse_sensitivity = 1.0
	prefs.load_preferences()
	check(prefs.key("lantern") == KEY_V and prefs.key("flare") == KEY_G and prefs.key("sprint") == KEY_CTRL, "Key bindings persist")
	check(is_equal_approx(prefs.volumes[3], .5) and is_equal_approx(prefs.brightness, 1.3) and is_equal_approx(prefs.gamma, 1.2) and is_equal_approx(prefs.fov, 90.0), "Volumes, brightness, gamma and FOV persist")
	check(prefs.quality == 0 and not prefs.vsync and not prefs.subtitles and prefs.invert_y and is_equal_approx(prefs.mouse_sensitivity, 2.0), "Quality, vsync, subtitles and mouse persist")
	check(is_equal_approx(bus_db("Master"), linear_to_db(.5)), "Loading applies the settings immediately")
	var cfg := ConfigFile.new()
	cfg.load(prefs.path)
	cfg.set_value("keys", "lantern", KEY_W)
	cfg.save(prefs.path)
	prefs.load_preferences()
	check(prefs.key("lantern") == KEY_F, "A corrupt binding to a movement key falls back to default")
	DirAccess.remove_absolute(prefs.path)
	prefs.reset_bindings()
	prefs.volumes = [.85, 1.0, .72, 1.0]
	prefs.quality = 2
	prefs.brightness = 1.0
	prefs.gamma = 1.0
	prefs.fov = 75
	prefs.apply()
	print("settings_test: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
