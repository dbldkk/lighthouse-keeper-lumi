extends RefCounted
## Рукодельный стиль интерфейса (v1.3): вахтенный журнал смотрителя.
## Бумага с неровным краем, просмолённые листы для HUD, карандашные рамки, чернильные мазки, штампы.
## Шрифты (SIL OFL 1.1, см. assets/fonts/OFL-*.txt): Old Standard TT — печатный текст журнала,
## Caveat — рукописные пометки, PT Mono — машинописные цифры и бирки.
const SERIF := preload("res://assets/fonts/OldStandard-Regular.ttf")
const SERIF_BOLD := preload("res://assets/fonts/OldStandard-Bold.ttf")
const HAND := preload("res://assets/fonts/Caveat.ttf")
const MONO := preload("res://assets/fonts/PTMono.ttf")
const PAPER_SHEET := preload("res://assets/ui/paper/paper_sheet.png")
const PAPER_CARD := preload("res://assets/ui/paper/paper_card.png")
const TAR_SHEET := preload("res://assets/ui/paper/tar_sheet.png")
const TAR_STRIP := preload("res://assets/ui/paper/tar_strip.png")
const BTN_PENCIL := preload("res://assets/ui/paper/btn_pencil.png")
const BTN_PENCIL_LIGHT := preload("res://assets/ui/paper/btn_pencil_light.png")
const BTN_PRIMARY := preload("res://assets/ui/paper/btn_primary.png")
const BTN_HOVER := preload("res://assets/ui/paper/btn_hover.png")
const BTN_HOVER_LIGHT := preload("res://assets/ui/paper/btn_hover_light.png")
const BAR_FILL := preload("res://assets/ui/paper/bar_fill.png")
const BAR_TRACK := preload("res://assets/ui/paper/bar_track.png")
const STAMP_RECORDED := preload("res://assets/ui/paper/stamp_recorded.png")
const STAMP_DANGER := preload("res://assets/ui/paper/stamp_danger.png")
const SMUDGE := preload("res://assets/ui/paper/smudge.png")

## Палитра: чернила, старая бумага, латунь/охра, сепия, выцветший сургуч.
const INK := Color("1d1812")
const INK_BLUE := Color("27354a")
const PAPER := Color("dccfb0")
const OCHRE := Color("c39a55")
const SEPIA := Color("8e8370")
const RUST := Color("8c2f22")

static var _theme: Theme

static func tex_box(tex: Texture2D, margin: float, content: Vector4 = Vector4(14, 10, 14, 10), modulate := Color.WHITE) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = tex
	b.texture_margin_left = margin
	b.texture_margin_right = margin
	b.texture_margin_top = margin
	b.texture_margin_bottom = margin
	# растягиваем целиком: без швов от повторения середины листа
	b.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	b.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	b.content_margin_left = content.x
	b.content_margin_top = content.y
	b.content_margin_right = content.z
	b.content_margin_bottom = content.w
	b.modulate_color = modulate
	return b

static func paper(modulate := Color.WHITE) -> StyleBoxTexture:
	return tex_box(PAPER_SHEET, 46, Vector4(22, 18, 22, 18), modulate)

static func card(modulate := Color.WHITE) -> StyleBoxTexture:
	return tex_box(PAPER_CARD, 30, Vector4(16, 12, 16, 12), modulate)

static func tar(alpha := 1.0) -> StyleBoxTexture:
	return tex_box(TAR_SHEET, 34, Vector4(14, 10, 14, 10), Color(1, 1, 1, alpha))

static func strip(alpha := 1.0) -> StyleBoxTexture:
	return tex_box(TAR_STRIP, 22, Vector4(14, 8, 14, 8), Color(1, 1, 1, alpha))

static func button_box(kind: String) -> StyleBox:
	match kind:
		"pencil":
			return tex_box(BTN_PENCIL, 14, Vector4(16, 6, 16, 6))
		"pencil_light":
			return tex_box(BTN_PENCIL_LIGHT, 14, Vector4(16, 6, 16, 6))
		"primary":
			return tex_box(BTN_PRIMARY, 16, Vector4(18, 6, 18, 6))
		"hover":
			return tex_box(BTN_HOVER, 18, Vector4(16, 6, 16, 6))
		"hover_light":
			return tex_box(BTN_HOVER_LIGHT, 18, Vector4(16, 6, 16, 6))
	var e := StyleBoxEmpty.new()
	return e

static func bar_box(fill: bool, color: Color) -> StyleBoxTexture:
	var b := tex_box(BAR_FILL if fill else BAR_TRACK, 4, Vector4.ZERO, color if fill else Color(1, 1, 1, 1))
	b.texture_margin_top = 0
	b.texture_margin_bottom = 0
	b.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return b

