class_name UIManager
extends CanvasLayer
## All menus, HUD and panels for THE LAST MOVE, built procedurally so the UI shares one
## theme and stays consistent. The company voice is present in the copy, the stamps and
## the refusal to sound reassuring.

const BG := Color("#0d1117")
const PANEL := Color("#161d27")
const PANEL_2 := Color("#1e2836")
const PAPER := Color("#e8e0cd")
const INK := Color("#2a2620")
const ACCENT := Color("#e8b13a")
const TEXT := Color("#e7e7e1")
const DIM := Color("#8b95a1")
const DANGER := Color("#e0553a")
const GOOD := Color("#5ac48a")
const SPOOKY := Color("#9b7fd4")
const HINT_COLOR := Color("#9ec5ff")

var theme_res: Theme
var menu_root: Control
var hud_root: Control
var panel_root: Control
var lobby_root: Control

var _prompt_label: Label
var _prompt_sub: Label
var _crosshair: Control
var _objectives_box: VBoxContainer
var _timer_label: Label
var _status_label: Label
var _notify_box: VBoxContainer
var _subtitle_panel: PanelContainer
var _subtitle_label: Label
var _subtitle_timer := 0.0
var _compass: CompassArrow
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _chat_lines: VBoxContainer
var _scoreboard: PanelContainer
var _scoreboard_text: RichTextLabel
var _carry_label: Label
var _transmit_dot: ColorRect
var _hud_visible := false
var _notify_cooldown := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	menu_root = _full_rect_control("MenuRoot")
	panel_root = _full_rect_control("PanelRoot")
	hud_root = _full_rect_control("HUDRoot")
	lobby_root = _full_rect_control("LobbyRoot")
	_build_hud()
	Audio.voice_line.connect(show_subtitle)
	if Net.get_node_or_null("VoiceChat") != null:
		Net.get_node("VoiceChat").transmitting_changed.connect(_on_transmit_changed)


func _full_rect_control(n: String) -> Control:
	var c := Control.new()
	c.name = n
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# ------------------------------------------------------------------ theme ---

func _build_theme() -> void:
	theme_res = Theme.new()
	theme_res.default_font_size = 16
	var btn := StyleBoxFlat.new()
	btn.bg_color = PANEL_2
	btn.border_width_left = 2
	btn.border_color = ACCENT
	btn.content_margin_left = 16
	btn.content_margin_right = 16
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	btn.corner_radius_top_left = 2
	btn.corner_radius_top_right = 2
	btn.corner_radius_bottom_left = 2
	btn.corner_radius_bottom_right = 2
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#2a3547")
	var btn_press := btn.duplicate() as StyleBoxFlat
	btn_press.bg_color = Color("#3a4658")
	theme_res.set_stylebox("normal", "Button", btn)
	theme_res.set_stylebox("hover", "Button", btn_hover)
	theme_res.set_stylebox("pressed", "Button", btn_press)
	theme_res.set_stylebox("disabled", "Button", btn)
	theme_res.set_color("font_color", "Button", TEXT)
	theme_res.set_color("font_hover_color", "Button", ACCENT)
	theme_res.set_color("font_color", "Label", TEXT)
	theme_res.set_color("font_color", "RichTextLabel", TEXT)
	var pb := StyleBoxFlat.new()
	pb.bg_color = PANEL_2
	pb.corner_radius_top_left = 2
	pb.corner_radius_top_right = 2
	pb.corner_radius_bottom_left = 2
	pb.corner_radius_bottom_right = 2
	theme_res.set_stylebox("panel", "PanelContainer", pb)
	theme_res.set_stylebox("background", "ProgressBar", pb)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOOD
	theme_res.set_stylebox("fill", "ProgressBar", fill)
	if menu_root:
		menu_root.theme = theme_res


func _label(text: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Audio.play_sfx("ui_click", Vector3.ZERO, -10.0)
		cb.call())
	return b


func _paper_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color("#b9ae95")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, h)
	return p


func _dark_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.97)
	sb.border_color = Color(1, 1, 1, 0.09)
	sb.set_border_width_all(1)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 16
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, h)
	return p


