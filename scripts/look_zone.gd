## โซนด้านขวาของจอสำหรับหันหน้า (มือถือ)
## แก้ปัญหา Multi-touch jitter ด้วย:
##  - คำนวณ delta จาก _last_position แทน event.relative (ป้องกัน Godot multi-touch bug)
##  - Spike clamp (ตัดค่ากระโดดผิดปกติ)
##  - Exponential smoothing (ทำให้การหันหน้าเนียน ไม่กระตุก)
extends Control

## ความไวในการหันหน้า
@export var look_sensitivity: float = 0.5

## ความเนียนของการหันหน้า (0=ไม่ smooth, 1=smooth มาก แต่หน่วง)
@export_range(0.0, 0.95, 0.05) var smoothing: float = 0.7

## Path ไปยัง player node
@export var player_path: NodePath

## ค่า delta สูงสุดต่อ event ก่อน clamp (px)
const MAX_SPIKE_PX := 80.0

var _touch_index: int = -1
var _last_position: Vector2 = Vector2.ZERO
var _target_delta: Vector2 = Vector2.ZERO
var _player: CharacterBody3D = null

func _ready() -> void:
	# ไม่บล็อก event ใดๆ ของ GUI — รับเฉพาะผ่าน _input()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player_path:
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_root().find_child("player", true, false)

## ตรวจว่า position อยู่ในโซนขวาของหน้าจอ
func _is_in_zone(pos: Vector2) -> bool:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# ใช้ 45% เพื่อให้โซนทับกันกลางจอเล็กน้อย ป้องกันรอยต่อ
	return pos.x >= vp.x * 0.45 and pos.y >= 0.0 and pos.y <= vp.y

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _is_in_zone(event.position):
			_touch_index = event.index
			_last_position = event.position
			_target_delta = Vector2.ZERO
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			# ค่อยๆ หยุด ไม่ตัดทันที
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if event.index != _touch_index:
			return

		# คำนวณ delta จาก position ของนิ้วนี้เอง (ไม่ใช้ event.relative)
		# เพื่อหลีกเลี่ยงบั๊ก Godot multi-touch ที่ relative สลับนิ้วกัน
		var raw_delta := event.position - _last_position
		_last_position = event.position

		# Spike Clamp: ตัดค่ากระโดดผิดปกติที่เกิดตอนวางนิ้วที่ 2
		if raw_delta.length() > MAX_SPIKE_PX:
			raw_delta = raw_delta.normalized() * MAX_SPIKE_PX

		# Exponential smoothing: ผสมค่าใหม่เข้ากับค่าเก่าแบบค่อยเป็นค่อยไป
		_target_delta = _target_delta.lerp(raw_delta, 1.0 - smoothing)

		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _player == null:
		return

	if _touch_index == -1:
		# ไม่มีนิ้วสัมผัส — ค่อยๆ ลด delta ให้เป็น 0 (inertia decay)
		_target_delta = _target_delta.lerp(Vector2.ZERO, 0.4)
	
	# ใช้ threshold เล็กน้อยป้องกันการหมุนกล้องเพราะ float noise
	if _target_delta.length() > 0.3:
		_player.apply_look_delta(_target_delta * look_sensitivity)
