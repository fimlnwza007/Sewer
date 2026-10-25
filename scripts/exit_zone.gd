## ======================================================
## exit_zone.gd — จุดออก (Exit) เมื่อผู้เล่นเดินเข้ามาจะชนะเกม
## ======================================================
extends Area3D

signal player_won

## เส้นทางไปยัง MobileUI เพื่อแสดง Win Screen
@export var mobile_ui_path: NodePath = NodePath("")

@onready var glow_light: OmniLight3D = get_node_or_null("OmniLight3D")
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")

var _triggered: bool = false
var _pulse_timer: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("exit_zone")

func _process(delta: float) -> void:
	# ไฟกะพริบๆ บอกว่าคือทางออก
	if glow_light and not _triggered:
		_pulse_timer += delta * 2.5
		glow_light.light_energy = 1.8 + sin(_pulse_timer) * 0.7

func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	if body.get("is_dead"):
		return

	_triggered = true
	_show_win_screen()

func _show_win_screen() -> void:
	# หยุดผีทุกตัวก่อน
	for ghost in get_tree().get_nodes_in_group("phee_tor"):
		if ghost.has_method("_set_state"):
			ghost.set_process(false)
			ghost.set_physics_process(false)

	# ส่ง signal ไปยัง MobileUI
	var ui_nodes := get_tree().get_nodes_in_group("mobile_ui")
	for ui in ui_nodes:
		if ui.has_method("show_win_screen"):
			ui.show_win_screen()
