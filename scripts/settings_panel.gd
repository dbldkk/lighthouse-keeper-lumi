extends Control
## Экран настроек (главное меню и пауза): изображение, звук, управление.
## Значения редактируются здесь и применяются кнопкой «Применить» (и сохраняются в user://settings.cfg).
const CALIBRATION_SHADER = preload("res://shaders/calibration.gdshader")

var hud: CanvasLayer
var preferences
var tabs: TabContainer
# изображение
var resolution: OptionButton
var quality: OptionButton
var quality_note: Label
var fullscreen: CheckButton
var vsync: CheckButton
var fov: HSlider
var brightness: HSlider
var gamma: HSlider
var calibration: TextureRect
# звук
var sliders: Array[HSlider] = []      ## 0 эффекты, 1 голоса, 2 музыка, 3 общая (порядок CHANNELS)
var subtitles: CheckButton
# управление
var sensitivity: HSlider
var invert_y: CheckButton
var key_buttons := {}
var pending := {}
var capturing := ""
var status: Label
var value_labels := {}

func setup(owner_hud: CanvasLayer, settings) -> void:
	hud = owner_hud
	preferences = settings
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(.03,.025,.02,.93)
	add_child(backdrop)
	var sheet: Panel = hud.panel(self,Rect2(280,52,880,800),Color("132a30"))
	sheet.add_theme_stylebox_override("panel",hud.UI.paper())
	hud.text(self,"СМОТРИТЕЛЬ МАЯКА  /  ПАРАМЕТРЫ",Rect2(318,78,700,24),14,hud.GOLD)
	hud.text(self,"Настройки",Rect2(318,104,700,50),36)
	tabs = TabContainer.new()
	tabs.position = Vector2(312,166)
	tabs.size = Vector2(816,578)
	tabs.add_theme_font_size_override("font_size",17)
	tabs.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(tabs)
	_build_video(_tab("Изображение"))
	_build_audio(_tab("Звук"))
	_build_controls(_tab("Управление"))
	status = hud.text(self,"",Rect2(318,752,800,22),14,hud.GOLD)
	hud.make_button(self,"Применить",Vector2(318,782),apply_settings,true).size = Vector2(390,51)
	hud.make_button(self,"Назад · Esc",Vector2(732,782),close).size = Vector2(390,51)
	hud.UI.inkify(self)
	hide()

func _tab(title: String) -> Control:
	var page := Control.new()
	page.name = title
	tabs.add_child(page)
	return page

func _row(page: Control, title: String, y: float) -> void:
	hud.text(page,title,Rect2(18,y,330,34),18)

func _option(page: Control, at: Vector2) -> OptionButton:
	var button := OptionButton.new()
	button.position = at
	button.size = Vector2(260,40)
	button.add_theme_font_size_override("font_size",17)
	page.add_child(button)
	return button

func _check(page: Control, at: Vector2, label := "Включить") -> CheckButton:
	var c := CheckButton.new()
	c.position = at
	c.size = Vector2(260,40)
	c.text = label
	page.add_child(c)
	return c

func _slider(page: Control, at: Vector2, lo: float, hi: float, step: float, id: String, fmt: String) -> HSlider:
	var s := HSlider.new()
	s.position = at + Vector2(0,8)
	s.size = Vector2(200,25)
	s.min_value = lo
	s.max_value = hi
	s.step = step
	page.add_child(s)
	var v: Label = hud.text(page,"",Rect2(at.x+210,at.y+2,70,30),16,hud.MUTED)
	value_labels[id] = [v, fmt]
	s.value_changed.connect(func(value): _on_value(id, value))
	return s

func _on_value(id: String, value: float) -> void:
	var pair: Array = value_labels.get(id, [])
	if not pair.is_empty():
		(pair[0] as Label).text = String(pair[1]) % (value * (100.0 if String(pair[1]).contains("%%") else 1.0))
	if id in ["brightness","gamma"] and calibration:
		var mat := calibration.material as ShaderMaterial
		mat.set_shader_parameter(id, value)

