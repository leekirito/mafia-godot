extends Node
## Authority owns the full model; RPC snapshots are filtered per recipient.
signal changed
signal notice(message: String)
const Rules = preload("res://scripts/match_rules.gd")
const PORT := 27840
var model = Rules.new()
var snapshot: Dictionary = {}
var mode := "menu"
var local_name := "Guest"
var seconds := 0.0
var bot_clock := 0.0
var chat: Array = []
var chat_times: Dictionary = {}
var pending_peers: Dictionary = {}
var is_host := false
var fast := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_connected)
	multiplayer.peer_disconnected.connect(_disconnected)
	multiplayer.connected_to_server.connect(_joined)
	multiplayer.connection_failed.connect(func(): leave(); notice.emit("Connection failed. Check the address and UDP port 27840."))
	multiplayer.server_disconnected.connect(func(): leave(); notice.emit("The host closed the table."))

func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "menu"
	is_host = false
	model = Rules.new()
	snapshot.clear()
	chat.clear()
	chat_times.clear()
	pending_peers.clear()
	changed.emit()

func host_game(player_name: String, practice := false) -> void:
	leave()
	local_name = clean_name(player_name)
	if not practice:
		var peer := ENetMultiplayerPeer.new()
		var result := peer.create_server(PORT, 11)
		if result != OK:
			notice.emit("Could not host on UDP %d (error %d)." % [PORT, result])
			return
		multiplayer.multiplayer_peer = peer
	is_host = true
	mode = "practice" if practice else "host"
	model.add_player(1, local_name)
	if practice:
		for i in range(9): add_bot(false)
		start_game()
	else:
		broadcast()

func join_game(player_name: String, address: String) -> void:
	leave()
	local_name = clean_name(player_name)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address.strip_edges(), PORT)
	if result != OK:
		notice.emit("Invalid connection address (error %d)." % result)
		return
	multiplayer.multiplayer_peer = peer
	mode = "connecting"
	changed.emit()

func clean_name(value: String) -> String:
	var cleaned := value.strip_edges().replace("\n", " ").replace("\r", " ").left(20)
	return cleaned if cleaned != "" else "Guest"

func _connected(id: int) -> void:
	if is_host:
		if model.phase != "lobby" or model.players.size() >= 12:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		else:
			pending_peers[id] = Time.get_ticks_msec()

func _joined() -> void:
	mode = "client"
	register.rpc_id(1, local_name)

@rpc("any_peer", "call_remote", "reliable")
func register(player_name: String) -> void:
	if not is_host or model.phase != "lobby": return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not model.player(id).is_empty() or model.players.size() >= 12: return
	pending_peers.erase(id)
	model.add_player(id, clean_name(player_name))
	broadcast()

func _disconnected(id: int) -> void:
	if not is_host: return
	pending_peers.erase(id)
	var p: Dictionary = model.player(id)
	if p.is_empty(): return
	if model.phase == "lobby":
		model.players.erase(p)
	else:
		# Explicit prototype policy: a bot inherits the seat and secret role.
		p.bot = true
		model.announce("%s disconnected. A stand-in takes their seat." % p.name)
	broadcast()

func add_bot(update := true) -> void:
	if not is_host or model.phase != "lobby" or model.players.size() >= 12: return
	var names := ["Morrow", "Vesper", "Hollow", "Ash", "Mercer", "Rook", "Vale", "Silas", "Moth", "Ives", "Crow"]
	var id := -1
	while not model.player(id).is_empty(): id -= 1
	model.add_player(id, names[(-id - 1) % names.size()], true)
	if update: broadcast()

func start_game() -> void:
	if not is_host or model.phase != "lobby": return
	if not model.start():
		notice.emit("Seat 5–12 players before dealing. Add stand-ins for empty seats.")
		return
	chat.clear()
	set_clock()
	broadcast()

func set_clock() -> void:
	match model.phase:
		"night": seconds = 35.0
		"discussion": seconds = 90.0
		"vote": seconds = 30.0
		_: seconds = 0.0
	bot_clock = 2.0

