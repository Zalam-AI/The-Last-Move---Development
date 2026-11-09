extends Node
## Carry-physics test: proves the central mechanic with real forces, not teleports.
##
##  * one mover can lift a light chair clear of the floor and carry it
##  * one mover cannot lift a grand piano: it drags, which is the intended comedy
##  * a shoved door opens for moving furniture
##  * the grip breaks when the carrier walks off
##  * cargo validation rejects an item that is only half inside the hold

var checks := 0
var failures := 0
var player: Player
var mission: MissionManager


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== CARRY PHYSICS TEST ===========")
	Save.reset_profile()
	Game.start_solo()
	await get_tree().process_frame
	Game.start_mission("willow", 2024, [])
	await get_tree().process_frame
	for i in 20:
		await get_tree().physics_frame
	mission = Game.mission
	player = Game.get_player(1)
	_check(mission != null and player != null, "mission and player ready")
	if mission == null or player == null:
		_finish()
		return
	await _test_light_carry()
	await _test_heavy_drag()
	await _test_grip_break()
	await _test_door_shove()
	await _test_cargo_rejection()
	_finish()


func _find(item_ids: Array, required := false) -> Furniture:
	for f in mission.furniture:
		if not is_instance_valid(f):
			continue
		if item_ids.is_empty() or f.item_id in item_ids:
			if not required or f.is_required:
				return f
	return null


## Finds a patch of flat ground with 20 m of clear space to the north, so a carry test
## measures the carry forces instead of a wall the player walked into.
func _open_lane(preferred: Vector3) -> Vector3:
	var space := mission.get_world_3d().direct_space_state
	for offset in [Vector3.ZERO, Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 6), Vector3(8, 0, 4)]:
		var origin: Vector3 = preferred + offset
		var blocked := false
		for y in [0.5, 1.4]:
			var q := PhysicsRayQueryParameters3D.create(origin + Vector3(0, y, 0), origin + Vector3(0, y, 20), Layers.WORLD)
			if not space.intersect_ray(q).is_empty():
				blocked = true
				break
		if not blocked:
			return origin
	return preferred


## Removes the mover's body from collision entirely so a tow test measures the grip
## forces rather than the character capsule bulldozing the object.
func _isolate_player(on: bool) -> void:
	if on:
		player.collision_layer = 0
		player.collision_mask = Layers.WORLD
	else:
		player.collision_layer = Layers.PLAYER
		player.collision_mask = Layers.PLAYER_MASK


func _place_player(pos: Vector3, yaw := 0.0) -> void:
	player.global_position = pos + Vector3(0, 0.15, 0)
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


## Walks the carrier toward a target by nudging the body, which is what the PD grip
## follows in play. Any real movement of the object comes from the physics forces.
func _walk_toward(target_pos: Vector3, frames: int, speed := 0.045) -> void:
	for i in frames:
		if player.carried == null:
			return
		var dir := target_pos - player.global_position
		dir.y = 0
		if dir.length() > 0.25:
			player.global_position += dir.normalized() * speed
			player.velocity = Vector3.ZERO
		await get_tree().physics_frame


func _test_light_carry() -> void:
	var chair := _find(["dining_chair", "stool", "sideboard"], false)
	if chair == null:
		chair = _find([], false)
	_check(chair != null and chair.weight <= 30.0, "found a light item to carry (%s, %.0f kg)" % [
		chair.item_id if chair else "-", chair.weight if chair else 0.0])
	if chair == null:
		return
	# Carry in open ground north of the lot, verified clear for 20 m, so the measurement
	# is of the carry force and nothing else.
	var lane := _open_lane(Vector3(0, 0, 40.0))
	chair.global_position = lane + Vector3(0, 0.12, 1.2)
	chair.linear_velocity = Vector3.ZERO
	chair.angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	_place_player(lane, PI)
	await get_tree().physics_frame
	var start_floor := chair.global_position.y
	player._request_grab(chair)
	await get_tree().physics_frame
	_check(chair.holders.has(player.peer_id), "one mover takes a grip")
	var peak := start_floor
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, chair.global_position.y)
	var lifted := peak
	_check(lifted > start_floor + 0.12, "light item lifts off the floor (%.2f -> %.2f)" % [start_floor, lifted])
	# tow it with the grip alone: the mover stops colliding with furniture so the test
	# measures the carry force, not the character body bulldozing the object
	var before := chair.global_position
	_isolate_player(true)
	await _walk_toward(lane + Vector3(0, 0, 9.0), 150)
	_isolate_player(false)
	var travelled := before.distance_to(chair.global_position)
	_check(travelled > 1.2, "carried item travels with the mover (%.2f m)" % travelled)
	_check(chair.holders.has(player.peer_id), "grip survives a normal carry")
	player._request_release()
	await get_tree().create_timer(0.3).timeout
	_check(chair.holders.is_empty(), "releasing clears the grip")


