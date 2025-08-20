extends Area2D
signal collected(value: int)
@export var value: int = 1

func _input_event(_vp, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("collected", value)
		queue_free()
		
