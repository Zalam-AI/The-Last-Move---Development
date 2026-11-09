extends Node
## SaveManager (autoload: Save)
## Versioned, crash-tolerant player profile persistence.
## Writes are atomic (tmp -> rename) and keep one rolling backup, so a failed write
## can never destroy progression. Unknown/older versions are migrated or defaulted safely.

signal profile_changed
signal achievement_unlocked(id: String)

const VERSION := 3
const PROFILE_PATH := "user://profile.json"
const BACKUP_PATH := "user://profile.json.bak"
const TMP_PATH := "user://profile.json.tmp"

var profile: Dictionary = {}


func _ready() -> void:
	load_profile()


func default_profile() -> Dictionary:
	return {
		"version": VERSION,
		"credits": 0,
		"xp": 0,
		"contracts_completed": 0,
		"best_scores": {},           # property_id -> best payout
		"completed_properties": [],  # ordered list of property ids finished
		"unlocked_properties": ["willow"],
		"unlocked_upgrades": ["gloves_basic", "paint_rust"],
		"owned_cosmetics": ["uni_standard", "hat_none"],
		"equipped": {"uniform": "uni_standard", "hat": "hat_none", "gloves": "", "boots": ""},
		"achievements": [],
		"stats": {
			"items_delivered": 0,
			"items_destroyed": 0,
			"total_damage": 0,
			"distance_carried": 0.0,
			"deaths": 0,
			"revives": 0,
			"fastest_contract": 0.0,
			"crew_carries": 0,
		},
		"seen_story": 0,
		"hints_seen": [],
		"name": "",
	}


func load_profile() -> void:
	profile = default_profile()
	var loaded := false
	if FileAccess.file_exists(PROFILE_PATH):
		var data = _read_json(PROFILE_PATH)
		if data is Dictionary and data.has("version"):
			profile = _migrate(data)
			loaded = true
		else:
			push_warning("[Save] primary profile unreadable, trying backup")
	if not loaded and FileAccess.file_exists(BACKUP_PATH):
		var backup = _read_json(BACKUP_PATH)
		if backup is Dictionary and backup.has("version"):
			profile = _migrate(backup)
			push_warning("[Save] recovered profile from backup")
			loaded = true
	if not loaded:
		profile = default_profile()
		save_profile()
	profile_changed.emit()


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data


func _migrate(data: Dictionary) -> Dictionary:
	var out := default_profile()
	# JSON round-trips every number as a float, so coercion has to be explicit or a
	# reloaded profile silently loses its credits. Merge known keys only.
	for key in out.keys():
		if not data.has(key):
			continue
		var v = data[key]
		var cur = out[key]
		if (v is int or v is float) and (cur is int or cur is float):
			out[key] = int(v) if typeof(cur) == TYPE_INT else float(v)
		elif typeof(cur) == typeof(v):
			out[key] = v
		elif cur is Dictionary and v is Dictionary:
			for k2 in v.keys():
				cur[k2] = v[k2]
		elif cur is Array and v is Array:
			out[key] = v
	out["version"] = VERSION
	if int(out["credits"]) < 0:
		out["credits"] = 0
	for arr_key in ["unlocked_properties", "unlocked_upgrades", "owned_cosmetics", "achievements", "completed_properties", "hints_seen"]:
		if not (out[arr_key] is Array):
			out[arr_key] = []
	return out