func _center_control(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.position = Vector2.ZERO
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


func _clear(node: Control) -> void:
	for ch in node.get_children():
		ch.queue_free()


# -------------------------------------------------------------- main menu ---

func show_main_menu() -> void:
	close_all_panels()
	_clear(menu_root)
	_clear(lobby_root)
	hud_root.visible = false
	menu_root.visible = true
	menu_root.mouse_filter = Control.MOUSE_FILTER_PASS
	menu_root.theme = theme_res

	var bg := ColorRect.new()
	bg.color = Color("#0a0d12")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	var stripe := ColorRect.new()
	stripe.color = Color(0.91, 0.69, 0.23, 0.9)
	stripe.set_anchors_preset(Control.PRESET_FULL_RECT)
	stripe.anchor_left = 0.0
	stripe.anchor_right = 1.0
	stripe.anchor_top = 0.0
	stripe.anchor_bottom = 0.0
	stripe.offset_bottom = 4
	menu_root.add_child(stripe)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(100, 0)
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	menu_root.add_child(box)

	box.add_child(_label("LAST MOVE", 72, TEXT, true))
	var inc := _label("INCORPORATED", 22, ACCENT)
	box.add_child(inc)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	box.add_child(sp)
	box.add_child(_label("Every house has baggage. Some of it fights back.", 18, DIM))
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 26)
	box.add_child(sp2)

	box.add_child(_button("START SHIFT  (solo)", func(): Game.start_solo()))
	box.add_child(_button("HOST CREW  (1-4 players)", func(): _show_host_dialog()))
	box.add_child(_button("JOIN CREW", func(): _show_join_dialog()))
	box.add_child(_button("SETTINGS", func(): _show_settings()))
	box.add_child(_button("CREDITS & LICENCES", func(): _show_credits()))
	box.add_child(_button("QUIT", func(): get_tree().quit()))

	var footer := _label("Crew credits: %s     Contracts completed: %d" % [
		U.fmt_money(Save.credits()), int(Save.profile.get("contracts_completed", 0))], 15, DIM)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(100, -46)
	menu_root.add_child(footer)

	var legal := _label("© LAST MOVE INCORPORATED. Employee safety is not covered by our insurance policy.", 13, Color(1, 1, 1, 0.3))
	legal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legal.position = Vector2(-560, -40)
	legal.custom_minimum_size = Vector2(520, 0)
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	menu_root.add_child(legal)


func _show_host_dialog() -> void:
	close_all_panels()
	var p := _dark_panel(460, 420)
	_center_control(p)
	panel_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("HOST A CREW", 26, ACCENT, true))
	v.add_child(_label("The crew gathers in the office. Open a port and wait for up to 3 friends.", 14, DIM))
	var name_edit := LineEdit.new()
	name_edit.text = str(Settings.get_value("player_name", "Mover"))
	name_edit.placeholder_text = "Your name"
	v.add_child(_label("Mover name", 13, DIM))
	v.add_child(name_edit)
	var port_edit := LineEdit.new()
	port_edit.text = "27015"
	v.add_child(_label("Port", 13, DIM))
	v.add_child(port_edit)
	var pw_edit := LineEdit.new()
	pw_edit.placeholder_text = "optional"
	v.add_child(_label("Password", 13, DIM))
	v.add_child(pw_edit)
	var err := _label("", 13, DANGER)
	v.add_child(err)
	v.add_child(_button("OPEN THE OFFICE", func():
		if int(port_edit.text) < 1024 or int(port_edit.text) > 65535:
			err.text = "Pick a port between 1024 and 65535."
			return
		if not Game.host_session(int(port_edit.text), pw_edit.text, name_edit.text):
			err.text = "Could not host. Is the port already in use?"
		else:
			close_all_panels()))
	v.add_child(_button("BACK", func(): show_main_menu()))


func _show_join_dialog() -> void:
	close_all_panels()
	var p := _dark_panel(460, 380)
	_center_control(p)
	panel_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("JOIN A CREW", 26, ACCENT, true))
	v.add_child(_label("Ask the host for their address. LAN address for the same network.", 14, DIM))
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	v.add_child(_label("Address", 13, DIM))
	v.add_child(ip_edit)
	var port_edit := LineEdit.new()
	port_edit.text = "27015"
	v.add_child(_label("Port", 13, DIM))
	v.add_child(port_edit)
	var pw_edit := LineEdit.new()
	pw_edit.placeholder_text = "optional"
	v.add_child(_label("Password", 13, DIM))
	v.add_child(pw_edit)
	v.add_child(_button("KNOCK ON THE DOOR", func():
		Game.join_session(ip_edit.text.strip_edges(), int(port_edit.text), pw_edit.text)))
	v.add_child(_button("BACK", func(): show_main_menu()))


func show_connecting() -> void:
	close_all_panels()
	var p := _dark_panel(420, 200)
	_center_control(p)
	panel_root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("CONTACTING DISPATCH…", 22, ACCENT))
	v.add_child(_label("If this takes more than a few seconds, the address or port is wrong,\nor the host's firewall is closed.", 14, DIM))
	v.add_child(_button("CANCEL", func(): Game.go_to_menu()))


# ------------------------------------------------------------------ lobby ---

