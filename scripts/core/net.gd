extends Node
## Network (autoload: Net)
## Transport + session layer for THE LAST MOVE.
##
## Design notes
## ------------
## * Solo play uses OfflineMultiplayerPeer so every RPC path is identical in solo and
##   online play -- a single code path is tested by solo QA runs.
## * Host-authoritative: the host owns mission state, furniture physics and scoring.
##   Clients own only their own player transform, which they broadcast; the host relays.
## * The transport is isolated behind create_host()/join() so a Steam transport
##   (SteamMultiplayerPeer from GodotSteam) can replace ENet without touching gameplay.
##   See documentation/STEAM_INTEGRATION.md.

signal session_started(is_host: bool)
signal session_ended(reason: String)
signal players_changed
signal peer_joined(id: int)
signal peer_left(id: int)
signal host_left
signal chat_message(from_id: int, text: String)
signal net_error(message: String)

enum Mode { NONE, SOLO, HOST, CLIENT }

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 4
const PROTOCOL := 1
const PING_INTERVAL := 1.0

var mode: Mode = Mode.NONE
var players: Dictionary = {}          # id -> {name, ready, equipped, ping, loaded, alive}
var session_name := "LAST MOVE CREW"
var session_password := ""
var transport: String = "enet"        # "enet" (default) or "steam"
var last_join := {"ip": "", "port": 0}
var voice: Node = null
var _ping_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	voice = preload("res://scripts/core/voice_chat.gd").new()
	voice.name = "VoiceChat"
	add_child(voice)


# ------------------------------------------------------------- lifecycle ----

func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func is_host() -> bool:
	return mode == Mode.SOLO or mode == Mode.HOST


func is_solo() -> bool:
	return mode == Mode.SOLO


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func player_count() -> int:
	return maxi(1, players.size())


func start_solo() -> void:
	leave_session(false)
	mode = Mode.SOLO
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = _local_info()
	players_changed.emit()
	session_started.emit(true)


