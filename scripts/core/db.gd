extends Node
## Database (autoload: DB)
## Loads the JSON design data once at boot and exposes typed accessors.
## Everything gameplay-facing (items, upgrades, properties, flavour text) lives here
## so content can be tuned without touching systems code.

var items: Dictionary = {}
var item_ids: Array[String] = []
var upgrades: Array = []
var cosmetics: Array = []
var modifiers: Dictionary = {}
var properties: Array = []
var achievements: Dictionary = {}
var flavor: Dictionary = {}
var loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	var items_data = U.json_read("res://resources/items.json")
	if items_data is Dictionary and items_data.has("items"):
		items.clear()
		item_ids.clear()
		for it in items_data["items"]:
			items[it["id"]] = _normalize_item(it)
			item_ids.append(it["id"])

	var up_data = U.json_read("res://resources/upgrades.json")
	if up_data is Dictionary:
		upgrades = up_data.get("upgrades", [])
		cosmetics = up_data.get("cosmetics", [])

	var mod_data = U.json_read("res://resources/modifiers.json")
	if mod_data is Dictionary:
		modifiers.clear()
		for m in mod_data.get("modifiers", []):
			modifiers[m["id"]] = m

	var prop_data = U.json_read("res://resources/properties.json")
	if prop_data is Dictionary:
		properties = prop_data.get("properties", [])
		properties.sort_custom(func(a, b): return int(a["index"]) < int(b["index"]))

	var fl = U.json_read("res://resources/flavor.json")
	flavor = fl if fl is Dictionary else {}
	achievements.clear()
	for a in flavor.get("achievements", []):
		achievements[a["id"]] = a

	loaded = true
	print("[DB] loaded %d items, %d properties, %d upgrades, %d modifiers" % [
		items.size(), properties.size(), upgrades.size(), modifiers.size()])


func _normalize_item(it: Dictionary) -> Dictionary:
	var d: Dictionary = it.duplicate(true)
	var size_arr: Array = d.get("size", [1, 1, 1])
	d["size_v"] = Vector3(float(size_arr[0]), float(size_arr[1]), float(size_arr[2]))
	d["height"] = float(size_arr[1])
	d["radius"] = maxf(float(d["size_v"].x), float(d["size_v"].z)) * 0.5
	d["color_c"] = Color(str(d.get("color", "#888888")))
	d["accent_c"] = Color(str(d.get("accent", "#555555")))
	_set_default(d, "fragility", 0.3)
	_set_default(d, "material", "wood")
	_set_default(d, "grips", 2)
	_set_default(d, "min_carriers", 1)
	_set_default(d, "category", "medium")
	_set_default(d, "value", 100)
	_set_default(d, "weight", 20.0)
	_set_default(d, "static", false)
	_set_default(d, "template", "crate")
	return d


func _set_default(d: Dictionary, key: String, value: Variant) -> void:
	if not d.has(key):
		d[key] = value


func get_item(id: String) -> Dictionary:
	if not items.has(id):
		push_warning("Unknown item id: %s" % id)
		return items.get("crate", {})
	return items[id]


func item_value(id: String) -> int:
	return int(get_item(id).get("value", 0))


func has_item(id: String) -> bool:
	return items.has(id)


func get_property(id: String) -> Dictionary:
	for p in properties:
		if p["id"] == id:
			return p
	return {}


func property_count() -> int:
	return properties.size()


func get_upgrade(id: String) -> Dictionary:
	for u in upgrades:
		if u["id"] == id:
			return u
	return {}


func get_cosmetic(id: String) -> Dictionary:
	for c in cosmetics:
		if c["id"] == id:
			return c
	return {}


func cosmetics_for_slot(slot: String) -> Array:
	var out := []
	for c in cosmetics:
		if c["slot"] == slot:
			out.append(c)
	return out


func get_modifier(id: String) -> Dictionary:
	return modifiers.get(id, {})


func achievement_list() -> Array:
	var out := []
	for a in flavor.get("achievements", []):
		out.append(a)
	return out


func random_tip(rng: RandomNumberGenerator) -> String:
	var tips: Array = flavor.get("tips", [])
	if tips.is_empty():
		return ""
	return tips[rng.randi_range(0, tips.size() - 1)]


func random_announcement(rng: RandomNumberGenerator) -> String:
	var a: Array = flavor.get("announcements", [])
	if a.is_empty():
		return ""
	return a[rng.randi_range(0, a.size() - 1)]


func random_line(group: String, rng: RandomNumberGenerator) -> String:
	var rep: Dictionary = flavor.get("report", {})
	var arr: Array = rep.get(group, [])
	if arr.is_empty():
		return ""
	return arr[rng.randi_range(0, arr.size() - 1)]


func ending(kind := "success") -> Dictionary:
	var e = flavor.get("ending", {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var key := kind if e.has(kind) else "success"
	return e.get(key, {})


func story_beat(index: int) -> Dictionary:
	var s: Array = flavor.get("story", [])
	if index >= 0 and index < s.size():
		return s[index]
	return {}