func show_lobby_panel(solo := false) -> void:
	_clear(lobby_root)
	lobby_root.visible = true
	lobby_root.mouse_filter = Control.MOUSE_FILTER_PASS
	lobby_root.theme = theme_res
	var p := _dark_panel(520, 460)
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.position = Vector2(-560, 0)
	lobby_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.name = "LobbyBox"
	p.add_child(v)
	v.add_child(_label("CREW ROSTER", 24, ACCENT, true))
	var info := _label("Solo shift." if solo else "Session open. Friends can join using your address and port.", 13, DIM)
	v.add_child(info)
	var list := VBoxContainer.new()
	list.name = "PlayerList"
	v.add_child(list)
	var status := _label("", 13, DIM)
	status.name = "Status"
	v.add_child(status)
	v.add_child(_button("READY" if not solo else "ENTER OFFICE", func():
		if solo:
			lobby_root.visible = false
		else:
			Net.set_ready(not bool(Net.players.get(Net.my_id(), {}).get("ready", false)))
			_refresh_lobby()))
	v.add_child(_button("SETTINGS", func(): _show_settings()))
	v.add_child(_button("LEAVE", func(): Game.leave_to_menu()))
	_refresh_lobby()
	Net.players_changed.connect(func(): _refresh_lobby())


func _refresh_lobby() -> void:
	if not lobby_root.visible:
		return
	var list := lobby_root.find_child("PlayerList", true, false)
	var status := lobby_root.find_child("Status", true, false) as Label
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	for pid in Net.players.keys():
		var info: Dictionary = Net.players[pid]
		var row := HBoxContainer.new()
		var name_l := _label(str(info.get("name", "Mover")), 16, TEXT)
		name_l.custom_minimum_size = Vector2(230, 0)
		row.add_child(name_l)
		var ready := bool(info.get("ready", false))
		row.add_child(_label("READY" if ready else "not ready", 14, GOOD if ready else DIM))
		if int(pid) == 1 and Net.is_online():
			row.add_child(_label("  (host)", 13, DIM))
		list.add_child(row)
	if status:
		if Net.is_online():
			status.text = "Players %d/%d   •   all ready: %s" % [Net.players.size(), Net.MAX_PLAYERS, "yes" if Net.all_ready() else "no"]
		else:
			status.text = "Solo shift. The warehouse is quiet."


func hide_lobby() -> void:
	lobby_root.visible = false


# -------------------------------------------------------------------- HUD ---

func _build_hud() -> void:
	hud_root.visible = false
	hud_root.theme = theme_res

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.custom_minimum_size = Vector2(6, 6)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.size = Vector2(4, 4)
	dot.position = Vector2(-2, -2)
	_crosshair.add_child(dot)
	hud_root.add_child(_crosshair)

	_prompt_label = _label("", 18, TEXT)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.position = Vector2(0, 46)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.custom_minimum_size = Vector2(520, 0)
	_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_root.add_child(_prompt_label)
	_prompt_sub = _label("", 14, ACCENT)
	_prompt_sub.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_sub.position = Vector2(0, 72)
	_prompt_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_sub.custom_minimum_size = Vector2(620, 0)
	_prompt_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_root.add_child(_prompt_sub)

	# objectives (top-left)
	var obj_panel := _dark_panel(320, 0)
	obj_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	obj_panel.position = Vector2(22, 22)
	hud_root.add_child(obj_panel)
	_objectives_box = VBoxContainer.new()
	_objectives_box.add_theme_constant_override("separation", 3)
	obj_panel.add_child(_objectives_box)

	# timer (top-centre)
	var timer_panel := _dark_panel(210, 0)
	timer_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_panel.position = Vector2(-105, 18)
	hud_root.add_child(timer_panel)
	var tv := VBoxContainer.new()
	timer_panel.add_child(tv)
	_timer_label = _label("15:00", 34, TEXT, true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_timer_label)
	_status_label = _label("", 12, DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_status_label)

	# compass (top-right)
	_compass = CompassArrow.new()
	_compass.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_compass.position = Vector2(-140, 18)
	hud_root.add_child(_compass)

	# vitals (bottom-left)
	var vitals := VBoxContainer.new()
	vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.position = Vector2(24, -86)
	vitals.custom_minimum_size = Vector2(220, 0)
	hud_root.add_child(vitals)
	_health_bar = ProgressBar.new()
	_health_bar.max_value = 100
	_health_bar.value = 100
	_health_bar.custom_minimum_size = Vector2(220, 12)
	_health_bar.show_percentage = false
	vitals.add_child(_health_bar)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.max_value = 100
	_stamina_bar.value = 100
	_stamina_bar.custom_minimum_size = Vector2(220, 6)
	_stamina_bar.show_percentage = false
	var stam_fill := StyleBoxFlat.new()
	stam_fill.bg_color = ACCENT
	_stamina_bar.add_theme_stylebox_override("fill", stam_fill)
	vitals.add_child(_stamina_bar)

	# carry / equipment
	_carry_label = _label("", 14, ACCENT)
	_carry_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_carry_label.position = Vector2(-200, -64)
	_carry_label.custom_minimum_size = Vector2(400, 0)
	_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(_carry_label)

	# notifications (bottom-right)
	_notify_box = VBoxContainer.new()
	_notify_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_notify_box.position = Vector2(-420, -220)
	_notify_box.custom_minimum_size = Vector2(390, 0)
	_notify_box.alignment = BoxContainer.ALIGNMENT_END
	hud_root.add_child(_notify_box)

	# chat
	_chat_lines = VBoxContainer.new()
	_chat_lines.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_lines.position = Vector2(24, -300)
	_chat_lines.custom_minimum_size = Vector2(420, 0)
	hud_root.add_child(_chat_lines)

	# subtitles
	_subtitle_panel = _dark_panel(620, 0)
	_subtitle_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_panel.position = Vector2(-310, -150)
	_subtitle_panel.visible = false
	hud_root.add_child(_subtitle_panel)
	_subtitle_label = _label("", 17, Color("#f2ead6"))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_panel.add_child(_subtitle_label)

	# voice indicator
	_transmit_dot = ColorRect.new()
	_transmit_dot.color = Color(0.4, 0.9, 0.5)
	_transmit_dot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_transmit_dot.position = Vector2(22, 0)
	_transmit_dot.size = Vector2(9, 9)
	_transmit_dot.visible = false
	hud_root.add_child(_transmit_dot)

	# scoreboard
	_scoreboard = _dark_panel(520, 300)
	_center_control(_scoreboard)
	_scoreboard.visible = false
	hud_root.add_child(_scoreboard)
	_scoreboard_text = RichTextLabel.new()
	_scoreboard_text.bbcode_enabled = true
	_scoreboard_text.custom_minimum_size = Vector2(460, 250)
	_scoreboard.add_child(_scoreboard_text)