static func font(kind := "serif") -> Font:
	match kind:
		"hand":
			return HAND
		"mono":
			return MONO
		"bold":
			return SERIF_BOLD
	return SERIF

## Тема на весь интерфейс: шрифт журнала и рукодельные стили по умолчанию.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = SERIF
	t.default_font_size = 16
	t.set_stylebox("panel", "Panel", tar(.94))
	t.set_stylebox("panel", "PanelContainer", tar(.94))
	t.set_stylebox("normal", "Button", button_box("pencil_light"))
	t.set_stylebox("hover", "Button", button_box("hover_light"))
	t.set_stylebox("pressed", "Button", button_box("hover_light"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", Color("f1e6c8"))
	t.set_color("font_pressed_color", "Button", OCHRE)
	t.set_color("font_color", "Label", PAPER)
	for cls in ["OptionButton", "CheckButton", "CheckBox", "LineEdit"]:
		t.set_stylebox("normal", cls, button_box("pencil"))
		t.set_stylebox("hover", cls, button_box("pencil"))
		t.set_stylebox("pressed", cls, button_box("pencil"))
		t.set_stylebox("hover_pressed", cls, button_box("pencil"))
		t.set_stylebox("disabled", cls, button_box("pencil"))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_disabled_color", cls, Color(INK, .55))
		t.set_color("font_color", cls, INK)
		t.set_color("font_hover_color", cls, INK)
		t.set_color("font_pressed_color", cls, INK)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_selected", "TabContainer", button_box("pencil"))
	t.set_stylebox("tab_unselected", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_hovered", "TabContainer", button_box("hover"))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", SEPIA.darkened(.25))
	t.set_color("font_hovered_color", "TabContainer", INK)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(INK, .55)
	slider.content_margin_top = 1
	slider.content_margin_bottom = 1
	t.set_stylebox("slider", "HSlider", slider)
	var area := StyleBoxFlat.new()
	area.bg_color = Color(RUST, .8)
	area.content_margin_top = 1
	area.content_margin_bottom = 1
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var popup := StyleBoxFlat.new()
	popup.bg_color = Color("d6c9a6")
	popup.border_color = Color(INK, .5)
	popup.set_border_width_all(1)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", RUST)
	t.set_stylebox("hover", "PopupMenu", button_box("hover"))
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("d6c9a6")
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	_theme = t
	return t

## Перекрашивает уже построенное поддерево «на бумагу»: светлый текст → чернила, золото → сургуч.
static func inkify(node: Node) -> void:
	if node is Label or node is Button or node is RichTextLabel:
		var c := node as Control
		for key in ["font_color", "default_color"]:
			if c.has_theme_color_override(key):
				c.add_theme_color_override(key, ink_for(c.get_theme_color(key)))
		if node is Label and not c.has_theme_color_override("font_color"):
			c.add_theme_color_override("font_color", INK)
		if node is Button and not (node is OptionButton or node is CheckButton or node is CheckBox):
			var primary: bool = c.has_meta("primary") and bool(c.get_meta("primary"))
			c.add_theme_stylebox_override("normal", button_box("primary" if primary else "pencil"))
			c.add_theme_stylebox_override("hover", button_box("hover"))
			c.add_theme_stylebox_override("pressed", button_box("hover"))
			c.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			c.add_theme_color_override("font_color", RUST if primary else INK)
			c.add_theme_color_override("font_hover_color", Color("f1e6c8"))
			c.add_theme_color_override("font_pressed_color", Color("f1e6c8"))
			c.add_theme_color_override("font_focus_color", RUST if primary else INK)
		if c.has_theme_color_override("font_shadow_color"):
			c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	for child in node.get_children():
		inkify(child)

static func ink_for(c: Color) -> Color:
	var lum := c.get_luminance()
	if c.a < .05:
		return c
	# золото/охра/оранжевое → выцветший сургуч; светлое → чернила; серое → сепия
	if lum > .7:
		return INK
	if c.r > c.b + .15 and c.g > c.b:
		return RUST
	if c.r > c.g + .2:
		return RUST.darkened(.1)
	if lum > .55:
		return INK
	return Color("4a4033")

## Лёгкий наклон «положенного от руки» листа (детерминированно по положению).
static func tilt(c: Control, max_deg := .55) -> void:
	var h := absi(int(c.position.x * 13.0 + c.position.y * 7.0)) % 1000
	c.pivot_offset = c.size * .5
	c.rotation_degrees = (h / 1000.0 * 2.0 - 1.0) * max_deg

static func stamp(parent: Control, tex: Texture2D, at: Vector2, scale := .5, alpha := .82) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = tex.get_size() * scale
	r.position = at
	r.modulate = Color(1, 1, 1, alpha)
	parent.add_child(r)
	return r
