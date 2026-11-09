class_name U
extends RefCounted
## Small stateless helpers shared by every system.
## Keeping these in one place avoids duplicated (and drifting) utility code.

static func fmt_clock(seconds: float) -> String:
	if seconds < 0.0:
		seconds = 0.0
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]

static func fmt_money(amount: int) -> String:
	var neg := amount < 0
	var s := str(absi(amount))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("- $" if neg else "$") + out

static func fmt_mass(kg: float) -> String:
	if kg >= 100.0:
		return "%d kg" % int(kg)
	return "%.1f kg" % kg

static func rng_for(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(seed_value))
	return r

static func pick_weighted(items: Array, weights: Array, rng: RandomNumberGenerator):
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return null if items.is_empty() else items[0]
	var roll := rng.randf() * total
	var acc := 0.0
	for i in items.size():
		acc += maxf(0.0, float(weights[i]))
		if roll <= acc:
			return items[i]
	return items[items.size() - 1]

static func shuffled(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a

## Frame-rate independent exponential smoothing.
static func damp(current: float, target: float, smoothing: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-smoothing * delta))

static func damp_v3(current: Vector3, target: Vector3, smoothing: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-smoothing * delta))

static func damp_angle(current: float, target: float, smoothing: float, delta: float) -> float:
	return current + wrapf(target - current, -PI, PI) * (1.0 - exp(-smoothing * delta))

static func safe_dir(v: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	return v.normalized() if v.length_squared() > 0.000001 else fallback

static func approach(current: float, target: float, step: float) -> float:
	if current < target:
		return minf(current + step, target)
	return maxf(current - step, target)

## Builds a human readable list: ["a","b","c"] -> "a, b and c"
static func join_words(arr: Array, conj := "and") -> String:
	var parts: Array[String] = []
	for a in arr:
		parts.append(str(a))
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " " + conj + " " + parts[-1]

static func plural(n: int, singular: String, plural_form := "") -> String:
	if n == 1:
		return "%d %s" % [n, singular]
	if plural_form == "":
		plural_form = singular + "s"
	return "%d %s" % [n, plural_form]

static func json_read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("json_read: missing %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_error("json_read parse error in %s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data

## Picks a variation variant deterministically from a seed string.
static func variant_index(seed_text: String, count: int) -> int:
	if count <= 0:
		return 0
	return abs(hash(seed_text)) % count

static func node_or_null(root: Node, path: NodePath) -> Node:
	if root == null:
		return null
	return root.get_node_or_null(path)

## Tints a colour the way the game's lighting model expects (keeps saturation sane).
static func tint(c: Color, amount: float) -> Color:
	return Color(
		clampf(c.r * (1.0 + amount), 0.0, 1.0),
		clampf(c.g * (1.0 + amount), 0.0, 1.0),
		clampf(c.b * (1.0 + amount), 0.0, 1.0),
		c.a)