func create_host(port: int = DEFAULT_PORT, password := "", name := "LAST MOVE CREW") -> bool:
	leave_session(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		net_error.emit("Could not open port %d (error %d). Another session may already be running." % [port, err])
		mode = Mode.NONE
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	session_name = name
	session_password = password
	players.clear()
	players[1] = _local_info()
	players_changed.emit()
	session_started.emit(true)
	print("[Net] hosting on port %d" % port)
	return true


func join(ip: String, port: int = DEFAULT_PORT, password := "") -> bool:
	leave_session(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		net_error.emit("Could not reach %s:%d (error %d)." % [ip, port, err])
		mode = Mode.NONE
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	session_password = password
	last_join = {"ip": ip, "port": port}
	print("[Net] connecting to %s:%d" % [ip, port])
	return true


func disconnect_with_reason(reason: String) -> void:
	if multiplayer.multiplayer_peer != null and is_online():
		# Best effort notification to the other side.
		if is_host():
			rpc("_client_session_closed", reason)
	leave_session(true, reason)


func leave_session(emit_signal := true, reason := "Session closed") -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	var offline := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = offline
	mode = Mode.NONE
	players.clear()
	if emit_signal:
		session_ended.emit(reason)


func _local_info() -> Dictionary:
	return {
		"name": Settings.get_value("player_name", "Mover"),
		"ready": false,
		"equipped": Save.equipped(),
		"ping": 0,
		"loaded": false,
		"alive": true,
		"voice": Settings.get_value("voice_enabled", true),
	}


# --------------------------------------------------------- peer callbacks ---

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	print("[Net] peer connected: %d" % id)
	# The client registers itself; nothing is published until it does.
	rpc_id(id, "_server_welcome", PROTOCOL, session_name)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		players_changed.emit()
		peer_left.emit(id)
		if is_host():
			rpc("_sync_players", players)


func _on_connected_to_server() -> void:
	print("[Net] connected as id %d, registering" % multiplayer.get_unique_id())
	var pw_hash := "" if session_password == "" else session_password.sha256_text()
	rpc_id(1, "_client_register", _local_info(), PROTOCOL, pw_hash, Settings.get_value("player_name", "Mover"))


func _on_connection_failed() -> void:
	net_error.emit("Connection failed. Check the address, the port and your firewall.")
	leave_session(false)
	session_ended.emit("Connection failed")


func _on_server_disconnected() -> void:
	if mode == Mode.CLIENT:
		mode = Mode.NONE
		players.clear()
		host_left.emit()
		session_ended.emit("The host left the session.")


# ----------------------------------------------------------------- RPCs -----

@rpc("any_peer", "call_remote", "reliable")
func _server_welcome(protocol: int, sname: String) -> void:
	if protocol != PROTOCOL:
		net_error.emit("Host is running a different game version.")
		leave_session(false)


@rpc("any_peer", "call_remote", "reliable")
func _client_register(info: Dictionary, protocol: int, pw_hash: String, pname: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		rpc_id(sender, "_kicked", "Version mismatch. Both players must run the same build.")
		return
	if session_password != "" and pw_hash != session_password.sha256_text():
		rpc_id(sender, "_kicked", "Wrong session password.")
		return
	if players.size() >= MAX_PLAYERS:
		rpc_id(sender, "_kicked", "The crew is already full.")
		return
	info["name"] = str(pname) if pname.strip_edges() != "" else "Mover %d" % sender
	info["ready"] = false
	players[sender] = info
	players_changed.emit()
	peer_joined.emit(sender)
	print("[Net] broadcasting %d players to %d peers" % [players.size(), multiplayer.get_peers().size()])
	rpc("_sync_players", players)
	print("[Net] %s joined (%d total)" % [info["name"], players.size()])


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	net_error.emit(reason)
	leave_session(false)
	session_ended.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _sync_players(list: Dictionary) -> void:
	# Key types survive RPC as ints; normalise defensively.
	print("[Net] received roster: %d players" % list.size())
	players.clear()
	for k in list.keys():
		players[int(k)] = list[k]
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _client_session_closed(reason: String) -> void:
	host_left.emit()


@rpc("any_peer", "call_remote", "reliable")
func _client_set_ready(ready: bool) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ready"] = ready
		players_changed.emit()
		rpc("_sync_players", players)


@rpc("any_peer", "call_remote", "reliable")
func _client_set_info(patch: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		for k in patch.keys():
			players[sender][k] = patch[k]
		players_changed.emit()
		rpc("_sync_players", players)


# ---------------------------------------------------------- public helpers --

func set_ready(ready: bool) -> void:
	if is_host():
		if players.has(1):
			players[1]["ready"] = ready
			players_changed.emit()
			if is_online():
				rpc("_sync_players", players)
	else:
		rpc_id(1, "_client_set_ready", ready)


func set_player_info(patch: Dictionary) -> void:
	if is_host():
		if players.has(1):
			for k in patch.keys():
				players[1][k] = patch[k]
			players_changed.emit()
			if is_online():
				rpc("_sync_players", players)
	else:
		rpc_id(1, "_client_set_info", patch)


func send_chat(text: String) -> void:
	if text.strip_edges() == "":
		return
	if is_host():
		_deliver_chat(my_id(), text)
		if is_online():
			rpc("_deliver_chat", my_id(), text)
	elif is_online():
		rpc_id(1, "_client_chat", text)


@rpc("any_peer", "call_remote", "reliable")
func _client_chat(text: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	rpc("_deliver_chat", sender, text)
	_deliver_chat(sender, text)


@rpc("authority", "call_remote", "reliable")
func _deliver_chat(from_id: int, text: String) -> void:
	chat_message.emit(from_id, text)


func display_name(id: int) -> String:
	if players.has(id):
		return str(players[id].get("name", "Mover"))
	return "Mover %d" % id


func all_ready() -> bool:
	if players.size() == 0:
		return false
	var ready_count := 0
	for id in players.keys():
		if bool(players[id].get("ready", false)) and id != 0:
			ready_count += 1
	return ready_count == players.size()


func ping_of(id: int) -> int:
	if players.has(id):
		return int(players[id].get("ping", 0))
	return 0


func _process(delta: float) -> void:
	if not is_online():
		return
	_ping_timer += delta
	if _ping_timer < PING_INTERVAL:
		return
	_ping_timer = 0.0
	var now := Time.get_ticks_msec()
	if is_host():
		for id in multiplayer.get_peers():
			rpc_id(id, "_ping", now)
	else:
		rpc_id(1, "_ping", now)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(t: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		rpc_id(sender, "_pong", t)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(t: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ping"] = Time.get_ticks_msec() - t
		players_changed.emit()