func show_hud() -> void:
	hud_root.visible = true
	_hud_visible = true
	_clear(menu_root)
	menu_root.visible = false
	lobby_root.visible = false


func set_scoreboard_visible(v: bool) -> void:
	_scoreboard.visible = v
	if v:
		_refresh_scoreboard()


func _refresh_scoreboard() -> void:
	var lines := "[b]CREW[/b]\n\n"
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		var st := "?"
		if p != null:
			st = "DOWN" if p.is_downed else "OK"
		lines += "%s   %s   %dms\n" % [Net.display_name(int(pid)), st, Net.ping_of(int(pid))]
	if Game.mission:
		lines += "\n[b]CONTRACT[/b]\nContracted delivered: %d/%d\nOptional: %d/%d\nDamage: %s" % [
			Game.mission.required_delivered, Game.mission.required_total,
			Game.mission.optional_delivered, Game.mission.optional_total,
			U.fmt_money(int(Game.mission.property_damage))]
	_scoreboard_text.text = lines


func _process(delta: float) -> void:
	if not _hud_visible:
		return
	var p := Game.local_player()
	if p == null:
		_prompt_label.text = ""
		_prompt_sub.text = ""
		return
	_prompt_label.text = p.prompt_text
	_prompt_sub.text = p.prompt_sub
	_health_bar.value = p.health
	var hf := StyleBoxFlat.new()
	hf.bg_color = DANGER if p.health < 35.0 else GOOD
	_health_bar.add_theme_stylebox_override("fill", hf)
	_stamina_bar.value = p.stamina
	_carry_label.text = ""
	if p.carried != null and is_instance_valid(p.carried):
		var f := p.carried
		_carry_label.text = "%s  •  %s  •  %d/%d movers  •  [Q]/[R] rotate" % [
			f.data.get("name", "Object"), U.fmt_mass(f.weight), f.holders.size(), maxi(1, f.min_carriers)]
	if Game.mission:
		_update_objectives(Game.mission)
		# compass points at the truck
		if Game.mission.truck and p.camera:
			var target := Game.mission.truck.global_position
			_compass.set_bearing(target - p.global_position, p.camera, p.global_position.distance_to(target))
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			_subtitle_panel.visible = false


