extends RefCounted
## Все числа баланса в одном месте. Меняйте здесь, а не в коде систем.
## Время в секундах, урон и параметры — в единицах 0–100, если не сказано иное.

# ---------------------------------------------------------------- игрок и выживание
const HUNGER_DRAIN_CAMPAIGN := 0.19        ## сытость/с днём и ночью в кампании
const HUNGER_DRAIN_DEMO := 0.025           ## мягкий расход в демо «Первая смена»
const HUNGER_DRAIN_SPRINT := 0.14          ## доп. расход при беге
const STARVING_DAMAGE := 1.1               ## здоровье/с при нулевой сытости
const HUNGRY_STAMINA_MULT := 0.5           ## множитель восстановления выносливости при голоде
const HUNGRY_AT := 35.0
const STARVING_AT := 15.0

const SANITY_NIGHT_DRAIN := 0.32           ## рассудок/с ночью вне укрытия
const SANITY_DARK_DRAIN := 0.75            ## доп. расход ночью без фонаря
const SANITY_RECOVERY := 0.05              ## рассудок/с в безопасности
const SANITY_BREAK_DAMAGE := 1.0           ## здоровье/с при нулевом рассудке
const SANITY_HALLUCINATE_AT := 38.0        ## ниже — фантомы и выпады
const SANITY_TENSE_AT := 55.0              ## ниже — сердцебиение и виньетка

const COLD_AT := 18.0                      ## тепло ниже — урон от холода
const COLD_DAMAGE := 0.55                  ## здоровье/с при переохлаждении

const LOW_HEALTH_AT := 35.0                ## предупреждение и сердцебиение

# ---------------------------------------------------------------- фонарь
const LANTERN_OIL_MAX := 100.0
const LANTERN_OIL_DRAIN := 0.55            ## масло/с, пока фонарь горит ночью снаружи
const LANTERN_OIL_REFILL_INDOORS := 6.0    ## масло/с в хижине / радиостанции / маяке
const LANTERN_OIL_LOW := 25.0              ## ниже — мерцание и предупреждение
const LANTERN_RELIGHT_AT := 8.0            ## сколько масла нужно, чтобы снова зажечь
const LANTERN_ENERGY := 2.1                ## яркость ручного фонаря
const LANTERN_RANGE := 8.5

# ---------------------------------------------------------------- тени
const SHADOW_DAMAGE_BASE := 15.0
const SHADOW_DAMAGE_PER_DAY := 0.9
const DROWNED_DAMAGE_BONUS := 7.0
const SHADOW_WINDUP := 0.55                ## телеграф удара: столько секунд тень «замахивается»
const DROWNED_WINDUP := 0.8
const SHADOW_ATTACK_COOLDOWN := 1.6
const SHADOW_SPEED := 1.75
const SHADOW_SPEED_PER_DAY := 0.06
const SHADOW_SPEED_MAX_BONUS := 0.9
const LANTERN_FEAR_RADIUS := 3.4           ## фонарь отпугивает тени только вблизи
const SHADOW_FLINCH_TIME := 1.4            ## сколько тень пятится от фонаря
const SHADOW_BRAVE_TIME := 4.5             ## после этого столько секунд не боится фонаря
const SHADOW_EASY_DAYS := 2                ## в первые дни тени всегда боятся фонаря

# ---------------------------------------------------------------- ночные волны
const FIRST_WAVE_AT := 6.0
const FIRST_WAVE_PAUSE := 16.0             ## пауза после первой (мягкой) волны
const WAVE_INTERVAL_EARLY := 16.0          ## интервал на 2-й день
const WAVE_INTERVAL_LATE := 8.0            ## интервал к финалу
const WAVE_MAX_COUNT := 4
const MAX_ALIVE := 6

# ---------------------------------------------------------------- падение в воду
const FALL_Y := -2.0
const FALL_DAMAGE := 4.0
const SAFE_GROUND_SAMPLE := 0.25           ## как часто запоминаем твёрдую землю

# ---------------------------------------------------------------- события дня
const EVENT_GRACE_AFTER_RESPAWN := 4.0
const SHOAL_SECONDS := 65.0

# ---------------------------------------------------------------- ужас
const SCARE_MIN_GAP := 38.0                ## минимум тишины между «пугалками»
const SCARE_FIRST_DELAY := 20.0            ## не пугать в первые секунды ночи
const SCARE_CHANCE_PER_SEC := 0.035        ## базовый шанс в секунду после паузы
const SCARE_TYPE_COOLDOWN := 120.0         ## один и тот же тип не чаще
const SCARE_DAY_CHANCE_MULT := 0.25        ## днём пугаем реже (туман, шаги)

# ---------------------------------------------------------------- шаги
const STEP_VOLUME_DB := -9.0
const STEP_RUN_BOOST_DB := 3.0
const STEP_PITCH_JITTER := 0.08
const STEP_VOLUME_JITTER_DB := 2.0

static func wave_interval(day: int, pressure: float) -> float:
	var t := clampf(float(day - 2) / 11.0, 0.0, 1.0)
	return lerpf(WAVE_INTERVAL_EARLY, WAVE_INTERVAL_LATE, t) / sqrt(maxf(0.3, pressure))

static func wave_size(day: int, wave: int, pressure: float) -> int:
	if wave <= 1:
		return 1
	var base := 1.0 + float(day - 2) * 0.22 + float(wave - 2) * 0.35
	return clampi(roundi(base * pressure), 1, WAVE_MAX_COUNT)

static func shadow_damage(day: int, drowned: bool) -> float:
	return SHADOW_DAMAGE_BASE + day * SHADOW_DAMAGE_PER_DAY + (DROWNED_DAMAGE_BONUS if drowned else 0.0)
