extends Node
## Ночь без света маяка опасна по-настоящему (v1.3):
## - маяк не горит → рассудок тает быстрее, охотник смелее и сам выходит на ваш след;
## - полная темнота (маяк не горит, фонарь погас/выключен, вы снаружи, рядом нет ракеты или костра)
##   копит «тьму»: предупреждения на 40% и 70%, на 100% темнота начинает отнимать здоровье —
##   до смерти, если так и не найти свет. Свет или помещение быстро сбрасывают шкалу.
const DARK_LIMIT := 45.0            ## секунд полной темноты до урона
const DARK_DAMAGE := 1.5            ## здоровья в секунду после предела (медленно, с плашкой и сердцебиением)
const DARK_RECOVER := 3.0           ## во сколько раз быстрее шкала спадает на свету
const UNLIT_SANITY := 0.25          ## доп. расход рассудка/с ночью, пока маяк не горит
const UNLIT_AGGRESSION := 0.3       ## прибавка к смелости охотника без маяка
const LURE_EVERY := 14.0            ## без маяка охотник раз в столько секунд «слышит» смотрителя

var game: Node
var level := 0.0                    ## 0..1 — шкала полной темноты
var warned := 0
var lure_clock := LURE_EVERY
var unlit_night := false

func reset() -> void:
	level = 0
	warned = 0
	lure_clock = LURE_EVERY
	unlit_night = false

func active_night() -> bool:
	return game.campaign.enabled and bool(game.campaign.state.night) and not game.first_shift_demo.active() and game.day >= 2

func sheltered() -> bool:
	return game.lighthouse_interior.active or not game.building_interiors.active.is_empty() or game.hunter.hiding()

func in_full_darkness() -> bool:
	if not active_night() or game.lighthouse_on or sheltered():
		return false
	if game.player.lantern_on:
		return false
	if is_instance_valid(game.supplies) and game.supplies.flare_time > 0:
		return false
	if is_instance_valid(game.hunter) and game.hunter._in_light(game.player.global_position):
		return false
	return true

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.paused or game.finished:
		return
	tick(delta)

func tick(delta: float) -> void:
	unlit_night = active_night() and not game.lighthouse_on
	if not unlit_night:
		level = maxf(0, level - delta * DARK_RECOVER / DARK_LIMIT)
		if level <= 0:
			warned = 0
		return
	# маяк не горит: рассудок и охотник
	if not sheltered():
		game.sanity = maxf(0, game.sanity - UNLIT_SANITY * delta)
	lure_clock -= delta
	if lure_clock <= 0:
		lure_clock = LURE_EVERY * (0.6 if in_full_darkness() else 1.0)
		if is_instance_valid(game.hunter) and game.hunter.active and game.hunter.space.is_empty() and not sheltered():
			game.hunter.noise(game.map_player_position(), 1.0)
	# полная темнота
	var dark := in_full_darkness()
	if dark:
		level = minf(1.0, level + delta / DARK_LIMIT)
	else:
		level = maxf(0, level - delta * DARK_RECOVER / DARK_LIMIT)
	if dark and level >= .4:
		game.drain_warning("dark")
	if level >= .4 and warned < 1:
		warned = 1
		game.alert("ТЕМНОТА", "Без света долго не протянуть. Фонарь (F), ракета (X), костёр или помещение", 5)
		game.sound.cue("tell")
	if level >= .7 and warned < 2:
		warned = 2
		game.alert("ТЕМНОТА СГУЩАЕТСЯ", "Ещё немного — и она начнёт забирать вас. Найдите свет!", 5)
		game.sound.cue("alarm")
		if is_instance_valid(game.dread):
			game.dread.glitch_pulse(.6)
	if level >= 1.0 and dark:
		if warned < 3:
			warned = 3
			game.notify("Темнота смыкается. Каждый вдох — боль. Свет! Сейчас же!", 4, 2)
		game.drain_health(DARK_DAMAGE, delta, "dark")
		game.camera_shake = maxf(game.camera_shake, .08)
	if level < .3:
		warned = mini(warned, 0)

func hunter_bonus() -> float:
	return UNLIT_AGGRESSION if unlit_night else 0.0
