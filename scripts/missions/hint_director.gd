class_name HintDirector
extends Node
## First-run guidance.
##
## THE LAST MOVE teaches by doing: nothing is gated behind a tutorial level, so instead the
## mission watches what the crew is doing and says one thing, once, at the moment it is
## useful. Every hint is remembered in the save profile, so a crew hears each line exactly
## once in the life of the profile and a returning four-stack is never lectured. Hints can
## also be switched off entirely in Settings.
##
## Written in the company's voice: dispatch is helpful, faintly threatening, and never
## explains the supernatural.

const COOLDOWN := 11.0
const DOORS_DELAY := 18.0
const CLOCK_WARNING := 90.0
const HEAVY_MASS := 60.0
const DAMAGE_HINT_AT := 40.0

const HINTS := {
	"doors": "Cargo only counts while the bay doors are open. Hold [E] on the back of the truck.",
	"grab": "Hold [E] to keep your grip. Keep walking: the company does not pay for hesitation.",
	"heavy": "That is a two-mover object. Alone it drags and skids; with a second hand it lifts.",
	"delivered": "Loaded. [TAB] shows what is left, then bring the whole crew back to the truck.",
	"damage": "Damage is deducted from the payout. The client is sentimentally attached to it.",
	"creature": "That is not a mover. Light unsettles it, noise draws it, and furniture hurts it.",
	"downed": "A downed mover is not dead, just unavailable. Hold [E] on them to revive.",
	"clock": "The truck leaves on schedule whether or not the house is empty. It pays short.",
	"missing": "An employee who does not return is filed as missing.",
}

var mission: MissionManager = null
var _cooldown := 0.0
var _elapsed := 0.0
var _started := false


func setup(m: MissionManager) -> void:
	mission = m
	set_process(true)


func _enabled() -> bool:
	return bool(Settings.get_value("hints", true))


func _process(delta: float) -> void:
	if mission == null or not is_instance_valid(mission):
		return
	if not _started:
		_started = true
		_cooldown = 6.0
	_elapsed += delta
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	var id := next_hint()
	if id == "":
		return
	fire(id)


## The highest-priority hint that is both relevant right now and not yet shown. Public so a
## test (or the pause menu's "controls" page) can ask the same question without a mission.
func next_hint() -> String:
	if mission == null or not _enabled():
		return ""
	for id in HINTS.keys():
		if Save.has_seen_hint(str(id)):
			continue
		if _applies(str(id)):
			return str(id)
	return ""


func fire(id: String) -> void:
	if not HINTS.has(id) or Save.has_seen_hint(id):
		return
	Save.mark_hint_seen(id)
	_cooldown = COOLDOWN
	if mission != null:
		mission.notification.emit(str(HINTS[id]), "hint")
	Audio.play_sfx("paper", Vector3.ZERO, -10.0)


func _applies(id: String) -> bool:
	var truck := mission.truck
	match id:
		"doors":
			return (_elapsed > DOORS_DELAY and truck != null and not truck.doors_open
				and mission.required_delivered == 0 and _carried_count() > 0)
		"grab":
			return _carried_count() > 0
		"heavy":
			var f := _heaviest_carried()
			return f != null and f.mass >= HEAVY_MASS and f.holders.size() < 2
		"delivered":
			return mission.required_delivered >= 1
		"damage":
			return mission.property_damage >= DAMAGE_HINT_AT
		"creature":
			return mission.creatures != null and mission.creatures.alive_count() > 0
		"downed":
			return _downed_count() > 0
		"clock":
			return mission.time_left <= CLOCK_WARNING
		"missing":
			return mission.crew_lost > 0
	return false


func _carried_count() -> int:
	var n := 0
	for p in _players():
		if p.carried != null:
			n += 1
	return n


func _heaviest_carried() -> Furniture:
	var best: Furniture = null
	for p in _players():
		var f: Furniture = p.carried
		if f == null or not is_instance_valid(f):
			continue
		if best == null or f.mass > best.mass:
			best = f
	return best


func _downed_count() -> int:
	var n := 0
	for p in _players():
		if p.is_downed:
			n += 1
	return n


func _players() -> Array[Player]:
	var out: Array[Player] = []
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		if p != null and is_instance_valid(p):
			out.append(p)
	return out