func _build_video(page: Control) -> void:
	var y := 14.0
	_row(page,"Разрешение окна",y)
	resolution = _option(page,Vector2(330,y-4))
	for size in preferences.SIZE_OPTIONS:
		resolution.add_item("%d × %d" % [size.x,size.y])
	y += 50
	_row(page,"Полноэкранный режим",y)
	fullscreen = _check(page,Vector2(330,y-4))
	fullscreen.toggled.connect(func(value): resolution.disabled = value)
	y += 50
	_row(page,"Вертикальная синхронизация",y)
	vsync = _check(page,Vector2(330,y-4))
	y += 50
	_row(page,"Качество графики",y)
	quality = _option(page,Vector2(330,y-4))
	for t in preferences.QUALITY_TITLES:
		quality.add_item(t)
	quality.item_selected.connect(func(_i): _quality_note())
	quality_note = hud.text(page,"",Rect2(18,y+38,560,22),13,hud.MUTED)
	y += 80
	_row(page,"Поле зрения",y)
	fov = _slider(page,Vector2(330,y),55,100,1,"fov","%d°")
	y += 50
	_row(page,"Яркость",y)
	brightness = _slider(page,Vector2(330,y),.5,1.8,.02,"brightness","%.2f")
	y += 50
	_row(page,"Гамма",y)
	gamma = _slider(page,Vector2(330,y),.6,1.8,.02,"gamma","%.2f")
	# калибровка
	var frame: Panel = hud.panel(page,Rect2(612,330,186,186),Color(0,0,0,1))
	frame.name = "CalibrationFrame"
	calibration = TextureRect.new()
	calibration.name = "Calibration"
	calibration.texture = PlaceholderTexture2D.new()
	calibration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	calibration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	calibration.position = Vector2(620,338)
	calibration.size = Vector2(170,170)
	var mat := ShaderMaterial.new()
	mat.shader = CALIBRATION_SHADER
	calibration.material = mat
	page.add_child(calibration)
	var hint: Label = hud.text(page,"Символ должен быть\nедва виден",Rect2(600,520,210,44),13,hud.GOLD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.text(page,"Поле зрения: в фоторежиме — угол камеры, в изометрии — ширина кадра.",Rect2(18,y+44,560,22),13,hud.MUTED)

func _quality_note() -> void:
	var p: Dictionary = preferences.QUALITY[quality.selected]
	quality_note.text = "Туман %d%% · зерно %d%% · тени %s · разрешение 3D %d%%%s" % [roundi(p.fog*100), roundi(p.grain*100), "вкл" if p.shadows else "выкл", roundi(p.scale*100), " · сглаживание" if p.msaa != Viewport.MSAA_DISABLED else ""]

func _build_audio(page: Control) -> void:
	var order := [3, 0, 1, 2]     # общая громкость сверху
	sliders.resize(preferences.CHANNELS.size())
	for row in order.size():
		var i: int = order[row]
		var y := 14.0 + row * 54
		_row(page,preferences.CHANNEL_TITLES[i],y)
		sliders[i] = _slider(page,Vector2(330,y),0,1,.01,"vol%d" % i,"%d%%")
	var y2 := 14.0 + order.size() * 54 + 10
	_row(page,"Субтитры радио и записей",y2)
	subtitles = _check(page,Vector2(330,y2-4))
	hud.text(page,"Шины: Master — общая, Environment — эффекты и мир, Dialogue — голоса и радио, Music — музыка.",Rect2(18,y2+56,780,22),13,hud.MUTED)

func _build_controls(page: Control) -> void:
	_row(page,"Чувствительность мыши",10)
	sensitivity = _slider(page,Vector2(330,10),.2,3.0,.05,"sens","×%.2f")
	_row(page,"Инвертировать ось Y",56)
	invert_y = _check(page,Vector2(330,52))
	hud.text(page,"Мышь — свободная камера фоторежима. Движение — WASD.",Rect2(18,92,600,20),13,hud.MUTED)
	var y := 124.0
	for a in preferences.ACTIONS:
		hud.text(page,a[1],Rect2(18,y+3,330,30),17)
		var b := Button.new()
		b.position = Vector2(330,y)
		b.size = Vector2(200,34)
		b.add_theme_font_size_override("font_size",16)
		var id: String = a[0]
		b.pressed.connect(func(): _start_capture(id))
		page.add_child(b)
		key_buttons[id] = b
		y += 40
	hud.make_button(page,"Сбросить клавиши",Vector2(560,124),_reset_keys).size = Vector2(236,40)
	hud.text(page,"Нажмите кнопку и затем клавишу.\nEsc — отмена. Занятая клавиша\nменяется местами.",Rect2(560,176,240,70),13,hud.MUTED)

func _start_capture(id: String) -> void:
	capturing = id
	_refresh_keys()
	status.text = "Нажмите клавишу для «%s» (Esc — отмена)" % _title(id)

func _title(id: String) -> String:
	for a in preferences.ACTIONS:
		if a[0] == id:
			return a[1]
	return id

func _reset_keys() -> void:
	for a in preferences.ACTIONS:
		pending[a[0]] = a[2]
	capturing = ""
	_refresh_keys()

func _refresh_keys() -> void:
	for id in key_buttons:
		key_buttons[id].text = "…" if id == capturing else preferences.key_label(int(pending[id]))

## Назначение в черновике: занятая клавиша меняется местами.
func capture_key(code: int) -> bool:
	if capturing.is_empty():
		return false
	if code == KEY_ESCAPE:
		capturing = ""
		status.text = ""
		_refresh_keys()
		return true
	if code in preferences.RESERVED:
		status.text = "Эта клавиша занята движением или меню."
		return true
	var previous: int = int(pending[capturing])
	for id in pending:
		if id != capturing and int(pending[id]) == code:
			pending[id] = previous
	pending[capturing] = code
	status.text = "«%s» — %s" % [_title(capturing), preferences.key_label(code)]
	capturing = ""
	_refresh_keys()
	return true

func _input(event: InputEvent) -> void:
	if not visible or capturing.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		capture_key(event.physical_keycode)
		get_viewport().set_input_as_handled()

func open() -> void:
	resolution.select(preferences.size_index)
	quality.select(preferences.quality)
	_quality_note()
	fullscreen.button_pressed = preferences.fullscreen
	vsync.button_pressed = preferences.vsync
	resolution.disabled = preferences.fullscreen
	fov.value = preferences.fov
	brightness.value = preferences.brightness
	gamma.value = preferences.gamma
	for i in sliders.size():
		sliders[i].value = preferences.volumes[i]
	subtitles.button_pressed = preferences.subtitles
	sensitivity.value = preferences.mouse_sensitivity
	invert_y.button_pressed = preferences.invert_y
	pending = preferences.bindings.duplicate()
	capturing = ""
	_refresh_keys()
	_on_value("brightness", brightness.value)
	_on_value("gamma", gamma.value)
	status.text = ""
	show()
	if resolution.disabled:
		quality.grab_focus()
	else:
		resolution.grab_focus()

func close() -> void:
	capturing = ""
	hide()
	hud.settings_button.grab_focus()

func apply_settings() -> void:
	preferences.size_index = resolution.selected
	preferences.quality = quality.selected
	preferences.fullscreen = fullscreen.button_pressed
	preferences.vsync = vsync.button_pressed
	preferences.fov = fov.value
	preferences.brightness = brightness.value
	preferences.gamma = gamma.value
	for i in sliders.size():
		preferences.volumes[i] = sliders[i].value
	preferences.subtitles = subtitles.button_pressed
	preferences.mouse_sensitivity = sensitivity.value
	preferences.invert_y = invert_y.button_pressed
	for id in pending:
		preferences.bindings[id] = int(pending[id])
	preferences.apply()
	status.text = "Настройки сохранены." if preferences.save_preferences()==OK else "Настройки применены. Сохранить файл не удалось."