func _update_objectives(m: MissionManager) -> void:
	for c in _objectives_box.get_children():
		c.queue_free()
	_objectives_box.add_child(_label("CONTRACT", 13, ACCENT, true))
	_objectives_box.add_child(_label(str(m.contract.get("title", "")), 16, TEXT))
	_objectives_box.add_child(_label("Contracted  %d / %d" % [m.required_delivered, m.required_total], 15,
		GOOD if m.required_delivered >= m.required_total else TEXT))
	if m.optional_total > 0:
		_objectives_box.add_child(_label("Optional    %d / %d" % [m.optional_delivered, m.optional_total], 15, DIM))
	if Save.owns_upgrade("detector"):
		var me := Game.get_player(Net.local_id)
		var near := m.nearest_required(me.global_position) if me != null else null
		if near != null:
			_objectives_box.add_child(_label("Detector    %s  %.0f m" % [str(near.data.get("name", "item")), near.global_position.distance_to(me.global_position)], 14, HINT_COLOR))
	var t := m.time_left
	_timer_label.text = U.fmt_clock(absf(t))
	_timer_label.add_theme_color_override("font_color", DANGER if t < 60.0 else (ACCENT if t < 180.0 else TEXT))
	if m.state == MissionManager.MState.OVERDUE:
		_status_label.text = "OVERDUE  •  pay is being reduced"
		_status_label.add_theme_color_override("font_color", DANGER)
	elif t < 120.0:
		_status_label.text = "deadline approaching"
		_status_label.add_theme_color_override("font_color", ACCENT)
	else:
		_status_label.text = "%d/%d movers on site" % [Net.players.size(), Net.MAX_PLAYERS]


func notify(text: String, kind := "info") -> void:
	if _notify_box == null:
		return
	var color := TEXT
	match kind:
		"warning":
			color = ACCENT
		"damage":
			color = DANGER
		"good":
			color = GOOD
		"spooky":
			color = SPOOKY
		"hint":
			color = HINT_COLOR
	var l := _label(text, 15, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.86)
	sb.set_border_width_all(1)
	sb.border_color = Color(color.r, color.g, color.b, 0.4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(l)
	_notify_box.add_child(panel)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)
	while _notify_box.get_child_count() > 5:
		_notify_box.get_child(0).queue_free()
		break


func show_subtitle(text: String, seconds := 4.0) -> void:
	if not bool(Settings.get_value("subtitles", true)):
		return
	_subtitle_label.text = text
	_subtitle_panel.visible = true
	_subtitle_timer = seconds
	_subtitle_panel.modulate.a = 1.0


func chat(from_id: int, text: String) -> void:
	var l := _label("%s: %s" % [Net.display_name(from_id), text], 14, TEXT)
	_chat_lines.add_child(l)
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
	while _chat_lines.get_child_count() > 6:
		_chat_lines.get_child(0).free()
		break


func _on_transmit_changed(t: bool) -> void:
	if _transmit_dot:
		_transmit_dot.visible = t


# ----------------------------------------------------------------- panels ---

func close_all_panels() -> void:
	_clear(panel_root)
	if hud_root:
		hud_root.visible = false
		_hud_visible = false
	if lobby_root:
		lobby_root.visible = false


func _modal(p: Control) -> void:
	panel_root.add_child(p)
	panel_root.mouse_filter = Control.MOUSE_FILTER_PASS


func show_pause() -> void:
	var p := _dark_panel(420, 420)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("SHIFT PAUSED", 26, ACCENT, true))
	v.add_child(_label("The clock stops. The house does not.", 14, DIM))
	v.add_child(_button("RESUME", func():
		close_all_panels()
		Game.toggle_pause()))
	v.add_child(_button("SETTINGS", func(): _show_settings()))
	v.add_child(_button("LEAVE CONTRACT (forfeit)", func():
		close_all_panels()
		Game.toggle_pause()
		if Game.mission:
			Game.mission.fail_mission("Crew abandoned the contract.")))
	if not Net.is_online():
		v.add_child(_button("QUIT TO MENU", func():
			close_all_panels()
			Game.is_paused = false
			Engine.time_scale = 1.0
			Game.leave_to_menu()))
	v.add_child(_label("Controls: WASD move • Shift sprint • Ctrl crouch • E grab/interact\nQ/R rotate • G throw • F flashlight • V voice • Tab crew", 12, DIM))


func show_contract_briefing() -> void:
	if Game.mission == null:
		return
	open_contract(true)