func _test_heavy_drag() -> void:
	var heavy := _find(["piano_grand", "piano_upright", "organ", "wardrobe"], false)
	if heavy == null:
		_check(false, "no heavy item present")
		return
	_check(heavy.min_carriers >= 2, "heavy item needs a crew (%s, %d carriers)" % [heavy.item_id, heavy.min_carriers])
	# deliberately under-crewed: one mover on a two-person item
	var lane3 := _open_lane(Vector3(14, 0, 40.0))
	heavy.global_position = lane3 + Vector3(0, 0.12, 1.2)
	heavy.linear_velocity = Vector3.ZERO
	heavy.angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	_place_player(lane3, PI)
	await get_tree().physics_frame
	var start := heavy.global_position
	player._request_grab(heavy)
	await get_tree().physics_frame
	_isolate_player(true)
	await _walk_toward(lane3 + Vector3(0, 0, 9.0), 150)
	_isolate_player(false)
	var lifted := heavy.global_position.y - start.y
	var moved := Vector2(heavy.global_position.x - start.x, heavy.global_position.z - start.z).length()
	_check(lifted < 0.55, "under-crewed heavy item does not fly (lifted %.2f m)" % lifted)
	_check(moved > 0.12, "under-crewed heavy item skids along the floor (%.2f m while the mover walked 9 m)" % moved)
	_check(moved < 4.0, "under-crewed heavy item is not carried away (%.2f m)" % moved)
	player._request_release()
	await get_tree().physics_frame


func _test_grip_break() -> void:
	var item := _find(["dining_chair", "stool", "coffee_table", "sideboard"], false)
	if item == null:
		item = _find([], false)
	if item == null:
		return
	var lane2 := _open_lane(Vector3(-14, 0, 40.0))
	item.freeze = false
	item.release_all()
	item.global_position = lane2 + Vector3(0, 0.12, 1.2)
	await get_tree().physics_frame
	_place_player(lane2, PI)
	await get_tree().physics_frame
	player._request_grab(item)
	await get_tree().physics_frame
	_check(item.holders.has(player.peer_id), "grip taken before the break test")
	# walk away without letting go; the grip has a hard distance limit
	player.global_position = item.global_position + Vector3(0, 0, Furniture.GRIP_BREAK_DIST + 4.0)
	for i in 40:
		await get_tree().physics_frame
	_check(not item.holders.has(player.peer_id), "grip breaks at %.1f m" % Furniture.GRIP_BREAK_DIST)
	if player.carried != null:
		player.force_drop()
	await get_tree().physics_frame


func _test_door_shove() -> void:
	# Pick a door with a clear approach on its +Z side: the truck's ramp sits outside the
	# front door in this property, so "the first unlocked door" is not good enough.
	var truck_pos := mission.truck.global_position
	var door: Door = null
	var door_start := Vector3.ZERO
	var space := mission.get_world_3d().direct_space_state
	for d in mission.property.doors:
		if d.locked:
			continue
		var n := d.global_transform.basis.z.normalized()
		if d.global_position.distance_to(truck_pos) < 6.0:
			continue
		var from := d.global_position + n * 1.5 + Vector3(0, 0.6, 0)
		var q := PhysicsRayQueryParameters3D.create(from, d.global_position + n * 0.4 + Vector3(0, 0.6, 0),
			Layers.WORLD | Layers.DOOR | Layers.FURNITURE)
		q.exclude = [d.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		door = d
		door_start = from
		break
	_check(door != null, "found a door with a clear approach")
	if door == null:
		return
	if door.is_open:
		door.open_door(false, true)
	var item := _find(["dining_chair", "stool", "coffee_table", "crate", "suitcase"], false)
	if item == null:
		item = _find([], false)
	if item == null:
		return
	item.release_all()
	# the closed leaf faces along its local -Z
	var door_normal := door.global_transform.basis.z.normalized()
	item.freeze = true
	item.global_position = door_start - Vector3(0, 0.1, 0) + door.global_transform.basis.x * 0.4
	item.freeze = false
	item.linear_velocity = -door_normal * 3.5
	item.angular_velocity = Vector3.ZERO
	for i in 45:
		await get_tree().physics_frame
	_check(door.is_open, "shoved door swings open for moving furniture (item %s, speed was 4.0)" % item.item_id)
	if door.is_open:
		door.open_door(false, true)


func _test_cargo_rejection() -> void:
	var truck := mission.truck
	truck.set_doors(true)
	await get_tree().physics_frame
	var item := _find(["coffee_table", "dining_chair", "crate", "suitcase", "stool"], false)
	if item == null:
		item = _find([], false)
	if item == null:
		return
	item.release_all()
	item.freeze = true
	# half in, half out of the open rear doors
	item.global_position = truck.to_global(Vector3(0, 1.2, Truck.CARGO_LENGTH * 0.5 + 1.2))
	await get_tree().physics_frame
	_check(not item.delivered, "half-loaded item is not accepted")
	item.global_position = truck.to_global(Vector3(0, Truck.CARGO_FLOOR_Y + 0.6, 0))
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.freeze = false
	for i in 150:
		await get_tree().physics_frame
		if item.delivered:
			break
	_check(item.delivered, "fully-loaded item is accepted")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("  %d checks, %d failures" % [checks, failures])
	print("  RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures > 0 else 0)
