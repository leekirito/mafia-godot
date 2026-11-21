extends Node3D
const Session = preload("res://scripts/session.gd")
const Room = preload("res://scripts/room.gd")
var session: Node
var room: Node3D
var ui: Control
var menu: PanelContainer
var lobby: PanelContainer
var hud: Control
var targets: VBoxContainer
var lobby_people: Label
var phase_label: Label
var clock_label: Label
var role_label: Label
var instruction: Label
var history_label: Label
var chat_log: RichTextLabel
var chat_input: LineEdit
var intel_label: Label
var status_label: Label
var name_input: LineEdit
var address_input: LineEdit
var role_texture: TextureRect
var secret_panel: PanelContainer
var rules_panel: PanelContainer
var settings_panel: PanelContainer
var phase_key := ""
var target_key := ""
var toast_time := 0.0
var ambience: AudioStreamPlayer
var master_volume := 0.22
var grain: ColorRect
var confirm_leave: ConfirmationDialog
const GOLD := Color("c6ad7b")
const MUTED := Color("8a9188")
const INK := Color("101713")

func _ready() -> void:
	room = Room.new()
	add_child(room)
	session = Session.new()
	add_child(session)
	build_ui()
	session.changed.connect(refresh)
	session.notice.connect(show_notice)
	build_audio()
	load_preferences()
	refresh()
	# Explicit launch switches support genuine separate-process network tests.
	var args := OS.get_cmdline_user_args()
	if "--host" in args: session.host_game("Host")
	if "--join-local" in args: session.join_game("Guest", "127.0.0.1")
	if "--practice" in args: session.host_game("You", true)

