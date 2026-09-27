class_name ShopUI
extends Control
## Station shop, opened with E inside a defense post's aura. Pauses the game.
## Ship upgrades are global; post services (rebuild, turrets, extra flies) apply
## to the post it was opened at.

const UPGRADE_COSTS := {
	"hull": [{"scrap": 20}, {"scrap": 35, "ore": 20}, {"scrap": 55, "ore": 30, "crystal": 2},
			{"scrap": 80, "ore": 45, "crystal": 4}],
	"blaster": [{"ore": 25}, {"ore": 40, "scrap": 15}, {"ore": 60, "scrap": 30, "crystal": 2},
			{"ore": 85, "scrap": 45, "crystal": 5}],
	"missiles": [{"scrap": 30}, {"scrap": 45, "ore": 20}, {"scrap": 65, "ore": 35, "crystal": 3},
			{"scrap": 90, "ore": 50, "crystal": 6}],
	"engine": [{"ore": 20, "scrap": 10}, {"ore": 40, "scrap": 25}, {"ore": 60, "scrap": 40, "crystal": 3}],
	"magnet": [{"ore": 15}, {"ore": 30, "scrap": 10}, {"ore": 50, "scrap": 20, "crystal": 2}],
}
const UPGRADE_INFO := {
	"hull": ["Броня корпуса", "+25 к прочности корабля"],
	"blaster": ["Бластер", "скорострельность, урон, затем 2 и 3 ствола"],
	"missiles": ["Ракеты", "больше ракет в залпе, быстрее перезарядка"],
	"engine": ["Двигатели", "тяга и максимальная скорость"],
	"magnet": ["Магнит", "радиус притягивания ресурсов"],
}
const MAX_EXTRA_FLIES := 3

var post: DefensePost

var _title: Label
var _res_row: HBoxContainer
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = UiTheme.label("СТАНЦИЯ", 22)
	v.add_child(_title)
	_res_row = HBoxContainer.new()
	v.add_child(_res_row)
	v.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	v.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Закрыть  [E]"
	close.pressed.connect(close_shop)
	v.add_child(close)


func open(p: DefensePost) -> void:
	post = p
	visible = true
	get_tree().paused = true
	Game.play_sound("click")
	_rebuild()


func close_shop() -> void:
	visible = false
	get_tree().paused = false


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for c in _res_row.get_children():
		c.queue_free()
	var pname: String = MapView.PLANET_NAMES.get(post.planet.kind, "") if Game.is_alive(post.planet) else ""
	_title.text = "СТАНЦИЯ  %s" % pname.to_upper()
	_res_row.add_child(UiTheme.label("Ресурсы:", 16, UiTheme.DIM))
	_res_row.add_child(UiTheme.cost_row(Game.resources, false))

	if not post.alive:
		_add_row("Восстановить пост", "пост снова начнёт выпускать Мух", -1, 0,
				{"scrap": 40, "ore": 30}, true, func() -> void: post.rebuild())
		return

	var pl := Game.player
	var missing := pl.max_hull - pl.hull if pl else 0.0
	_add_row("Ремонт корпуса", "полностью восстановить прочность", -1, 0,
			{"ore": 5 + int(missing * 0.1)}, missing > 1.0, func() -> void:
				pl.hull = pl.max_hull
				pl.hull_changed.emit(pl.hull, pl.max_hull))

	for key in ["hull", "blaster", "missiles", "engine", "magnet"]:
		var lvl: int = Game.upgrades[key]
		var costs: Array = UPGRADE_COSTS[key]
		var maxed := lvl >= costs.size()
		var cost: Dictionary = {} if maxed else costs[lvl]
		_add_row(UPGRADE_INFO[key][0], UPGRADE_INFO[key][1], lvl, costs.size(), cost, not maxed,
				func() -> void:
					Game.upgrades[key] += 1
					Game.player.apply_upgrades())

	var broken := post.destroyed_turrets()
	if not broken.is_empty():
		var n := broken.size()
		_add_row("Восстановить турели (%d)" % n, "турели у этой планеты", -1, 0,
				{"scrap": 25 * n, "ore": 10 * n}, true, func() -> void:
					for t in broken:
						t.rebuild())
	var extra := post.extra_flies
	_add_row("Муха в охрану", "ещё один защитник у этой планеты", extra, MAX_EXTRA_FLIES,
			{} if extra >= MAX_EXTRA_FLIES else {"scrap": 25 + 15 * extra, "crystal": extra},
			extra < MAX_EXTRA_FLIES, func() -> void: post.extra_flies += 1)


func _add_row(title: String, desc: String, level: int, max_level: int, cost: Dictionary,
		available: bool, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var head := title
	if max_level > 0:
		head += "   " + "■".repeat(level) + "□".repeat(max_level - level)
	info.add_child(UiTheme.label(head, 17))
	info.add_child(UiTheme.label(desc, 13, UiTheme.DIM))
	row.add_child(info)
	if available and not cost.is_empty():
		row.add_child(UiTheme.cost_row(cost))
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 0)
	if max_level > 0 and level >= max_level:
		b.text = "МАКС"
		b.disabled = true
	elif not available:
		b.text = "—"
		b.disabled = true
	else:
		b.text = "Купить"
		b.disabled = not Game.can_afford(cost)
		b.pressed.connect(func() -> void:
			if Game.spend(cost):
				action.call()
				Game.play_sound("buy")
			else:
				Game.play_sound("error")
			_rebuild())
	row.add_child(b)
	_list.add_child(row)
