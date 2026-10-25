## ======================================================
## mobile_ui.gd — HUD & ปุ่มควบคุมสำหรับมือถือ (Mobile Touch UI)
##
## - ปุ่ม Action วงกลม (ไอคอน 🥫 / 🎯)
## - ปุ่ม Crouch วงกลม (ไอคอน 👟 / 🤫)
## - ปุ่ม Hide วงกลม (ไอคอน 📦 / 🚪)
## - Squint Overlay (มุมมองหรี่ตาแคบลงเมื่อแอบในกล่อง)
## - GameOverScreen (เมื่อผีตีทีเดียวตาย + ปุ่มเริ่มเกมใหม่)
## - WinScreen (เมื่อผู้เล่นเดินถึง Exit ชนะเกม)
## ======================================================
extends CanvasLayer

@onready var action_button: Button = $Control/ActionButton
@onready var crouch_button: Button = get_node_or_null("Control/CrouchButton")
@onready var hide_button: Button = get_node_or_null("Control/HideButton")
@onready var crosshair: Control = $Control/Crosshair

@onready var squint_overlay: Control = get_node_or_null("Control/SquintOverlay")
@onready var top_bar: ColorRect = get_node_or_null("Control/SquintOverlay/TopBar")
@onready var bottom_bar: ColorRect = get_node_or_null("Control/SquintOverlay/BottomBar")

@onready var game_over_screen: Control = get_node_or_null("Control/GameOverScreen")
@onready var restart_button: Button = get_node_or_null("Control/GameOverScreen/VBox/RestartButton")

@onready var win_screen: Control = get_node_or_null("Control/WinScreen")
@onready var win_restart_button: Button = get_node_or_null("Control/WinScreen/VBox/RestartButton")

var _player: Node = null
var _pulse_timer: float = 0.0
var _was_hidden: bool = false

func _ready() -> void:
	add_to_group("mobile_ui")

	if action_button:
		action_button.add_to_group("mobile_ui_button")
		action_button.pressed.connect(_on_action_button_pressed)

	if crouch_button:
		crouch_button.add_to_group("mobile_ui_button")
		crouch_button.pressed.connect(_on_crouch_button_pressed)

	if hide_button:
		hide_button.add_to_group("mobile_ui_button")
		hide_button.pressed.connect(_on_hide_button_pressed)

	if restart_button:
		restart_button.add_to_group("mobile_ui_button")
		restart_button.pressed.connect(_on_restart_button_pressed)

	if win_restart_button:
		win_restart_button.add_to_group("mobile_ui_button")
		win_restart_button.pressed.connect(_on_restart_button_pressed)

	await get_tree().process_frame
	_find_player()

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		_player = get_tree().get_root().find_child("player", true, false)

	if _player and _player.has_signal("player_died"):
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)

func _process(delta: float) -> void:
	if _player == null:
		_find_player()
		if _player == null:
			return

	if _player.get("is_dead"):
		return

	var is_hidden: bool = _player.has_method("is_hidden") and _player.is_hidden()
	var is_holding: bool = _player.has_method("is_holding_can") and _player.is_holding_can()
	var nearby_can: Node = null
	if not is_holding and _player.has_method("get_closest_can_in_range"):
		nearby_can = _player.get_closest_can_in_range(3.0)

	var nearby_box: Node = null
	if not is_hidden and _player.has_method("get_closest_hiding_box"):
		nearby_box = _player.get_closest_hiding_box(2.8)

	# เช็คการเปลี่ยนสถานะการซ่อนเพื่อ trigger แอนิเมชันหรี่ตา
	if is_hidden != _was_hidden:
		_was_hidden = is_hidden
		_animate_squint(is_hidden)

	_update_ui(is_hidden, is_holding, nearby_can != null, nearby_box != null, delta)

func _update_ui(is_hidden: bool, is_holding: bool, can_nearby: bool, box_nearby: bool, delta: float) -> void:
	_pulse_timer += delta * 5.0

	# 1. Hide Button (ซ่อนตัวในกล่อง / ออกจากกล่อง)
	if hide_button:
		if is_hidden:
			hide_button.visible = true
			hide_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		elif box_nearby:
			hide_button.visible = true
			var pulse_val := 0.85 + sin(_pulse_timer) * 0.15
			hide_button.modulate = Color(1.0, 1.0, 1.0, pulse_val)
		else:
			hide_button.visible = false

	# เมื่อแอบอยู่ในกล่อง ให้ซ่อนปุ่มอื่นๆ และเป้าเล็ง
	if is_hidden:
		if action_button:
			action_button.visible = false
		if crouch_button:
			crouch_button.visible = false
		if crosshair:
			crosshair.visible = false
		return

	# สถานะปกติ (ไม่ได้แอบ)
	if crosshair:
		crosshair.visible = true

	if action_button:
		if is_holding:
			action_button.visible = true
			action_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		elif can_nearby:
			action_button.visible = true
			var pulse_val := 0.85 + sin(_pulse_timer) * 0.15
			action_button.modulate = Color(1.0, 1.0, 1.0, pulse_val)
		else:
			action_button.visible = false

	if crouch_button and _player and _player.has_method("is_crouching"):
		crouch_button.visible = true
		var is_crouching: bool = _player.is_crouching()
		if is_crouching:
			crouch_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			crouch_button.modulate = Color(1.0, 1.0, 1.0, 0.75)

func _animate_squint(hidden: bool) -> void:
	if squint_overlay == null or top_bar == null or bottom_bar == null:
		return

	var tw := create_tween().set_parallel(true)
	if hidden:
		tw.tween_property(squint_overlay, "modulate:a", 1.0, 0.35)
		tw.tween_property(top_bar, "anchor_bottom", 0.36, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(bottom_bar, "anchor_top", 0.64, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(squint_overlay, "modulate:a", 0.0, 0.25)
		tw.tween_property(top_bar, "anchor_bottom", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(bottom_bar, "anchor_top", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_player_died() -> void:
	# ซ่อนปุ่มและ HUD ควบคุม
	if action_button: action_button.visible = false
	if crouch_button: crouch_button.visible = false
	if hide_button: hide_button.visible = false
	if crosshair: crosshair.visible = false

	# แสดงหน้าต่าง Game Over พร้อมปุ่มเริ่มเกมใหม่
	if game_over_screen:
		game_over_screen.visible = true
		game_over_screen.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(game_over_screen, "modulate:a", 1.0, 0.7)

func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()

## แสดงหน้าต่าง Win (ชนะ) พร้อม fade-in
func show_win_screen() -> void:
	# ซ่อนปุ่มและ HUD ควบคุม
	if action_button: action_button.visible = false
	if crouch_button: crouch_button.visible = false
	if hide_button: hide_button.visible = false
	if crosshair: crosshair.visible = false

	# ปล่อยเมาส์
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if win_screen:
		win_screen.visible = true
		win_screen.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(win_screen, "modulate:a", 1.0, 1.0)

func _on_action_button_pressed() -> void:
	if _player and _player.has_method("interact_can"):
		_player.interact_can()
		_bounce_button(action_button)

func _on_crouch_button_pressed() -> void:
	if _player and _player.has_method("toggle_crouch"):
		_player.toggle_crouch()
		if crouch_button:
			_bounce_button(crouch_button)

func _on_hide_button_pressed() -> void:
	if _player and _player.has_method("toggle_hide_in_box"):
		_player.toggle_hide_in_box()
		if hide_button:
			_bounce_button(hide_button)

func _bounce_button(btn: Control) -> void:
	if btn == null:
		return
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.05)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08)
