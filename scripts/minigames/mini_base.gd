extends RefCounted
## Основа для отдельных мини-игр. Хост (scripts/minigames.gd) ставит игру на паузу, рисует
## тёмную рамку, частицы, итог и применяет награду или штраф. Наследник описывает механику.
const BAL = preload("res://scripts/balance.gd")
const PAPER := Color("e9e3ce")
const GOLD := Color("deb777")
const TEAL := Color("8fd7c0")
const RED := Color("ff7a5a")
const DIM := Color(1, 1, 1, .15)

var host: Control
var game: Node
var clock := 0.0
var day := 1
var perfect := false
var mistakes := 0
## Чем закончилась неудача: "noise" — шум в темноте, "shock" — удар током,
## "grab" — что-то схватило, "static" — голос в эфире. Хост выбирает штраф по этому полю.
var fail_kind := "noise"

func begin(owner_host: Control) -> void:
	host = owner_host
	game = owner_host.game
	day = maxi(1, int(game.day))
	start()

func start() -> void:
	pass

func title() -> String:
	return ""

func hint() -> String:
	return ""

func controls() -> String:
	return "Пробел / ЛКМ — действие   ·   Esc — отложить"

func tick(_delta: float) -> void:
	pass

## Пробел, E или ЛКМ без привязки к точке.
func act() -> void:
	pass

## Клик ЛКМ в координатах окна. По умолчанию — то же, что пробел.
func click(_at: Vector2) -> void:
	act()

## Дополнительные клавиши (цифры, стрелки). Вернуть true, если клавиша обработана.
func key(_code: int) -> bool:
	return false

func draw(_box: Rect2, _c: Vector2) -> void:
	pass

# ---------------------------------------------------------------- помощники
func finish(ok: bool, text: String) -> void:
	host.perfect = perfect
	host._finish(ok, text)

func done() -> bool:
	return host.result_time > 0

func held() -> bool:
	return host.blowing or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func axis() -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v += 1.0
	return v

func axis2() -> Vector2:
	var v := Vector2(axis(), 0)
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v

func night() -> bool:
	return game.has_method("is_night") and game.is_night()

func sfx(name: String, volume_db := -10.0, pitch := 1.0) -> void:
	if game.sound.has_method("sfx"):
		game.sound.sfx(name, volume_db, pitch)

func shake(amount: float) -> void:
	game.camera_shake = maxf(game.camera_shake, amount)

func text(content: String, at: Vector2, size_px: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := 640.0) -> void:
	host._text(content, at, size_px, color, align, width)

func burst(color: Color, count: int, at: Variant = null) -> void:
	host._burst(color, count, at)

## Пульсирующая «лампа» — мерцание света в мастерской. 0 — темно, 1 — светло.
func lamp(speed := 1.0) -> float:
	var f := 0.75 + 0.25 * sin(clock * 9.0 * speed) * sin(clock * 2.3 * speed + 1.0)
	if fmod(clock * speed + 0.37, 3.1) < 0.18:
		f *= 0.25
	return clampf(f, 0, 1)
