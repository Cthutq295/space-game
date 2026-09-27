class_name PauseMenu
extends Control
## Esc menu: resume, control scheme, music, restart, quit. Also the game-over screen.

const SCHEMES := ["W/S тяга по носу, A/D стрейф, нос за мышью", "Классика: A/D поворот, W/S тяга",
		"WASD по сторонам экрана, нос за мышью"]

var _panel_box: VBoxContainer
var _title: Label
var _subtitle: Label
var _resume: Button
var _scheme: Button
var _music: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	cc.add_child(panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 10)
	panel.add_child(_panel_box)
	_title = UiTheme.label("ПАУЗА", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(_title)
	_subtitle = UiTheme.label("", 16, UiTheme.DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(_subtitle)
	_resume = _button("Продолжить", close_menu)
	_scheme = _button("", func() -> void:
		Game.control_scheme = (Game.control_scheme + 1) % SCHEMES.size()
		_refresh())
	_music = _button("", func() -> void:
		Game.music.stream_paused = not Game.music.stream_paused
		_refresh())
	_button("Начать заново", restart)
	_button("Выйти", func() -> void: get_tree().quit())
	var help := UiTheme.label("ЛКМ — бластер   ПКМ — ракеты   Пробел — плазма\nколесо — зум   E — станция   Tab — карта   M — музыка   F11 — экран", 13, UiTheme.DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(help)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void:
		Game.play_sound("click")
		cb.call())
	_panel_box.add_child(b)
	return b


func _refresh() -> void:
	_scheme.text = "Управление: " + SCHEMES[Game.control_scheme]
	_music.text = "Музыка: " + ("выкл" if Game.music.stream_paused else "вкл")


func open_menu() -> void:
	_title.text = "ПАУЗА"
	_subtitle.text = ""
	_resume.visible = true
	_refresh()
	visible = true
	get_tree().paused = true


func close_menu() -> void:
	visible = false
	get_tree().paused = false


func show_game_over(victory: bool) -> void:
	var d := Game.director
	_title.text = "СЕКТОР УДЕРЖАН" if victory else "СЕКТОР ПОТЕРЯН"
	_title.label_settings.font_color = UiTheme.GOOD if victory else UiTheme.BAD
	var saved := Game.planets.size()
	_subtitle.text = "Волн: %d     Планет уцелело: %d из 5" % [d.wave if d else 0, saved]
	_resume.visible = false
	_refresh()
	visible = true
	get_tree().paused = true


func restart() -> void:
	get_tree().paused = false
	Game.reset()
	get_tree().reload_current_scene()
