extends RefCounted
## Server-only match model. Never send this object to a client.

var players: Array = []
var phase := "lobby"
var day := 0
var actions: Dictionary = {}
var votes: Dictionary = {}
var intel: Dictionary = {}
var history: Array = []
var winner := ""
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func add_player(id: int, player_name: String, bot := false) -> void:
	players.append({"id": id, "name": player_name.left(20), "bot": bot, "alive": true, "role": "Villager"})

func player(id: int) -> Dictionary:
	for p in players:
		if p.id == id:
			return p
	return {}

func alive() -> Array:
	return players.filter(func(p): return p.alive)

func start() -> bool:
	if players.size() < 5 or players.size() > 12:
		return false
	var roles: Array = []
	for i in range(players.size()):
		roles.append("Villager")
	var mafia_count := 2 if players.size() >= 8 else 1
	for i in range(mafia_count):
		roles[i] = "Mafia"
	roles[mafia_count] = "Doctor"
	roles[mafia_count + 1] = "Detective"
	for i in range(roles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var old = roles[i]
		roles[i] = roles[j]
		roles[j] = old
	for i in range(players.size()):
		players[i].role = roles[i]
		players[i].alive = true
	intel.clear()
	history.clear()
	winner = ""
	day = 1
	phase = "night"
	actions.clear()
	votes.clear()
	announce("The doors are locked. Night 1 begins.")
	return true

func announce(message: String) -> void:
	history.append(message)
	if history.size() > 40:
		history.pop_front()

func submit(id: int, target: int) -> bool:
	var p := player(id)
	if p.is_empty() or not p.alive:
		return false
	var t := player(target)
	if phase == "vote":
		if target != 0 and (t.is_empty() or not t.alive or target == id):
			return false
		votes[id] = target
		return true
	if phase != "night" or p.role == "Villager":
		return false
	if target == 0:
		actions[id] = 0
		return true
	if t.is_empty() or not t.alive:
		return false
	if p.role != "Doctor" and target == id:
		return false
	if p.role == "Mafia" and t.role == "Mafia":
		return false
	actions[id] = target
	return true

func resolve_night() -> void:
	if phase != "night":
		return
	var attacks: Dictionary = {}
	var protection: Array = []
	for p in alive():
		var target := int(actions.get(p.id, 0))
		if target == 0:
			continue
		match p.role:
			"Mafia": attacks[target] = int(attacks.get(target, 0)) + 1
			"Doctor": protection.append(target)
			"Detective":
				var found := player(target)
				intel[p.id] = "Night %d · %s: %s" % [day, found.name, "MAFIA" if found.role == "Mafia" else "NOT MAFIA"]
	var victim := 0
	var highest := 0
	var tied := false
	for id in attacks:
		if attacks[id] > highest:
			highest = attacks[id]
			victim = id
			tied = false
		elif attacks[id] == highest:
			tied = true
	if tied:
		victim = 0
	if victim != 0 and not protection.has(victim):
		player(victim).alive = false
		announce("Dawn %d · %s was killed. Their card: %s." % [day, player(victim).name, player(victim).role])
	else:
		announce("Dawn %d · Everyone survived the night." % day)
	phase = "discussion"
	check_win()

func begin_vote() -> void:
	if phase == "discussion":
		phase = "vote"
		votes.clear()
		announce("The ballot is open. A living majority must agree.")

func resolve_vote() -> void:
	if phase != "vote":
		return
	var counts: Dictionary = {}
	for id in votes:
		if player(id).alive and votes[id] != 0:
			counts[votes[id]] = int(counts.get(votes[id], 0)) + 1
	var victim := 0
	for id in counts:
		if counts[id] > alive().size() / 2.0:
			victim = id
	if victim != 0:
		player(victim).alive = false
		announce("%s was condemned (%d votes). Their card: %s." % [player(victim).name, counts[victim], player(victim).role])
	else:
		announce("No majority. The table spares everyone.")
	if check_win():
		return
	day += 1
	phase = "night"
	actions.clear()
	votes.clear()

func check_win() -> bool:
	var mafia := 0
	var town := 0
	for p in alive():
		if p.role == "Mafia": mafia += 1
		else: town += 1
	if mafia == 0: winner = "TOWN"
	elif mafia >= town: winner = "MAFIA"
	if winner != "":
		phase = "ended"
		announce("%s wins. Every secret is now on the table." % winner)
		return true
	return false

func view_for(id: int) -> Dictionary:
	var mine := player(id)
	var public_players: Array = []
	for p in players:
		var entry := {"id": p.id, "name": p.name, "alive": p.alive, "bot": p.bot}
		if phase != "lobby" and (p.id == id or not p.alive or phase == "ended" or (mine.get("role") == "Mafia" and p.role == "Mafia")):
			entry.role = p.role
		public_players.append(entry)
	return {"players": public_players, "phase": phase, "day": day, "winner": winner,
		"role": mine.get("role", "") if phase != "lobby" else "", "alive": mine.get("alive", false),
		"intel": intel.get(id, ""), "history": history.duplicate(),
		"selected": actions.get(id, -1) if phase == "night" else votes.get(id, -1)}
