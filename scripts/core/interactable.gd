class_name Interactable
extends Area3D
## Generic "press E" point used by the contract board, lockers, upgrade station, radios,
## switches and other small mission props. Levels subclass or configure this instead of
## writing one-off scripts.

signal activated(by_player)

@export var prompt_title := "Interact"
@export var prompt_sub := "[E]"
@export var one_shot := false
@export var enabled := true

var _used := false


func _ready() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	monitoring = false
	monitorable = true


func setup(title: String, sub: String, pos: Vector3, extents := Vector3(0.5, 0.5, 0.5)) -> void:
	prompt_title = title
	prompt_sub = sub
	position = pos
	var cs := get_node_or_null("Shape") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "Shape"
		add_child(cs)
	var box := BoxShape3D.new()
	box.size = extents * 2.0
	cs.shape = box


func activate(by_player: Node) -> void:
	if not enabled or (one_shot and _used):
		Audio.play_sfx("click_denied", global_position, -6.0)
		return
	_used = true
	Audio.play_sfx("click", global_position, -8.0)
	activated.emit(by_player)
