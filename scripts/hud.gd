class_name Hud
extends CanvasLayer
## In-game overlay: hull / missile / plasma bars, resources, radar minimap,
## full map (Tab), station shop (E), pause menu (Esc) and the game-over screen.

const HINT := "W/S — тяга   A/D — стрейф   мышь — прицел   ЛКМ — бластер   ПКМ — ракеты   Пробел — плазма\nколесо — зум   E — станция (в ауре поста)   Tab — карта сектора   Esc — пауза"

var radar: Radar
var map_view: MapView
var shop: ShopUI
var pause_menu: PauseMenu

var _bars: Control
var _res_labels := {}
var _center_label: Label
var _hull := 1.0
var _shown_hull := 1.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.hud = self

	_bars = Control.new()
	_bars.position = Vector2(20, 18)
	_bars.size = Vector2(340, 80)
	_bars.draw.connect(_draw_bars)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars)

	var res := HBoxContainer.new()
	res.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	res.offset_left = -420
	res.offset_right = -20
	res.offset_top = 14
	res.alignment = BoxContainer.ALIGNMENT_END
	res.add_theme_constant_override("separation", 8)
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(res)
	for k in Game.RESOURCE_TYPES:
		var icon := TextureRect.new()
		icon.texture = Pickup.TEXTURES[k]
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		res.add_child(icon)
		var l := UiTheme.label("0", 20)
		l.custom_minimum_size = Vector2(52, 0)
		res.add_child(l)
		_res_labels[k] = l
	Game.resources_changed.connect(_update_resources)

	_center_label = UiTheme.label("", 28)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_center_label.offset_left = -400
	_center_label.offset_right = 400
	_center_label.offset_top = 120
	_center_label.visible = false
	add_child(_center_label)

	var hint := UiTheme.label(HINT, 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -560
	hint.offset_right = 560
	hint.offset_top = -70
	hint.offset_bottom = -20
	hint.modulate = Color(0.85, 0.9, 1.0, 0.9)
	add_child(hint)
	var tw := hint.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(hint, "modulate:a", 0.0, 2.0)
	tw.tween_callback(hint.queue_free)

	radar = Radar.new()
	radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	radar.offset_left = -226
	radar.offset_top = -226
	radar.offset_right = -16
	radar.offset_bottom = -16
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(radar)

	map_view = MapView.new()
	add_child(map_view)
	shop = ShopUI.new()
	add_child(shop)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)

	var p := Game.player
	if p:
		p.hull_changed.connect(func(h: float, m: float) -> void: _hull = h / m)
		p.died.connect(func() -> void: _show_center("КОРАБЛЬ УНИЧТОЖЕН", UiTheme.BAD))
		p.respawned.connect(func() -> void: _center_label.visible = false)
	Game.game_ended.connect(func(victory: bool) -> void:
		map_view.close()
		shop.visible = false
		pause_menu.show_game_over(victory))


func _unhandled_input(event: InputEvent) -> void:
	if Game.game_over:
		return
	if event.is_action_pressed("pause"):
		if shop.visible:
			shop.close_shop()
		elif map_view.visible:
			map_view.close()
		elif pause_menu.visible:
			pause_menu.close_menu()
		else:
			pause_menu.open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		if shop.visible or pause_menu.visible:
			return
		if map_view.visible:
			map_view.close()
		else:
			map_view.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if pause_menu.visible:
			return
		if shop.visible:
			shop.close_shop()
		else:
			var post := _post_in_range()
			if post:
				map_view.close()
				shop.open(post)
		get_viewport().set_input_as_handled()


func _post_in_range() -> DefensePost:
	for n in get_tree().get_nodes_in_group(&"posts"):
		var post := n as DefensePost
		if post.player_inside():
			return post
	return null


func _update_resources() -> void:
	for k in _res_labels:
		_res_labels[k].text = str(Game.resources[k])


func _show_center(text: String, color: Color) -> void:
	_center_label.text = text
	_center_label.label_settings.font_color = color
	_center_label.visible = true


func _process(delta: float) -> void:
	_shown_hull = lerp(_shown_hull, _hull, 1.0 - exp(-8.0 * delta))
	_bars.queue_redraw()
	var p := Game.player
	if p and p.alive:
		if p.global_position.length() > Game.world_radius * 0.97:
			_show_center("ГРАНИЦА СЕКТОРА", Color(1, 0.8, 0.3, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)))
		elif _center_label.visible:
			_center_label.visible = false


func _draw_bars() -> void:
	var c := _bars
	var font := UiTheme.font()
	var p := Game.player
	var hc := Color(0.35, 0.9, 0.6).lerp(Color(1.0, 0.3, 0.25), 1.0 - _shown_hull)
	_bar(c, font, 0.0, "КОРПУС", _shown_hull, 260.0, 26, hc)
	if p:
		var m := p.missiles.charge()
		_bar(c, font, 25.0, "РАКЕТЫ", m, 160.0, p.missiles.magazine,
				Color(0.45, 0.85, 1.0) if not p.missiles.reloading else Color(0.25, 0.4, 0.6))
		var pc := p.plasma.charge()
		_bar(c, font, 48.0, "ПЛАЗМА", pc, 120.0, 0, Color(0.9, 0.5, 1.0) if pc >= 1.0 else Color(0.45, 0.3, 0.6))


func _bar(c: Control, font: Font, y: float, title: String, value: float, w: float, segs: int, col: Color) -> void:
	c.draw_string(font, Vector2(0, y + 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
	var r := Rect2(76, y + 2, w, 13)
	c.draw_rect(r.grow(2), Color(0.03, 0.02, 0.08))
	c.draw_rect(r, Color(0.12, 0.1, 0.2))
	if segs > 0:
		var sw := w / segs
		for i in segs:
			if (i + 0.5) / segs <= value + 0.001:
				c.draw_rect(Rect2(r.position.x + i * sw + 1, r.position.y + 1, sw - 2, r.size.y - 2), col)
	else:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * clamp(value, 0.0, 1.0), r.size.y)), col)