func open_contract(briefing := false) -> void:
	close_all_panels()
	if Game.mission == null:
		return
	var m := Game.mission
	var p := _paper_panel(640, 620)
	_center_control(p)
	_modal(p)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 560)
	p.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(v)
	v.add_child(_label(str(m.contract.get("code", "PROPERTY")), 13, Color("#8a7a52")))
	v.add_child(_label(str(m.contract.get("title", "Contract")).to_upper(), 28, INK, true))
	v.add_child(_label(str(m.contract.get("subtitle", "")), 15, Color("#5c5348")))
	v.add_child(_label("— — — — — — — — — — — — — — — — — — — — — — —", 13, Color("#a89c82")))
	v.add_child(_label("BRIEFING", 13, Color("#8a7a52")))
	v.add_child(_label(str(m.contract.get("briefing", "")), 15, INK))
	v.add_child(_label("CONTRACTED ITEMS", 13, Color("#8a7a52")))
	for item in m.contract.get("required", []):
		v.add_child(_label("•  %s   (%s)   %s" % [item.get("name", ""), item.get("room", ""), U.fmt_money(int(item.get("value", 0)))], 15, INK))
	if not m.contract.get("optional", []).is_empty():
		v.add_child(_label("OPTIONAL (bonus payout)", 13, Color("#8a7a52")))
		for item in m.contract.get("optional", []):
			v.add_child(_label("•  %s   (%s)" % [item.get("name", ""), item.get("room", "")], 15, Color("#4a4438")))
	v.add_child(_label("DEADLINE  %s" % U.fmt_clock(m.time_total), 15, INK))
	if not m.contract.get("modifiers", []).is_empty():
		v.add_child(_label("CONTRACT MODIFIERS", 13, Color("#8a7a52")))
		for mod in m.contract.get("modifiers", []):
			v.add_child(_label("•  %s — %s" % [mod.get("name", ""), mod.get("desc", "")], 14, Color("#6b3a2a")))
	var memo_index := int(Game.mission.contract.get("story_index", -1))
	if memo_index >= 0:
		var memo: Dictionary = DB.story_beat(memo_index)
		if not memo.is_empty():
			v.add_child(_label(str(memo.get("title", "")), 13, Color("#6b3a2a")))
			v.add_child(_label(str(memo.get("text", "")), 14, Color("#5c5348")))
	v.add_child(_label("DISPATCH NOTES", 13, Color("#8a7a52")))
	for note in m.contract.get("notes", []):
		v.add_child(_label(str(note), 14, Color("#4a4438")))
	if m.contract.has("extra_note"):
		v.add_child(_label(str(m.contract.get("extra_note", "")), 14, Color("#6b3a2a")))
	v.add_child(_label("— — — — — — — — — — — — — — — — — — — — — — —", 13, Color("#a89c82")))
	v.add_child(_label("Employee safety is not covered by our insurance policy.", 12, Color("#8a7a52")))
	v.add_child(_button("CLOSE", func(): close_all_panels()))


func show_results(result: Dictionary) -> void:
	close_all_panels()
	var p := _paper_panel(720, 660)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_label("PERFORMANCE EVALUATION", 13, Color("#8a7a52")))
	v.add_child(_label(str(result.get("title", "Contract")).to_upper(), 26, INK, true))
	var rep: Dictionary = result.get("report", {})
	var open_line := _label(str(rep.get("open", "")), 16, INK)
	v.add_child(open_line)
	for line in rep.get("body", []):
		v.add_child(_label(str(line), 15, Color("#4a4438")))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	_kv(grid, "Contracted delivered", "%d / %d" % [int(result.get("required_delivered", 0)), int(result.get("required_total", 0))])
	_kv(grid, "Optional delivered", "%d / %d" % [int(result.get("optional_delivered", 0)), int(result.get("optional_total", 0))])
	_kv(grid, "Value recovered", U.fmt_money(int(result.get("delivered_value", 0))))
	_kv(grid, "Property damage", U.fmt_money(int(result.get("damage_penalty", 0))))
	_kv(grid, "Crew lost", str(int(result.get("crew_lost", 0))))
	_kv(grid, "Time remaining", U.fmt_clock(maxf(0.0, float(result.get("time_left", 0.0)))))
	v.add_child(_label(str(rep.get("close", "")), 15, Color("#6b3a2a")))
	var pay := _label("PAYOUT: %s" % U.fmt_money(int(result.get("payout", 0))), 24, INK, true)
	v.add_child(pay)
	v.add_child(_label("Credits are shared by the crew.", 13, Color("#8a7a52")))
	v.add_child(_button("RETURN TO OFFICE", func():
		close_all_panels()
		if Net.is_host():
			Game.return_to_headquarters()
		else:
			Game.go_to_menu()))
	v.add_child(_button("MAIN MENU", func():
		close_all_panels()
		Game.leave_to_menu()))


