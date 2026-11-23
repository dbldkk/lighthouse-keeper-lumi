extends Node
## Синтезированные звуки: прибой, шаги и взаимодействие.
var sea: AudioStreamPlayer
var steps: AudioStreamPlayer
var effect: AudioStreamPlayer
var rainfall: AudioStreamPlayer
var drone: AudioStreamPlayer
var radio: AudioStreamPlayer
var engine: AudioStreamPlayer
var music: AudioStreamPlayer
var horror_cache := {}
var burn: AudioStreamPlayer
var cue_player: AudioStreamPlayer
var cue_cache := {}
const BAL = preload("res://scripts/balance.gd")
const SURFACES := ["grass", "wood", "stone", "sand"]
const STEP_VARIANTS := 5
## Громкость поверхностей относительно друг друга (дБ): дерево звонче, песок глуше.
const SURFACE_GAIN := {"grass": -1.0, "wood": 1.5, "stone": 0.0, "sand": -2.5}
const HORROR_FILES := {"heartbeat":"heartbeat","static":"static_burst","stinger":"stinger","slam":"door_slam","whisper_long":"whisper","flicker":"lantern_flicker","breath":"breath","hit":"hit","tell":"tell","splash":"splash"}
var step_samples := {}
var step_pool: Array[AudioStreamPlayer] = []
var step_index := 0
var last_variant := {}
var horror_samples := {}
var deep_drone: AudioStreamPlayer
var heart: AudioStreamPlayer
var heart_clock := 0.0
var heart_rate := 0.0
var heart_volume := -60.0
var muffle: AudioEffectLowPassFilter
var muffle_bus := -1
const TITLE_THEME = preload("res://assets/audio/music/menu_tide.wav")
const END_THEME = preload("res://assets/audio/music/morning_signal.wav")

func _ready() -> void:
	sea = AudioStreamPlayer.new()
	sea.stream = noise_stream(5.0, 0)
	sea.bus = "Environment"
	sea.volume_db = -25
	add_child(sea)
	sea.play()
	steps = AudioStreamPlayer.new()
	steps.stream = noise_stream(0.13, 1)
	steps.bus = "Environment"
	steps.volume_db = -17
	add_child(steps)
	_load_steps()
	_load_horror()
	effect = AudioStreamPlayer.new()
	effect.stream = noise_stream(0.3, 2)
	effect.bus = "Environment"
	effect.volume_db = -20
	add_child(effect)
	rainfall = looping_player(3, 3.0)
	drone = looping_player(4, 6.0)
	radio = AudioStreamPlayer.new()
	radio.stream = noise_stream(0.85, 5)
	radio.bus = "Environment"
	radio.volume_db = -23
	add_child(radio)
	engine = looping_player(6,4.0)
	burn = looping_player(10, 1.2)
	burn.volume_db = -60
	cue_player = AudioStreamPlayer.new()
	cue_player.bus = "Environment"
	cue_player.volume_db = -15
	add_child(cue_player)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = -13
	add_child(music)

func set_music(screen: String) -> void:
	match screen:
		"title":
			music.stream = repeat_track(TITLE_THEME)
			music.play()
		"win", "demo_win":
			music.stream = END_THEME
			music.play()
		_:
			music.stop()
			music.stream = null

func repeat_track(source: AudioStreamWAV) -> AudioStreamWAV:
	var track := source.duplicate() as AudioStreamWAV
	track.loop_begin = 0
	track.loop_end = roundi(track.get_length()*track.mix_rate)
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return track

func looping_player(kind: int, duration: float) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = noise_stream(duration, kind)
	audio.bus = "Environment"
	audio.volume_db = -70
	add_child(audio)
	audio.play()
	return audio

func set_ambience(night: float, rain: float) -> void:
	rainfall.volume_db = lerpf(-70, -24, rain)
	drone.volume_db = lerpf(-70, -34, night)

func set_engine(distance: float, running: bool) -> void:
	engine.volume_db = lerpf(-70,-26,clampf(1-distance/18.0,0,1)) if running else -70.0

func set_story_silence(silent: bool) -> void:
	sea.volume_db = -65 if silent else -25
	if silent:
		rainfall.volume_db = -65
		drone.volume_db = -70

