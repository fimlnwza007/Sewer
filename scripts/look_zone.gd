## โซนด้านขวาของจอสำหรับหันหน้า (มือถือ)
## วางทับพื้นที่ครึ่งขวาของจอ ตรวจจับ drag เพื่อส่งให้ player หันหน้า
extends Control

## ความไวในการหันหน้า
@export var look_sensitivity: float = 0.5

## Path ไปยัง player node
@export var player_path: NodePath

## เก็บ index ของ touch event ที่กำลัง drag อยู่
var _touch_index: int = -1
var _player: CharacterBody3D = null

func _ready() -> void:
	# MOUSE_FILTER_STOP เสมอ — รับทั้ง touch จริงและ InputEventScreenDrag
	# ที่มาจาก emulate_touch_from_mouse บน PC
	mouse_filter = Control.MOUSE_FILTER_STOP
	# resolve player หลัง scene พร้อม
	if player_path:
		_player = get_node_or_null(player_path)
	if _player == null:
		# fallback: หา player จาก root
		_player = get_tree().get_root().find_child("player", true, false)

func _is_in_zone(pos: Vector2) -> bool:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	return (
		pos.x >= vp_size.x * anchor_left and
		pos.x <= vp_size.x * anchor_right and
		pos.y >= vp_size.y * anchor_top and
		pos.y <= vp_size.y * anchor_bottom
	)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and _touch_index == -1:
		if _is_in_zone(event.position):
			_touch_index = event.index
			get_viewport().set_input_as_handled()
	elif not event.pressed and event.index == _touch_index:
		_touch_index = -1
		get_viewport().set_input_as_handled()

func _on_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	if _player == null:
		return
	_player.apply_look_delta(event.relative * look_sensitivity)
	get_viewport().set_input_as_handled()
