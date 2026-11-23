extends RefCounted
## Настройки игры: user://settings.cfg (старый user://game_settings.cfg читается один раз для переноса).
## Звук по шинам, мышь, яркость/гамма (через экранный шейдер мрака), пресет качества,
## окно/вертикальная синхронизация, поле зрения, переназначение клавиш, субтитры, флаг обучения.

const SIZE_OPTIONS := [Vector2i(960,600),Vector2i(1280,800),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]
## Порядок сохранён ради старых настроек и тестов: мир (эффекты), голос, музыка, затем общая громкость.
const CHANNELS := ["Environment", "Dialogue", "Music", "Master"]
const CHANNEL_TITLES := ["Звуки и эффекты", "Голоса и радио", "Музыка", "Общая громкость"]
const SETTINGS_FILE := "user://settings.cfg"
const LEGACY_FILE := "user://game_settings.cfg"
const QUALITY_TITLES := ["Низкое", "Среднее", "Высокое"]
## Пресеты качества: туман, плёночное зерно, тени, масштаб 3D-разрешения, сглаживание.
const QUALITY := [
	{"fog": .55, "grain": .35, "shadows": false, "scale": .7, "msaa": Viewport.MSAA_DISABLED},
	{"fog": .8, "grain": .7, "shadows": true, "scale": .85, "msaa": Viewport.MSAA_DISABLED},
	{"fog": 1.0, "grain": 1.0, "shadows": true, "scale": 1.0, "msaa": Viewport.MSAA_4X},
]
## Переназначаемые действия: id, название, клавиша по умолчанию.
const ACTIONS := [
	["interact", "Действие", KEY_E],
	["lantern", "Фонарь", KEY_F],
	["flare", "Сигнальная ракета", KEY_X],
	["breath", "Прыжок / задержать дыхание", KEY_SPACE],
	["sprint", "Бег", KEY_SHIFT],
	["journal", "Записи (журнал)", KEY_J],
	["backpack", "Рюкзак", KEY_B],
	["map", "Карта", KEY_M],
	["eat", "Еда", KEY_R],
]
## Эти клавиши занять нельзя: движение и меню.
const RESERVED := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_ESCAPE, KEY_BACKSPACE, KEY_F9, KEY_F10]

var game: Node
var path := SETTINGS_FILE
var size_index := 1
var fullscreen := false
var vsync := true
var quality := 2
var high_quality := true          ## совместимость: true для «Среднего» и «Высокого»
var volumes := [.85, 1.0, .72, 1.0]
var mouse_sensitivity := 1.0
var invert_y := false
var brightness := 1.0
var gamma := 1.0
var fov := 75.0
var subtitles := true
var bindings := {}
var tutorial_done := false

func _init() -> void:
	reset_bindings()

func reset_bindings() -> void:
	bindings.clear()
	for a in ACTIONS:
		bindings[a[0]] = a[2]

func load_preferences() -> void:
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK and path == SETTINGS_FILE:
		err = config.load(LEGACY_FILE)
	if err == OK:
		size_index = clampi(int(config.get_value("video","size",1)),0,SIZE_OPTIONS.size()-1)
		fullscreen = bool(config.get_value("video","fullscreen",false))
		vsync = bool(config.get_value("video","vsync",true))
		if config.has_section_key("video","quality"):
			quality = clampi(int(config.get_value("video","quality",2)),0,2)
		else:
			quality = 2 if bool(config.get_value("video","high_quality",true)) else 0
		brightness = clampf(float(config.get_value("video","brightness",1.0)),.5,1.8)
		gamma = clampf(float(config.get_value("video","gamma",1.0)),.6,1.8)
		fov = clampf(float(config.get_value("video","fov",75.0)),55,100)
		for i in CHANNELS.size():
			volumes[i] = clampf(float(config.get_value("audio",CHANNELS[i],volumes[i])),0,1)
		subtitles = bool(config.get_value("audio","subtitles",true))
		mouse_sensitivity = clampf(float(config.get_value("controls","mouse_sensitivity",1.0)),.2,3.0)
		invert_y = bool(config.get_value("controls","invert_y",false))
		reset_bindings()
		for a in ACTIONS:
			var code := int(config.get_value("keys",a[0],a[2]))
			if code > 0 and code not in RESERVED:
				bindings[a[0]] = code
		tutorial_done = bool(config.get_value("progress","tutorial_done",false))
	high_quality = quality >= 1
	apply()

