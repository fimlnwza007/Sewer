## โซนด้านขวาของจอสำหรับหันหน้า (มือถือ)
extends Control

## ความไวในการหันหน้า
@export var look_sensitivity: float = 0.5

## Path ไปยัง player node
@export var player_path: NodePath

var _touch_index: int = -1
var _last_position: Vector2 = Vector2.ZERO
var _accumulated_look: Vector2 = Vector2.ZERO
var _player: CharacterBody3D = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player_path:
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_root().find_child("player", true, false)

func _is_in_zone(pos: Vector2) -> bool:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# ครึ่งขวาของหน้าจอ
	return pos.x >= vp_size.x * 0.45 and pos.y >= 0.0 and pos.y <= vp_size.y

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if _is_in_zone(event.position):
				_touch_index = event.index
				_last_position = event.position
				_accumulated_look = Vector2.ZERO
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_accumulated_look = Vector2.ZERO
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			# คำนวณ delta เองจาก position ของนิ้วนี้โดยเฉพาะ
			# เพื่อแก้ปัญหาบั๊ก event.relative ของ Godot ที่คำนวณสลับนิ้วเวลาแตะ 2 นิ้วพร้อมกัน
			var delta := event.position - _last_position
			_last_position = event.position

			# ป้องกันค่ากระโดดผิดปกติ (Spike guard)
			if delta.length() < 250.0:
				_accumulated_look += delta * look_sensitivity
			
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _accumulated_look != Vector2.ZERO and _player != null:
		_player.apply_look_delta(_accumulated_look)
		_accumulated_look = Vector2.ZERO