func save_profile() -> bool:
	profile["version"] = VERSION
	var tmp := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if tmp == null:
		push_error("[Save] cannot open tmp file for writing")
		return false
	tmp.store_string(JSON.stringify(profile, "\t"))
	tmp.flush()
	tmp.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	# Rotate current -> backup before replacing.
	if FileAccess.file_exists(PROFILE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			dir.remove(BACKUP_PATH)
		dir.copy(PROFILE_PATH, BACKUP_PATH)
	if dir.file_exists(TMP_PATH):
		dir.remove(PROFILE_PATH)
		var err := dir.rename(TMP_PATH, PROFILE_PATH)
		if err != OK:
			push_error("[Save] rename failed: %s" % err)
			return false
	return true


func reset_profile() -> void:
	profile = default_profile()
	save_profile()
	profile_changed.emit()


# ---------------------------------------------------------------- economy ----

func credits() -> int:
	return int(profile.get("credits", 0))


func add_credits(amount: int) -> void:
	profile["credits"] = maxi(0, credits() + amount)
	save_profile()
	profile_changed.emit()


func can_afford(amount: int) -> bool:
	return credits() >= amount


func spend_credits(amount: int) -> bool:
	if not can_afford(amount):
		return false
	profile["credits"] = credits() - amount
	save_profile()
	profile_changed.emit()
	return true


func owns_upgrade(id: String) -> bool:
	return id in profile.get("unlocked_upgrades", [])


func purchase_upgrade(id: String) -> bool:
	var up := DB.get_upgrade(id)
	if up.is_empty() or owns_upgrade(id):
		return false
	var cost := int(up.get("cost", 0))
	if cost > 0 and not spend_credits(cost):
		return false
	profile["unlocked_upgrades"].append(id)
	save_profile()
	profile_changed.emit()
	return true


func owns_cosmetic(id: String) -> bool:
	return id in profile.get("owned_cosmetics", [])


func purchase_cosmetic(id: String) -> bool:
	var c := DB.get_cosmetic(id)
	if c.is_empty() or owns_cosmetic(id):
		return false
	if not spend_credits(int(c.get("cost", 0))):
		return false
	profile["owned_cosmetics"].append(id)
	equip_cosmetic(id)
	save_profile()
	profile_changed.emit()
	return true


func equip_cosmetic(id: String) -> void:
	var c := DB.get_cosmetic(id)
	if c.is_empty() or not owns_cosmetic(id):
		return
	profile["equipped"][c["slot"]] = id
	save_profile()
	profile_changed.emit()


func equipped() -> Dictionary:
	return profile.get("equipped", {})


func cosmetic_color(slot: String, fallback: Color) -> Color:
	var id: String = profile.get("equipped", {}).get(slot, "")
	if id == "":
		return fallback
	var c := DB.get_cosmetic(id)
	if c.is_empty():
		return fallback
	return Color(str(c.get("color", "#888888")))


# ------------------------------------------------------------- progression ---

func is_property_unlocked(property_id: String) -> bool:
	return property_id in profile.get("unlocked_properties", [])


func has_completed(property_id: String) -> bool:
	return property_id in profile.get("completed_properties", [])


func complete_property(property_id: String, payout: int, unlocked_next: String = "") -> void:
	profile["contracts_completed"] = int(profile.get("contracts_completed", 0)) + 1
	profile["xp"] = int(profile.get("xp", 0)) + maxi(1, payout / 10)
	if not has_completed(property_id):
		profile["completed_properties"].append(property_id)
	if unlocked_next != "" and not is_property_unlocked(unlocked_next):
		profile["unlocked_properties"].append(unlocked_next)
	var best: Dictionary = profile.get("best_scores", {})
	if payout > int(best.get(property_id, 0)):
		best[property_id] = payout
	profile["best_scores"] = best
	save_profile()
	profile_changed.emit()


func bump_stat(key: String, amount: float) -> void:
	var stats: Dictionary = profile.get("stats", {})
	stats[key] = float(stats.get(key, 0)) + amount
	profile["stats"] = stats


func set_achievement(id: String) -> bool:
	var list: Array = profile.get("achievements", [])
	if id in list:
		return false
	list.append(id)
	profile["achievements"] = list
	save_profile()
	achievement_unlocked.emit(id)
	return true


func has_achievement(id: String) -> bool:
	return id in profile.get("achievements", [])


func has_seen_hint(id: String) -> bool:
	return (profile.get("hints_seen", []) as Array).has(id)


func mark_hint_seen(id: String) -> void:
	var seen: Array = profile.get("hints_seen", [])
	if seen.has(id):
		return
	seen.append(id)
	profile["hints_seen"] = seen
	save_profile()


func clear_hints() -> void:
	profile["hints_seen"] = []
	save_profile()


func mark_story_seen(index: int) -> void:
	profile["seen_story"] = maxi(int(profile.get("seen_story", 0)), index + 1)
	save_profile()
