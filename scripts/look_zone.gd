## Stub — look input is handled directly in player.gd
## Node นี้มีไว้เฉพาะป้องกัน error จาก scene reference เท่านั้น
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ปิด input processing ทั้งหมด — player.gd จัดการแทน
	set_process_input(false)
	set_process(false)
