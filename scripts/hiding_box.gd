## ======================================================
## hiding_box.gd — กล่องซ่อนตัวสำหรับผู้เล่น (Hiding Box)
##
## - เป็นจุดซ่อนตัวจากผีทั่วแมพ
## - เมื่อผู้เล่นกดซ่อน ผีจะหาไม่เจอแม้กำลังโดนไล่
## ======================================================
extends Node3D

@export var prompt_text: String = "ซ่อนตัว"

var _is_occupied: bool = false
var _prompt_light: OmniLight3D = null

func _ready() -> void:
	add_to_group("hiding_box")
	_prompt_light = get_node_or_null("PromptLight")
	if _prompt_light:
		_prompt_light.light_energy = 0.3

func is_occupied() -> bool:
	return _is_occupied

func set_occupied(occupied: bool) -> void:
	_is_occupied = occupied
	if _prompt_light:
		_prompt_light.visible = not occupied

func get_hiding_position() -> Vector3:
	# กล่องอยู่ที่ระดับพื้น Y ~ -0.7 ตัวผู้เล่น (ความสูง Capsule 2.0 ม.)
	# ต้องวางจุดศูนย์กลางที่ +1.0 ม. เหนือพื้น เพื่อให้เท้าแตะพื้นกล่องพอดี ไม่จมลงใต้แมพ
	return global_position + Vector3(0, 1.0, 0)

func get_exit_position(pre_hide_pos: Vector3 = Vector3.ZERO) -> Vector3:
	# ถ้ามีตำแหน่งก่อนซ่อน (ซึ่งยืนอยู่บนพื้นปกติอย่างปลอดภัย) ให้ก้าวออกมาทางนั้น
	if pre_hide_pos != Vector3.ZERO:
		var dir := (pre_hide_pos - global_position)
		dir.y = 0.0
		if dir.length() > 0.1:
			var exit_xz := global_position + dir.normalized() * 1.45
			return Vector3(exit_xz.x, pre_hide_pos.y, exit_xz.z)
		return pre_hide_pos
	# ถ้าไม่มี ให้ก้าวออกมาทางทิศหน้ากล่อง และรักษาระดับความสูงตัวผู้เล่น (+1.0 ม. เหนือพื้นกล่อง)
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	return global_position + fwd * 1.45 + Vector3(0, 1.0, 0)