func style(bg: Color, border := Color("474b3c"), width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

func label(parent: Node, text: String, size := 18, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func column(parent: Node, separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v

func panel(parent: Node, pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", style(Color(0.035, 0.052, 0.043, 0.96)))
	parent.add_child(p)
	return p

func wrap_label(parent: Node, text: String, size := 16, color := MUTED) -> Label:
	var l := label(parent, text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Button", GOLD)
	theme.set_color("font_hover_color", "Button", Color("f6e5be"))
	theme.set_stylebox("normal", "Button", style(Color("1b251e")))
	theme.set_stylebox("hover", "Button", style(Color("334334"), GOLD))
	theme.set_stylebox("pressed", "Button", style(Color("48523a"), GOLD))
	theme.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), GOLD, 2))
	theme.set_stylebox("normal", "LineEdit", style(Color("0d120f")))
	theme.set_color("font_color", "LineEdit", Color("e0d5b8"))
	ui.theme = theme
	# Film texture is a light overlay, never applied to UI text.
	grain = ColorRect.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment(){vec2 p=UV-0.5; float v=smoothstep(0.18,0.72,length(p)); float n=fract(sin(dot(FRAGCOORD.xy+floor(TIME*12.0),vec2(12.9898,78.233)))*43758.5453); COLOR=vec4(vec3(n*0.15),v*0.42+n*0.04);}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	grain.material = sm
	ui.add_child(grain)
	var top := HBoxContainer.new()
	top.position = Vector2(36, 22)
	top.size.x = 1208
	top.add_theme_constant_override("separation", 18)
	ui.add_child(top)
	label(top, "M A F I A", 22)
	var edition := label(top, "THE LAST TABLE  /  PROTOTYPE 01", 13, MUTED)
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(top, "RULES", func(): rules_panel.visible = not rules_panel.visible)
	button(top, "SETTINGS", func(): settings_panel.visible = not settings_panel.visible)
	button(top, "LEAVE", func():
		if session.mode != "menu": confirm_leave.popup_centered()
		else: get_tree().quit())
	menu = panel(ui, Vector2(60, 132), Vector2(400, 530))
	var v := column(menu, 12)
	label(v, "TRUST IS A\nDEATH SENTENCE.", 35, Color("e7dbbf"))
	wrap_label(v, "One table. Hidden loyalties.\nSomeone will not see the morning.", 17)
	label(v, "YOUR NAME", 12)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Guest"
	name_input.max_length = 20
	name_input.custom_minimum_size.y = 40
	v.add_child(name_input)
	button(v, "ENTER PRACTICE  ·  9 STAND-INS", func(): save_preferences(); session.host_game(name_input.text, true))
	button(v, "HOST A PRIVATE TABLE", func(): save_preferences(); session.host_game(name_input.text))
	var row := HBoxContainer.new()
	v.add_child(row)
	address_input = LineEdit.new()
	address_input.placeholder_text = "Host IP address"
	address_input.text = "127.0.0.1"
	address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address_input)
	button(row, "JOIN", func(): save_preferences(); session.join_game(name_input.text, address_input.text))
	wrap_label(v, "LAN / direct IP · UDP 27840\nInternet hosting requires port forwarding.\nRoom codes and voice are not in this build.", 13)
	lobby = panel(ui, Vector2(60, 132), Vector2(410, 500))
	v = column(lobby)
	label(v, "TAKE YOUR SEAT", 30)
	wrap_label(v, "5–12 seats. Share the host’s IP address.\nStand-ins can fill a small table.")
	lobby_people = label(v, "", 18, Color("ddd4bc"))
	button(v, "ADD A STAND-IN", func(): session.add_bot())
	button(v, "DEAL THE CARDS", func(): session.start_game())
	wrap_label(v, "Only the host can add stand-ins or deal.\nDisconnected players become stand-ins.\nRejoining an active match is not yet supported.", 13)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var phase_panel := panel(hud, Vector2(430, 84), Vector2(420, 84))
	v = column(phase_panel, 4)
	phase_label = label(v, "NIGHT 01", 25)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label = label(v, "", 14, MUTED)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var left := panel(hud, Vector2(26, 380), Vector2(290, 310))
	v = column(left, 8)
	role_label = label(v, "YOUR CARD IS SEALED", 15)
	button(v, "INSPECT CARD  [TAB]", toggle_card)
	intel_label = wrap_label(v, "", 14, GOLD)
	label(v, "THE RECORD", 12, MUTED)
	history_label = wrap_label(v, "", 14, Color("cdc5af"))
	var right := panel(hud, Vector2(980, 184), Vector2(274, 506))
	v = column(right, 8)
	instruction = wrap_label(v, "", 16, GOLD)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	targets = column(scroll, 5)
	targets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var practice_button := button(v, "SKIP PHASE  [PRACTICE]", func(): session.advance())
	practice_button.name = "PracticeSkip"
	var chat_panel := panel(hud, Vector2(336, 490), Vector2(624, 200))
	v = column(chat_panel, 6)
	label(v, "TABLE CHANNEL  /  ENTER TO SEND", 12, MUTED)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size.y = 98
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.bbcode_enabled = false
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Speak to the table…"
	chat_input.max_length = 180
	chat_input.text_submitted.connect(func(message): session.send_chat(message); chat_input.clear())
	v.add_child(chat_input)
	secret_panel = panel(ui, Vector2(430, 175), Vector2(420, 480))
	v = column(secret_panel)
	label(v, "FOR YOUR EYES ONLY", 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_texture = TextureRect.new()
	role_texture.custom_minimum_size = Vector2(230, 330)
	role_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	role_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(role_texture)
	button(v, "PUT CARD AWAY  [TAB]", toggle_card)
	secret_panel.hide()
	rules_panel = panel(ui, Vector2(280, 120), Vector2(720, 545))
	v = column(rules_panel, 12)
	label(v, "THE HOUSE RULES", 28)
	wrap_label(v, "MAFIA · Agree on one victim each night. A tied Mafia ballot kills nobody. Win when Mafia equal or outnumber the remaining Town.\n\nDOCTOR · Protect one player each night, including yourself. Repeated protection is allowed.\n\nDETECTIVE · Learn privately whether one player is Mafia.\n\nVILLAGER · Listen, bluff, and vote. Town wins when all Mafia are gone.\n\nNIGHT → DISCUSSION → VOTE\nMore than half of living players must vote for the same person to eliminate them. Abstentions and ties can lead to no elimination. Death reveals the role. Dead players cannot speak to the living.\n\nPractice stand-ins make simple decisions, not human-like conversation. Expanded roles, voice, room codes, and reconnect recovery are planned.", 17, Color("d3ccb6"))
	button(v, "UNDERSTOOD", func(): rules_panel.hide())
	rules_panel.hide()
	settings_panel = panel(ui, Vector2(420, 200), Vector2(440, 340))
	v = column(settings_panel, 16)
	label(v, "ROOM SETTINGS", 27)
	var blood := CheckButton.new()
	blood.text = "Blood traces after elimination"
	blood.button_pressed = true
	blood.toggled.connect(func(on): room.blood_enabled = on; room.update_match(session.snapshot); save_preferences())
	v.add_child(blood)
	var film := CheckButton.new()
	film.text = "Film grain and vignette"
	film.button_pressed = true
	film.toggled.connect(func(on): grain.visible = on; save_preferences())
	v.add_child(film)
	label(v, "AMBIENT VOLUME", 13)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = master_volume
	volume.value_changed.connect(func(value): master_volume = value; if ambience: ambience.volume_db = linear_to_db(value); save_preferences())
	v.add_child(volume)
	button(v, "CLOSE", func(): settings_panel.hide())
	settings_panel.hide()
	status_label = label(ui, "", 16, Color("f0c288"))
	status_label.position = Vector2(40, 704)
	confirm_leave = ConfirmationDialog.new()
	confirm_leave.dialog_text = "Leave this table? Hosting players will disconnect."
	confirm_leave.confirmed.connect(func(): session.leave())
	ui.add_child(confirm_leave)
	var footer := label(ui, "HOLD RIGHT MOUSE TO LOOK  ·  TAB TO INSPECT  ·  ESC TO CLOSE", 11, MUTED)
	footer.position = Vector2(620, 704)

func refresh() -> void:
	var data: Dictionary = session.snapshot
	var phase: String = data.get("phase", "")
	menu.visible = session.mode == "menu" or session.mode == "connecting"
	lobby.visible = phase == "lobby" and session.mode != "menu"
	hud.visible = phase not in ["", "lobby"] and session.mode != "menu"
	if session.mode == "connecting": show_notice("Connecting to the host…")
	room.update_match(data)
	if not hud.visible:
		secret_panel.hide()
		room.inspect = false
		phase_key = ""
	if lobby.visible:
		var lines := PackedStringArray()
		for p in data.get("players", []): lines.append("%02d   %s%s" % [lines.size() + 1, p.name, "  · stand-in" if p.bot else ""])
		lobby_people.text = "\n".join(lines)
	if not hud.visible: return
	var day: int = data.get("day", 1)
	phase_label.text = "%s  %02d" % [phase.to_upper(), day]
	if phase == "ended": phase_label.text = "%s WINS" % data.winner
	clock_label.text = "%02d:%02d  ·  %d ALIVE" % [int(data.get("seconds", 0)) / 60, int(data.get("seconds", 0)) % 60, data.players.filter(func(p): return p.alive).size()]
	role_label.text = "YOUR CARD IS SEALED" if data.alive else "YOU ARE ELIMINATED"
	intel_label.text = data.get("intel", "")
	var log_lines: Array = data.get("history", [])
	history_label.text = "\n\n".join(log_lines.slice(maxi(0, log_lines.size() - 3)))
	var messages := PackedStringArray()
	for m in data.get("chat", []): messages.append("[%s] %s: %s" % [m.channel, m.name, m.text])
	var new_chat := "\n".join(messages)
	if chat_log.text != new_chat: chat_log.text = new_chat
	var can_chat: bool = not data.alive or phase != "night" or data.role == "Mafia"
	chat_input.editable = can_chat
	chat_input.placeholder_text = "The dead speak only to the dead…" if not data.alive else ("Mafia channel — teammates only…" if phase == "night" and can_chat else ("Silence. The room is asleep." if not can_chat else "Speak to the table…"))
	var new_phase := "%s%d" % [phase, day]
	if phase_key != new_phase:
		phase_key = new_phase
		secret_panel.hide()
		room.inspect = false
		play_cue(110.0 if phase == "night" else 240.0)
	var skip: Button = hud.find_child("PracticeSkip", true, false)
	if skip: skip.visible = session.mode == "practice" and phase != "ended"
	var new_targets := JSON.stringify([phase, data.players, data.get("selected", -1)])
	if target_key != new_targets:
		target_key = new_targets
		build_targets(data)

func build_targets(data: Dictionary) -> void:
	for child in targets.get_children():
		targets.remove_child(child)
		child.queue_free()
	var phase: String = data.phase
	var can_act: bool = data.alive and (phase == "vote" or (phase == "night" and data.role != "Villager"))
	instruction.text = "WATCH. LISTEN. REMEMBER."
	if phase == "night": instruction.text = "CHOOSE IN SECRET" if can_act else "THE ROOM IS ASLEEP"
	if phase == "vote": instruction.text = "CAST YOUR BALLOT"
	if phase == "ended": instruction.text = "THE CARDS ARE REVEALED"
	if not data.alive and phase != "ended": instruction.text = "YOUR SEAT IS SILENT"
	for p in data.players:
		var suffix := ""
		if p.has("role"): suffix = " · " + p.role
		if not p.alive: suffix = " †" + suffix
		var text: String = p.name + suffix
		if data.get("selected", -1) == p.id: text = "✓ " + text
		var b := button(targets, text, func(): session.submit(p.id))
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = not can_act or not p.alive or (p.id == data.self_id and (phase == "vote" or data.role != "Doctor")) or (phase == "night" and data.role == "Mafia" and p.get("role", "") == "Mafia")
	if can_act:
		button(targets, "✓ ABSTAIN" if data.get("selected", -1) == 0 else "ABSTAIN / NO ACTION", func(): session.submit(0))
	if phase == "ended":
		button(targets, "RETURN TO ENTRANCE", func(): session.leave())

func toggle_card() -> void:
	if session.snapshot.get("role", "") == "": return
	secret_panel.visible = not secret_panel.visible
	room.inspect = secret_panel.visible
	role_texture.texture = load("res://assets/cards/%s.png" % session.snapshot.role.to_lower())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_card()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			secret_panel.hide()
			rules_panel.hide()
			settings_panel.hide()
			room.inspect = false
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		room.look_offset.x = clampf(room.look_offset.x - event.relative.x * 0.012, -3.0, 3.0)
		room.look_offset.y = clampf(room.look_offset.y + event.relative.y * 0.009, -1.3, 1.0)

func show_notice(message: String) -> void:
	status_label.text = message
	toast_time = 8.0

func _process(delta: float) -> void:
	toast_time -= delta
	if toast_time <= 0: status_label.text = ""

func build_audio() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050 * 4 * 2)
	for i in range(22050 * 4):
		var t := float(i) / 22050.0
		var value := (sin(TAU * 55 * t) * 0.16 + sin(TAU * 82.5 * t) * 0.06 + sin(TAU * 110 * t) * 0.03) * (0.8 + 0.2 * sin(TAU * 0.25 * t))
		samples.encode_s16(i * 2, int(value * 32767))
	wav.data = samples
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050 * 4
	ambience = AudioStreamPlayer.new()
	ambience.stream = wav
	ambience.volume_db = linear_to_db(master_volume)
	add_child(ambience)
	ambience.play()

func play_cue(frequency: float) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(11025 * 2)
	for i in range(11025):
		var t := float(i) / 22050.0
		data.encode_s16(i * 2, int(sin(t * TAU * frequency) * exp(-t * 9.0) * 10000))
	wav.data = data
	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = linear_to_db(master_volume)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("user", "name", name_input.text)
	config.set_value("user", "address", address_input.text)
	config.set_value("audio", "volume", master_volume)
	config.set_value("visual", "blood", room.blood_enabled)
	config.set_value("visual", "grain", grain.visible)
	config.save("user://preferences.cfg")

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load("user://preferences.cfg") != OK: return
	name_input.text = config.get_value("user", "name", "Guest")
	address_input.text = config.get_value("user", "address", "127.0.0.1")
	master_volume = config.get_value("audio", "volume", 0.22)
	ambience.volume_db = linear_to_db(master_volume)
	room.blood_enabled = config.get_value("visual", "blood", true)
	grain.visible = config.get_value("visual", "grain", true)
	for n in settings_panel.get_child(0).get_children():
		if n is HSlider: n.set_value_no_signal(master_volume)
		if n is CheckButton: n.set_pressed_no_signal(room.blood_enabled if n.text.begins_with("Blood") else grain.visible)
