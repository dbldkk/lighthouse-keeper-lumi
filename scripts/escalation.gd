extends Node
## Каждая ночь тяжелее предыдущей:
## - охотник смелее и быстрее (aggression 1.0 → 1.8), с 9-й ночи не боится укреплённой хижины;
## - с 4-й ночи с моря может прийти ночной туман (видимость ниже, шанс растёт);
## - 5-я ночь — ШТОРМ: длиннее, ливень, молнии, удар в генератор — пережить до рассвета;
## - с 7-й ночи — «мёртвый час»: на полминуты гаснет весь свет;
## - последняя ночь — большой шторм и выбор у генератора.
const STORM_DAY := 5
const STORM_SECONDS := 95.0
const BOLT_AT := 32.0

var game: Node
var rng := RandomNumberGenerator.new()
var night_was := false
var storm := false
var fog := false
var flash := 0.0
var lightning_clock := 3.0
var done := {}
var fearless_told := false
var fog_amount := 0.0

func _init() -> void:
	rng.randomize()

func reset() -> void:
	night_was = false
	storm = false
	fog = false
	flash = 0
	done.clear()
	fearless_told = false
	fog_amount = 0
	if is_instance_valid(game) and is_instance_valid(game.coastal_life):
		game.coastal_life.weather_mode = 0

func level() -> float:
	var last: int = game.campaign.final_night()
	return clampf(float(game.day - 2) / maxf(1.0, float(last - 2)), 0, 1)

func hunter_aggression() -> float:
	return 1.0 + .8 * level() + (.25 if storm else 0.0)

func storm_night(day: int) -> bool:
	if not game.campaign.enabled:
		return false
	return day == STORM_DAY or day == game.campaign.final_night()

func night_clock() -> float:
	return float(game.campaign.state.night_clock)

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.finished:
		return
	var night: bool = game.campaign.enabled and bool(game.campaign.state.night) and not game.first_shift_demo.active()
	if night and not night_was:
		begin_night()
	elif not night and night_was:
		end_night()
	night_was = night
	fog_amount = move_toward(fog_amount, 1.0 if fog else 0.0, delta * .25)
	if night and not game.paused:
		_tick_night(delta)
	_apply_visuals(delta)

func begin_night() -> void:
	done.clear()
	var day: int = game.day
	storm = storm_night(day)
	fog = false
	if day >= 4 and not storm:
		fog = rng.randf() < .2 + .07 * (day - 4)
	lightning_clock = rng.randf_range(2, 5)
	var lines: Array[String] = []
	if storm:
		game.coastal_life.weather_mode = 1
		if day == STORM_DAY:
			game.campaign.entry().night.seconds = maxf(float(game.campaign.entry().night.seconds), STORM_SECONDS)
		lines.append("ШТОРМ. Ливень, молнии, генератор под ударом. Переживите ночь до рассвета.")
		game.alert("ШТОРМ", "Переживите ночь до рассвета. Берегите свет маяка", 6)
	if fog:
		lines.append("С моря ползёт ночной туман — видно только на пару шагов.")
	if day >= 2 and day < game.campaign.calendar_days():
		var a := hunter_aggression()
		if a >= 1.5 and not fearless_told:
			fearless_told = true
			lines.append("Оно больше не боится укреплённой хижины. Только свет маяка, костёр и ракеты.")
		elif day >= 3:
			lines.append("Ночь %d. Шаги тяжелее, чем вчера." % day)
	if not lines.is_empty():
		game.notify(" ".join(lines), 9, 1)

func end_night() -> void:
	if storm:
		game.coastal_life.weather_mode = 0
	storm = false
	fog = false
	flash = 0

func _tick_night(delta: float) -> void:
	var t := night_clock()
	var duration: float = float(game.campaign.entry().night.seconds)
	if storm:
		lightning_clock -= delta
		if lightning_clock <= 0:
			lightning_clock = rng.randf_range(3.5, 8.0)
			strike()
		# удар молнии в генератор (5-я ночь)
		if game.day == STORM_DAY and t >= BOLT_AT and not done.has("bolt"):
			done["bolt"] = true
			strike(true)
			if game.lighthouse_on:
				game.lighthouse_on = false
				game.beacon.set_powered(false)
				game.campaign.state.blackout = true
				game.campaign.state.event_done = false
				game.alert("МОЛНИЯ В ГЕНЕРАТОР", "Маяк погас. Доберитесь до генератора — E", 6)
				game.radio.say("light_out", false, true)
	# «мёртвый час»
	if game.day >= 7 and t >= duration * .5 and not done.has("dead_hour"):
		done["dead_hour"] = true
		if is_instance_valid(game.dread):
			game.dread.blackout(3.5)
			game.dread.glitch_pulse(.6)
		game.sound.sfx("whisper", -6, .7, game.player.global_position + Vector3(0, 1.5, -3))
		game.notify("Весь свет на острове разом гаснет. Кто-то шепчет ваше имя.", 4, 1)
		if is_instance_valid(game.hunter):
			game.hunter.noise(game.map_player_position(), 1.0)

func strike(close := false) -> void:
	flash = 1.0
	var at: Vector3 = game.player.global_position + Vector3(rng.randf_range(-25, 25), 6, rng.randf_range(-25, 25))
	game.sound.sfx("thump", -2 if close else -7, rng.randf_range(.45, .6), at)
	game.camera_shake = maxf(game.camera_shake, .35 if close else .15)

func _apply_visuals(delta: float) -> void:
	flash = maxf(0, flash - delta * 3.2)
	var sun: DirectionalLight3D = game.world.get_node_or_null("Sun")
	var env: Environment = game.world.get_node("CoastalAtmosphere").environment
	if flash > 0:
		var k := flash * (0.6 + 0.4 * sin(flash * 40.0))
		if sun != null:
			sun.light_energy += 2.2 * k
			sun.light_color = sun.light_color.lerp(Color("cfe0ff"), k)
		env.ambient_light_energy += .5 * k
	if fog_amount > 0:
		env.fog_density += .014 * fog_amount
		env.fog_light_color = env.fog_light_color.lerp(Color("3a4650"), .45 * fog_amount)
	if storm and is_instance_valid(game.sound.wind):
		game.sound.wind.volume_db += 7.0
		game.camera_shake = maxf(game.camera_shake, .03)

# ---------------------------------------------------------------- сохранение
func save_data() -> Dictionary:
	return {"fearless_told": fearless_told}

func restore(data: Variant) -> void:
	if data is Dictionary:
		fearless_told = bool(data.get("fearless_told", false))