func noise_stream(duration: float, kind: int) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 127 + kind
	var filtered := 0.0
	for index in count:
		var t := float(index) / rate
		filtered = lerpf(filtered, rng.randf_range(-1, 1), 0.07 if kind == 0 else 0.45)
		var value := 0.0
		if kind == 0:
			value = filtered * (0.55 + 0.3 * sin(TAU * t / duration)) + sin(t * 80) * 0.008
		elif kind == 1:
			value = (filtered * 0.7 + sin(t * 95) * 0.2) * pow(1.0 - float(index) / count, 2)
		elif kind == 2:
			value = sin(t * TAU * lerpf(520, 760, t / duration)) * pow(1.0 - t / duration, 2) * 0.35
		elif kind == 3:
			value = filtered * 0.7 + rng.randf_range(-0.1, 0.1)
		elif kind == 4:
			value = (sin(TAU * t * 110) + sin(TAU * t * 130.833333) * 0.6 + sin(TAU * t * 164.833333) * 0.3) * 0.11
			value *= 0.8 + sin(TAU * t / duration) * 0.2
		elif kind == 6:
			value = (sin(TAU*t*35)*0.2+sin(TAU*t*70)*0.07)*(0.85+sin(TAU*t*6)*0.15)+filtered*0.08
		elif kind==7:
			var beat := fmod(t,.23)
			value = (sin(t*TAU*72)*.55+filtered*.2)*exp(-beat*38)
		elif kind==8:
			value = (filtered*.3+sin(t*TAU*163)*.035)*pow(sin(PI*t/duration),2)
		elif kind==10:
			value = filtered*.55*(.6+.4*sin(TAU*t*13))+sin(TAU*t*190)*.05
		elif kind==11:
			var pulse := fmod(t,.32)
			value = (sin(TAU*t*660)*.5+sin(TAU*t*880)*.3)*exp(-pulse*9)*(1.0 if t<.96 else 0.0)
		elif kind==12:
			var note := 523.25 if t<.16 else (659.25 if t<.32 else 783.99)
			value = sin(TAU*t*note)*.4*exp(-fmod(t,.16)*7)*(1.0-t/duration)
		elif kind==13:
			value = (sin(TAU*t*lerpf(220,90,t/duration))*.5+filtered*.35)*pow(1.0-t/duration,1.5)
		elif kind==9:
			value = filtered*.45*(.2+.8*maxf(0,sin(TAU*t*7)))
		else:
			value = (filtered * 0.6 + sin(t * TAU * 820) * 0.12) * pow(sin(PI * t / duration), 2)
		data.encode_s16(index * 2, int(clampf(value, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind in [0, 3, 4, 6, 10]:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream

# ---------------------------------------------------------------- шаги
func _load_steps() -> void:
	for surface in SURFACES:
		var list: Array = []
		for i in STEP_VARIANTS:
			var path := "res://assets/audio/steps/%s_%d.wav" % [surface, i + 1]
			if ResourceLoader.exists(path):
				list.append(load(path))
		step_samples[surface] = list
	# Пул из четырёх плееров: шаг не обрывает предыдущий хвост (нет щелчков), но и не копится.
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = "Environment"
		add_child(player)
		step_pool.append(player)

## Шаг: случайный вариант (не повторяет предыдущий), разброс высоты и громкости, поверхность.
func footstep(surface: String = "grass", running := false) -> void:
	var list: Array = step_samples.get(surface, step_samples.get("grass", []))
	if list.is_empty():
		if not steps.playing:
			steps.pitch_scale = randf_range(0.88, 1.1)
			steps.play()
		return
	var variant := randi() % list.size()
	if list.size() > 1 and variant == int(last_variant.get(surface, -1)):
		variant = (variant + 1 + randi() % (list.size() - 1)) % list.size()
	last_variant[surface] = variant
	var player: AudioStreamPlayer = step_pool[step_index]
	step_index = (step_index + 1) % step_pool.size()
	player.stream = list[variant]
	player.pitch_scale = 1.0 + randf_range(-BAL.STEP_PITCH_JITTER, BAL.STEP_PITCH_JITTER) + (0.04 if running else 0.0)
	player.volume_db = BAL.STEP_VOLUME_DB + float(SURFACE_GAIN.get(surface, 0.0)) + randf_range(-BAL.STEP_VOLUME_JITTER_DB, BAL.STEP_VOLUME_JITTER_DB) * .5 + (BAL.STEP_RUN_BOOST_DB if running else 0.0)
	player.play()

## Шаги «за спиной» в 3D: тот же набор сэмплов, что и у смотрителя.
func phantom_step(at: Vector3, surface: String = "grass") -> void:
	var list: Array = step_samples.get(surface, [])
	if list.is_empty():
		horror_cue("steps", at)
		return
	var cue3d := AudioStreamPlayer3D.new()
	cue3d.bus = "Environment"
	cue3d.stream = list[randi() % list.size()]
	cue3d.unit_size = 4
	cue3d.max_distance = 30
	cue3d.volume_db = BAL.STEP_VOLUME_DB + 2.0
	cue3d.pitch_scale = randf_range(.86, .94)
	add_child(cue3d)
	cue3d.global_position = at
	cue3d.finished.connect(cue3d.queue_free)
	cue3d.play()

# ---------------------------------------------------------------- ужас
func _load_horror() -> void:
	for key in HORROR_FILES:
		var path := "res://assets/audio/horror/%s.wav" % HORROR_FILES[key]
		if ResourceLoader.exists(path):
			horror_samples[key] = load(path)
	if ResourceLoader.exists("res://assets/audio/horror/drone_low.wav"):
		var loop: AudioStreamWAV = (load("res://assets/audio/horror/drone_low.wav") as AudioStreamWAV).duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		deep_drone = AudioStreamPlayer.new()
		deep_drone.stream = loop
		deep_drone.bus = "Environment"
		deep_drone.volume_db = -70
		add_child(deep_drone)
		deep_drone.play()
	heart = AudioStreamPlayer.new()
	heart.bus = "Environment"
	heart.stream = horror_samples.get("heartbeat")
	add_child(heart)
	_setup_muffle()

func _setup_muffle() -> void:
	muffle_bus = AudioServer.get_bus_index("Environment")
	if muffle_bus < 0:
		AudioServer.add_bus()
		muffle_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(muffle_bus, "Environment")
	for i in AudioServer.get_bus_effect_count(muffle_bus):
		if AudioServer.get_bus_effect(muffle_bus, i) is AudioEffectLowPassFilter:
			muffle = AudioServer.get_bus_effect(muffle_bus, i)
			return
	muffle = AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = 20000
	AudioServer.add_bus_effect(muffle_bus, muffle)

## Одиночный звук ужаса. Для 3D передайте точку, иначе звучит «в голове».
func scare(kind: String, volume_db := -6.0, pitch := 1.0, at: Variant = null) -> void:
	var stream: AudioStream = horror_samples.get(kind)
	if stream == null:
		cue("alarm")
		return
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Environment"
		p3.stream = stream
		p3.unit_size = 6
		p3.max_distance = 45
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		add_child(p3)
		p3.global_position = at
		p3.finished.connect(p3.queue_free)
		p3.play()
		return
	var p := AudioStreamPlayer.new()
	p.bus = "Environment"
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## Напряжение: 0 — спокойно, 1 — паника. Сердцебиение, низкий гул и «глухой» слух.
func set_tension(tension: float, heart_bpm: float, delta: float) -> void:
	tension = clampf(tension, 0, 1)
	if is_instance_valid(deep_drone):
		deep_drone.volume_db = move_toward(deep_drone.volume_db, lerpf(-60, -16, tension) if tension > .05 else -70.0, 30 * delta)
	if muffle != null:
		muffle.cutoff_hz = lerpf(20000, 1400, smoothstep(.45, 1.0, tension))
	heart_rate = heart_bpm
	heart_volume = lerpf(-26, -4, clampf((heart_bpm - 60) / 80.0, 0, 1))
	if heart_bpm <= 0 or not is_instance_valid(heart) or heart.stream == null:
		heart_clock = 0
		return
	heart_clock += delta
	if heart_clock >= 60.0 / heart_bpm:
		heart_clock = 0
		heart.volume_db = heart_volume
		heart.pitch_scale = randf_range(.97, 1.03)
		heart.play()

func interact(kind: String = "") -> void:
	effect.pitch_scale = {"wood": 0.7, "beacon": 0.65, "cook": 1.15, "fish": 1.3}.get(kind, 1.0)
	effect.play()

func set_burn(active: bool) -> void:
	if not is_instance_valid(burn):
		return
	burn.volume_db = move_toward(burn.volume_db, -19.0 if active else -60.0, 6.0 if active else 3.0)

## alarm — тревога события, chime — цель выполнена, dispel — тень рассеяна.
func cue(kind: String) -> void:
	if kind in ["hit", "tell", "splash", "flicker"]:
		scare(kind, {"hit":-4.0, "tell":-8.0, "splash":-6.0, "flicker":-8.0}[kind], randf_range(.94, 1.06))
		return
	var type: int = {"alarm":11,"chime":12,"dispel":13}.get(kind,12)
	if not cue_cache.has(type):cue_cache[type]=noise_stream({11:1.0,12:.62,13:.55}[type],type)
	if kind == "dispel":
		var one_shot := AudioStreamPlayer.new()
		one_shot.bus = "Environment"
		one_shot.stream = cue_cache[type]
		one_shot.volume_db = -13
		one_shot.pitch_scale = randf_range(.9, 1.15)
		add_child(one_shot)
		one_shot.finished.connect(one_shot.queue_free)
		one_shot.play()
		return
	cue_player.stream = cue_cache[type]
	cue_player.play()

func radio_signal() -> void:
	radio.play()

func horror_cue(kind: String, at: Vector3) -> void:
	var type: int = {"knock":7,"whisper":8,"radio":9,"steps":1}.get(kind,8)
	if not horror_cache.has(type):horror_cache[type]=noise_stream(.75 if type!=1 else .18,type)
	var cue := AudioStreamPlayer3D.new()
	cue.bus = "Environment"
	cue.stream = horror_cache[type]
	cue.unit_size = 7
	cue.max_distance = 55
	cue.volume_db = -14
	add_child(cue)
	cue.global_position = at
	cue.finished.connect(cue.queue_free)
	cue.play()

func _exit_tree() -> void:
	if muffle != null:
		muffle.cutoff_hz = 20000
	for audio_player in [sea, steps, effect, rainfall, drone, radio, engine, music, burn, cue_player, deep_drone, heart]:
		if is_instance_valid(audio_player):
			audio_player.stop()
			audio_player.stream = null