func save_preferences() -> Error:
	high_quality = quality >= 1
	var config := ConfigFile.new()
	config.set_value("video","size",size_index)
	config.set_value("video","fullscreen",fullscreen)
	config.set_value("video","vsync",vsync)
	config.set_value("video","quality",quality)
	config.set_value("video","high_quality",high_quality)
	config.set_value("video","brightness",brightness)
	config.set_value("video","gamma",gamma)
	config.set_value("video","fov",fov)
	for i in CHANNELS.size():
		config.set_value("audio",CHANNELS[i],volumes[i])
	config.set_value("audio","subtitles",subtitles)
	config.set_value("controls","mouse_sensitivity",mouse_sensitivity)
	config.set_value("controls","invert_y",invert_y)
	for a in ACTIONS:
		config.set_value("keys",a[0],int(bindings[a[0]]))
	config.set_value("progress","tutorial_done",tutorial_done)
	return config.save(path)

# ---------------------------------------------------------------- клавиши
func key(action: String) -> int:
	return int(bindings.get(action, KEY_NONE))

func key_name(action: String) -> String:
	return key_label(key(action))

static func key_label(code: int) -> String:
	match code:
		KEY_SPACE: return "Пробел"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
	return OS.get_keycode_string(code)

func pressed(action: String) -> bool:
	return Input.is_physical_key_pressed(key(action))

func default_key(action: String) -> int:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return KEY_NONE

## Переводит нажатую клавишу в «клавишу по умолчанию» её действия — так весь остальной код
## продолжает проверять KEY_E, KEY_F и т. д. Клавиша, у которой забрали действие, глохнет.
func translate(code: int) -> int:
	for a in ACTIONS:
		if int(bindings[a[0]]) == code:
			return a[2]
	for a in ACTIONS:
		if a[2] == code and int(bindings[a[0]]) != code:
			return KEY_NONE
	return code

## Назначить клавишу. Если она занята другим действием — действия меняются клавишами.
func bind(action: String, code: int) -> bool:
	if code in RESERVED or code == KEY_NONE or not bindings.has(action):
		return false
	var previous := key(action)
	for a in ACTIONS:
		if a[0] != action and int(bindings[a[0]]) == code:
			bindings[a[0]] = previous
	bindings[action] = code
	return true

func translated_event(event: InputEvent) -> InputEvent:
	if not event is InputEventKey:
		return event
	var code: int = event.physical_keycode
	var mapped := translate(code)
	if mapped == code:
		return event
	var copy: InputEventKey = event.duplicate()
	copy.physical_keycode = mapped
	copy.keycode = mapped
	return copy

# ---------------------------------------------------------------- применение
func quality_preset() -> Dictionary:
	return QUALITY[clampi(quality,0,2)]

func fog_scale() -> float:
	return float(quality_preset().fog)

## Поле зрения: в фоторежиме — угол камеры, в изометрии — масштаб кадра (75° = как задумано).
func view_scale() -> float:
	return fov / 75.0

func apply() -> void:
	high_quality = quality >= 1
	for i in CHANNELS.size():
		apply_volume(i,volumes[i])
	if game == null:
		return
	var preset := quality_preset()
	var viewport := game.get_viewport() as Viewport
	viewport.msaa_3d = preset.msaa
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = preset.scale
	var sun := game.world.get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = preset.shadows
	apply_screen()
	if is_instance_valid(game.get("player")):
		game.player.set("sprint_key", key("sprint"))
	if is_instance_valid(game.get("hunter")):
		game.hunter.set("breath_key", key("breath"))
	if DisplayServer.get_name()=="headless" or "--keep-window-size" in OS.get_cmdline_user_args():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var window := game.get_window() as Window
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		var restored := window.mode != Window.MODE_WINDOWED
		window.mode = Window.MODE_WINDOWED
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		var preferred: Vector2i = SIZE_OPTIONS[size_index]
		var maximum := usable.size - Vector2i(24,72)
		var scale := minf(1.0,minf(float(maximum.x)/preferred.x,float(maximum.y)/preferred.y))
		var target := Vector2i(Vector2(preferred)*scale)
		if restored or window.size!=target:
			window.size = target
			window.position = usable.position + (usable.size - target)/2

## Яркость, гамма и зерно — в экранном шейдере (он же рисует мрак), поэтому работают вместе с ним.
func apply_screen() -> void:
	if game == null or game.get("hud") == null:
		return
	var rect = game.hud.get("atmosphere")
	if rect == null:
		return
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("gamma", gamma)
	mat.set_shader_parameter("grain_scale", float(quality_preset().grain))

func apply_volume(index: int, volume: float) -> void:
	var channel: String = CHANNELS[index]
	var bus := AudioServer.get_bus_index(channel)
	if bus<0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count-1
		AudioServer.set_bus_name(bus,channel)
	volumes[index] = clampf(volume,0,1)
	AudioServer.set_bus_mute(bus,volumes[index]<=0.0)
	AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(.001,volumes[index])))
