extends Camera3D
# Orbit around the models: drag with the right mouse button, wheel to zoom.

var target := Vector3.ZERO
var yaw := 0.0
var pitch := -35.0
var dist := 12.0

func _ready():
	var parent = get_parent()
	var box := AABB()
	var first := true
	for c in parent.get_children():
		if c is Node3D and c.name != "Floor" and c != self and not (c is Light3D) and not (c is WorldEnvironment):
			var p = c.position
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	target = box.get_center() + Vector3(0, 0.6, 0)
	dist = max(box.size.length() * 0.9, 4.0)
	_apply()

func _unhandled_input(event):
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= event.relative.x * 0.3
		pitch = clamp(pitch - event.relative.y * 0.3, -85, -5)
		_apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = max(dist * 0.9, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist *= 1.1
		_apply()

func _apply():
	var dir = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)) * Vector3(0, 0, 1)
	position = target + dir * dist
	look_at(target)