## Campaign endings. Shown once, after the final contract, before the crew goes home.
func show_epilogue(success: bool) -> void:
	close_all_panels()
	var data: Dictionary = DB.ending("success" if success else "partial")
	if data.is_empty():
		return
	var p := _paper_panel(720, 700)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("FINAL DELIVERY", 13, Color("#8a7a52")))
	v.add_child(_label(str(data.get("title", "")), 26, INK, true))
	for para in data.get("body", []):
		var l := _label(str(para), 15, Color("#3a3428"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(660, 0)
		v.add_child(l)
	v.add_child(_label("— — — — — — — — — — — — — — — — — — — — — — —", 13, Color("#a89c82")))
	v.add_child(_label(str(data.get("footer", "")), 14, Color("#6b3a2a")))
	v.add_child(_button("CLOCK OUT", func():
		close_all_panels()
		if Net.is_host():
			Game.return_to_headquarters()
		else:
			Game.go_to_menu()))
	Audio.play_music("result_sting", 1.0)
	Audio.play_voice("training_05", "Dispatch: Thank you for your service. The company has no further comment.", -2.0)


func _kv(grid: GridContainer, k: String, val: String) -> void:
	grid.add_child(_label(k, 15, Color("#5c5348")))
	grid.add_child(_label(val, 15, INK, true))


# --------------------------------------------------------------- settings ---

func _show_settings() -> void:
	var p := _dark_panel(680, 640)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_label("SETTINGS", 24, ACCENT, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 520)
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(600, 0)
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)

	inner.add_child(_label("DISPLAY", 14, ACCENT))
	_check(inner, "Fullscreen", "fullscreen")
	_check(inner, "VSync", "vsync")
	_slider(inner, "Render scale", "render_scale", 0.5, 1.0, 0.05)
	_option(inner, "Anti-aliasing", "aa", ["Off", "2x MSAA", "4x MSAA"])
	_option(inner, "Shadows", "shadows", ["Off", "Low", "High"])
	_option(inner, "FPS limit", "fps_limit", ["Unlimited", "60", "120", "144"], [0, 60, 120, 144])

	inner.add_child(_label("AUDIO", 14, ACCENT))
	_slider(inner, "Master", "vol_master", 0.0, 1.0, 0.05)
	_slider(inner, "Music", "vol_music", 0.0, 1.0, 0.05)
	_slider(inner, "Effects", "vol_sfx", 0.0, 1.0, 0.05)
	_slider(inner, "Ambience", "vol_ambience", 0.0, 1.0, 0.05)
	_slider(inner, "Voice", "vol_voice", 0.0, 1.0, 0.05)

	inner.add_child(_label("VOICE CHAT", 14, ACCENT))
	_check(inner, "Voice enabled", "voice_enabled")
	_check(inner, "Push to talk (V)", "voice_push_to_talk")
	_slider(inner, "Microphone gain", "mic_gain", 0.2, 3.0, 0.1)

	inner.add_child(_label("CONTROLS", 14, ACCENT))
	_slider(inner, "Mouse sensitivity", "sensitivity", 0.2, 3.0, 0.05)
	_slider(inner, "Field of view", "fov", 70.0, 110.0, 1.0)
	_check(inner, "Invert Y", "invert_y")

	inner.add_child(_label("GUIDANCE", 14, ACCENT))
	_check(inner, "First-run hints", "hints")
	inner.add_child(_label("  Hints teach one mechanic each, once per profile.", 12, DIM))
	inner.add_child(_button("REPLAY ALL HINTS", func():
		Save.clear_hints()
		notify("Hints will be shown again from the next contract.", "good")))

	inner.add_child(_label("COMFORT & ACCESSIBILITY", 14, ACCENT))
	_slider(inner, "Head bob", "head_bob", 0.0, 1.0, 0.05)
	_slider(inner, "View sway", "view_sway", 0.0, 1.0, 0.05)
	_slider(inner, "Camera shake", "camera_shake", 0.0, 1.0, 0.05)
	_check(inner, "Subtitles", "subtitles")
	_check(inner, "Reduce flashing", "reduce_flashing")

	v.add_child(_button("CLOSE", func():
		close_all_panels()
		if Game.state == Game.State.MISSION or Game.state == Game.State.HEADQUARTERS:
			Game.is_paused = false
			Engine.time_scale = 1.0
			Game.ui.show_hud()))


func _check(parent: VBoxContainer, text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(Settings.get_value(key, false))
	cb.toggled.connect(func(v: bool): Settings.set_value(key, v))
	parent.add_child(cb)


func _slider(parent: VBoxContainer, text: String, key: String, mn: float, mx: float, step: float) -> void:
	var row := HBoxContainer.new()
	var l := _label(text, 14, TEXT)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_value(key, mn))
	s.custom_minimum_size = Vector2(320, 18)
	s.value_changed.connect(func(v: float): Settings.set_value(key, v))
	row.add_child(s)
	parent.add_child(row)


func _option(parent: VBoxContainer, text: String, key: String, options: Array, values: Array = []) -> void:
	var row := HBoxContainer.new()
	var l := _label(text, 14, TEXT)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var o := OptionButton.new()
	for i in options.size():
		o.add_item(str(options[i]), i)
	o.selected = int(Settings.get_value(key, 0)) if values.is_empty() else maxi(0, values.find(int(Settings.get_value(key, 0))))
	o.item_selected.connect(func(idx: int):
		var value = idx if values.is_empty() else values[idx]
		Settings.set_value(key, value))
	row.add_child(o)
	parent.add_child(row)


func _show_credits() -> void:
	var p := _dark_panel(620, 520)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("CREDITS", 24, ACCENT, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(560, 400)
	text.text = """[b]THE LAST MOVE[/b]
A cooperative physics comedy by LAST MOVE INCORPORATED (the studio, not the employer).

[b]Engine[/b]           Godot Engine 4.6.3 (MIT licence)
[b]Art[/b]              procedurally generated in-engine (original work)
[b]Audio[/b]            synthesised from scratch by tools/generate_audio.py (original work)
[b]Voice[/b]            espeak-ng speech synthesis (GPLv3 runtime, output is original)
[b]Fonts[/b]            Godot default (Open Sans derived)

No third-party art, audio or models are used. Nothing was extracted from
another game. Full attribution in documentation/LICENSES_AND_ATTRIBUTION.md.

[b]Disclaimer[/b]
Every house has baggage. Some of it fights back. Employee safety is not
covered by our insurance policy."""
	v.add_child(text)
	v.add_child(_button("CLOSE", func(): close_all_panels()))


# ------------------------------------------------------------------- shop ---

func open_shop() -> void:
	close_all_panels()
	var p := _dark_panel(760, 640)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_label("EQUIPMENT STORAGE", 24, ACCENT, true))
	v.add_child(_label("Crew credits: %s   (shared)" % U.fmt_money(Save.credits()), 15, TEXT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 500)
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(680, 0)
	scroll.add_child(inner)
	for up in DB.upgrades:
		if str(up.get("category", "")) == "cosmetic":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(520, 0)
		info.add_child(_label(str(up.get("name", "")), 16, TEXT, true))
		info.add_child(_label(str(up.get("desc", "")), 13, DIM))
		row.add_child(info)
		var owned := Save.owns_upgrade(str(up.get("id", "")))
		var b := _button("OWNED" if owned else U.fmt_money(int(up.get("cost", 0))), func():
			if Game.buy_upgrade(str(up.get("id", ""))):
				open_shop())
		b.disabled = owned
		b.custom_minimum_size = Vector2(120, 0)
		row.add_child(b)
		inner.add_child(row)
	v.add_child(_button("CLOSE", func(): close_all_panels()))


func open_cosmetics() -> void:
	close_all_panels()
	var p := _dark_panel(760, 640)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("UNIFORM LOCKER", 24, ACCENT, true))
	v.add_child(_label("Crew credits: %s" % U.fmt_money(Save.credits()), 15, TEXT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 520)
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(680, 0)
	scroll.add_child(inner)
	for slot in ["uniform", "hat", "gloves", "boots"]:
		inner.add_child(_label(slot.to_upper(), 14, ACCENT))
		for c in DB.cosmetics_for_slot(slot):
			var row := HBoxContainer.new()
			var swatch := ColorRect.new()
			swatch.color = Color(str(c.get("color", "#888888")))
			swatch.custom_minimum_size = Vector2(22, 22)
			row.add_child(swatch)
			var l := _label(str(c.get("name", "")), 15, TEXT)
			l.custom_minimum_size = Vector2(360, 0)
			row.add_child(l)
			var owned := Save.owns_cosmetic(str(c.get("id", "")))
			var equipped := str(Save.equipped().get(slot, "")) == str(c.get("id", ""))
			var b := _button("WEAR" if owned else U.fmt_money(int(c.get("cost", 0))), func():
				if owned:
					Save.equip_cosmetic(str(c.get("id", "")))
					Game.local_player().body_model.setup(Save.equipped())
				else:
					Game.buy_cosmetic(str(c.get("id", "")))
				open_cosmetics())
			b.disabled = equipped
			b.text = "WEARING" if equipped else b.text
			b.custom_minimum_size = Vector2(110, 0)
			row.add_child(b)
			inner.add_child(row)
	v.add_child(_button("CLOSE", func(): close_all_panels()))


func open_progress() -> void:
	close_all_panels()
	var p := _dark_panel(620, 560)
	_center_control(p)
	_modal(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("COMPANY PERFORMANCE BOARD", 22, ACCENT, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(560, 420)
	var lines := "[b]Crew credits[/b]  %s\n[b]Contracts completed[/b]  %d\n\n" % [
		U.fmt_money(Save.credits()), int(Save.profile.get("contracts_completed", 0))]
	lines += "[b]PROPERTIES[/b]\n"
	for prop in DB.properties:
		var done := Save.has_completed(str(prop["id"]))
		var unlocked := Save.is_property_unlocked(str(prop["id"]))
		var state_txt := "COMPLETE" if done else ("available" if unlocked else "locked")
		lines += "%s  %-28s %s\n" % [prop.get("code", ""), prop.get("title", ""), state_txt]
	lines += "\n[b]ACHIEVEMENTS[/b]\n"
	for a in DB.achievement_list():
		var got := Save.has_achievement(str(a["id"]))
		lines += "%s %s\n" % ["[x]" if got else "[ ]", a.get("name", "")]
	text.text = lines
	v.add_child(text)
	v.add_child(_button("CLOSE", func(): close_all_panels()))
