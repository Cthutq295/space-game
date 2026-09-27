class_name UiTheme
## Shared pixel-ish UI look: dark panels with a thin bright frame, monospace font.

const BG := Color(0.04, 0.035, 0.09, 0.94)
const FRAME := Color(0.33, 0.5, 0.95)
const TEXT := Color(0.85, 0.9, 1.0)
const DIM := Color(0.5, 0.55, 0.7)
const GOOD := Color(0.45, 0.95, 0.65)
const BAD := Color(1.0, 0.45, 0.4)

static var _font: SystemFont
static var _theme: Theme


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.font_weight = 700
	return _font


static func box(bg: Color, frame: Color, border := 2, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = frame
	sb.set_border_width_all(border)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = false
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", box(BG, FRAME, 2, 16))
	t.set_stylebox("normal", "Button", box(Color(0.1, 0.1, 0.2), Color(0.3, 0.4, 0.75), 2, 6))
	t.set_stylebox("hover", "Button", box(Color(0.16, 0.18, 0.34), Color(0.5, 0.7, 1.0), 2, 6))
	t.set_stylebox("pressed", "Button", box(Color(0.25, 0.3, 0.55), Color(0.7, 0.85, 1.0), 2, 6))
	t.set_stylebox("disabled", "Button", box(Color(0.07, 0.07, 0.12), Color(0.2, 0.22, 0.35), 2, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.42, 0.55))
	t.set_color("font_color", "Label", TEXT)
	_theme = t
	return t


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 4
	ls.outline_color = Color(0.02, 0.02, 0.06)
	l.label_settings = ls
	return l


## Small resource icon + amount, e.g. [ore] 25.
static func cost_row(cost: Dictionary, affordable_check := true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for k in ["ore", "scrap", "crystal"]:
		if not cost.has(k) or cost[k] <= 0:
			continue
		var icon := TextureRect.new()
		icon.texture = Pickup.TEXTURES[k]
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(icon)
		var ok: bool = not affordable_check or Game.resources[k] >= cost[k]
		h.add_child(label(str(cost[k]), 16, TEXT if ok else BAD))
	return h