func advance() -> void:
	# Only practice exposes a manual phase skip.
	if not is_host: return
	match model.phase:
		"night": bot_actions(); model.resolve_night()
		"discussion": model.begin_vote()
		"vote": bot_actions(); model.resolve_vote()
	set_clock()
	broadcast()

func submit(target: int) -> void:
	if is_host:
		if model.submit(1, target): broadcast()
	else:
		request_action.rpc_id(1, target)

@rpc("any_peer", "call_remote", "reliable")
func request_action(target: int) -> void:
	if not is_host: return
	if model.submit(multiplayer.get_remote_sender_id(), target): broadcast()

func bot_actions() -> void:
	for p in model.alive():
		if not p.bot: continue
		if model.phase == "night" and not model.actions.has(p.id):
			var choices: Array = model.alive().filter(func(t): return (t.id != p.id or p.role == "Doctor") and (p.role != "Mafia" or t.role != "Mafia"))
			if not choices.is_empty():
				# All Mafia coordinate on the same target. Town bots never inspect hidden roles.
				var target: int = choices[model.rng.randi_range(0, choices.size() - 1)].id
				if p.role == "Mafia":
					for ally in model.alive():
						if ally.role == "Mafia" and model.actions.get(ally.id, 0) != 0:
							target = model.actions[ally.id]
							break
				model.submit(p.id, target)
		elif model.phase == "vote" and not model.votes.has(p.id):
			var choices: Array = model.alive().filter(func(t): return t.id != p.id)
			if not choices.is_empty():
				var target: int = choices[(model.day - 1) % choices.size()].id
				# A shared public suspicion makes practice rounds progress; no role lookup.
				var leader: int = model.alive()[(model.day * 3) % model.alive().size()].id
				if leader != p.id: target = leader
				model.submit(p.id, target)

func _process(delta: float) -> void:
	if not is_host: return
	for id in pending_peers.keys():
		if Time.get_ticks_msec() - pending_peers[id] > 10000:
			multiplayer.multiplayer_peer.disconnect_peer(id)
			pending_peers.erase(id)
	if model.phase in ["lobby", "ended"]: return
	var before := ceili(seconds)
	seconds = maxf(0.0, seconds - delta)
	bot_clock -= delta
	if bot_clock <= 0.0:
		bot_actions()
		bot_clock = 5.0
	if seconds <= 0.0:
		advance()
	elif ceili(seconds) != before:
		broadcast()

func broadcast() -> void:
	if not is_host: return
	for p in model.players:
		if p.bot: continue
		var data: Dictionary = model.view_for(p.id)
		data.seconds = ceili(seconds)
		data.self_id = p.id
		data.chat = visible_chat(p)
		if p.id == 1:
			snapshot = data
			changed.emit()
		elif multiplayer.get_peers().has(p.id):
			receive_snapshot.rpc_id(p.id, data)

@rpc("authority", "call_remote", "reliable")
func receive_snapshot(data: Dictionary) -> void:
	snapshot = data
	changed.emit()

func send_chat(message: String) -> void:
	if is_host: accept_chat(1, message)
	else: request_chat.rpc_id(1, message)

@rpc("any_peer", "call_remote", "reliable")
func request_chat(message: String) -> void:
	if is_host: accept_chat(multiplayer.get_remote_sender_id(), message)

func accept_chat(id: int, message: String) -> void:
	var p: Dictionary = model.player(id)
	if p.is_empty(): return
	var now := Time.get_ticks_msec()
	if now - int(chat_times.get(id, -1000)) < 700: return
	chat_times[id] = now
	var clean := message.strip_edges().replace("\n", " ").left(180)
	if clean == "": return
	var channel := "table"
	if not p.alive: channel = "dead"
	elif model.phase == "night":
		if p.role != "Mafia": return
		channel = "mafia"
	chat.append({"name": p.name, "text": clean, "channel": channel})
	if chat.size() > 60: chat.pop_front()
	broadcast()

func visible_chat(p: Dictionary) -> Array:
	return chat.filter(func(m): return m.channel == "table" or (m.channel == "dead" and not p.alive) or (m.channel == "mafia" and p.role == "Mafia"))
