extends Node2D

@export var coin_scene: PackedScene = preload("res://CoperCoin.tscn")
@export var spawn_interval: float = 0.1
@export var spawn_limit: int = 30
@export var coin_value_min: int = 1
@export var coin_value_max: int = 3
@export var stack_distance_threshold: float = 40.0 # distancia mínima para considerar que están "muy juntas"
@export var stack_vertical_offset: float = 26.0    # cuánto subir por nivel de apilado
@export var max_stack_height: int = 5               # monedas max por columna antes de crear una nueva           # (DEPRECATED)
@export var stack_x_tolerance: float = 2.0          # tolerancia para considerar la misma columna (diferencia en X)
@export var use_dynamic_stack_offset: bool = true   # si true, calcula el offset a partir de la altura visual de la moneda
@export_range(0.0,1.0,0.05) var stack_overlap_factor: float = 0.9 # 0 = sin overlap (separadas), 1 = totalmente encima
@export var fallback_coin_height: float = 32.0      # altura usada si no se puede calcular la textura
@export var stack_min_distance: float = 0.2         # distancia mínima en píxeles entre centros al apilar (para evitar z-flicker)
@export var smooth_stack_enabled: bool = true       # animar movimiento hacia la columna
@export var smooth_stack_max_distance: float = 40.0 # distancia máxima para animar (si mayor, se teletransporta)
@export var smooth_stack_time: float = 0.25         # duración de la animación de apilado



var score: int = 0
var _cached_coin_height: float = -1.0

@onready var spawn_area: Area2D = $SpanwArea
@onready var spawn_shape: CollisionShape2D = $SpanwArea/CollisionShape2D
@onready var coins_root: Node2D = $CoinRoot
@onready var timer: Timer = $SpawnTimer
@onready var lbl_score: Label = $LblScore

func _ready() -> void:
	timer.wait_time = spawn_interval
	timer.timeout.connect(_on_spawn_timeout)
	_refresh_score()

func _on_spawn_timeout() -> void:

	

	var coin := coin_scene.instantiate()
	coin.value = randi_range(coin_value_min, coin_value_max)

	var spawn_pos := _random_point_in_spawn_area()
	var target_pos := _adjust_for_stacking(spawn_pos)

	# Colocar inicialmente en el spawn original
	coin.position = spawn_pos

	coin.collected.connect(_on_coin_collected)
	coins_root.add_child(coin)

	# Si hay diferencia y procede animación suave
	if smooth_stack_enabled and spawn_pos != target_pos:
		var d := spawn_pos.distance_to(target_pos)
		if d <= smooth_stack_max_distance:
			var tw := coin.create_tween()
			tw.tween_property(coin, "position", target_pos, smooth_stack_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			coin.position = target_pos
			
	if coins_root.get_child_count() >= spawn_limit:
		return  # Limitar número de monedas en pantalla

func _random_point_in_spawn_area() -> Vector2:
	var shape := spawn_shape.shape
	if shape is RectangleShape2D:
		var ext: Vector2 = shape.extents    # mitad del ancho/alto del rect
		var local := Vector2(
			randf_range(-ext.x, ext.x),     # X aleatoria dentro del rect
			randf_range(-ext.y, ext.y)      # Y aleatoria dentro del rect
		)
		return spawn_area.to_global(local)   # convierte de local → global
	return spawn_area.global_position

func _on_coin_collected(value: int) -> void:
	score += value
	_refresh_score()

func _refresh_score() -> void:
	lbl_score.text = "Monedas: %d" % score

func _adjust_for_stacking(pos: Vector2) -> Vector2:
	# Busca la moneda más cercana dentro del radio para intentar apilar en SU columna.
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for c in coins_root.get_children():
		if not c is Node2D:
			continue
		var d: float = c.position.distance_to(pos)
		if d <= stack_distance_threshold and d < nearest_dist:
			nearest = c
			nearest_dist = d

	# No hay columna existente cerca → nueva columna (nueva base)
	if nearest == null:
		return pos

	# Contar cuántas monedas forman parte de la columna (misma X dentro de tolerancia)
	var column_x: float = nearest.position.x
	var heights: Array = []
	for c in coins_root.get_children():
		if not c is Node2D:
			continue
		if abs(c.position.x - column_x) <= stack_x_tolerance and c.position.distance_to(nearest.position) <= stack_distance_threshold:
			heights.append(c)

	var stack_height: int = heights.size()

	# Si la columna alcanzó la altura máxima, crear nueva columna independiente (no apilar)
	if stack_height >= max_stack_height:
		return pos

	# Posicionar exactamente sobre la base (misma X), Y desplazada según altura actual.
	pos.x = column_x

	# Base = la moneda más baja de la columna (mayor Y). Encontrarla.
	var base_y: float = nearest.position.y
	for c in heights:
		if c.position.y > base_y:
			base_y = c.position.y

	# Calcular offset vertical por nivel	
	var per_level: float = stack_vertical_offset

	if use_dynamic_stack_offset:
		per_level = _compute_dynamic_stack_offset()

	# Nueva Y: base_y - per_level * stack_height
	pos.y = base_y - per_level * stack_height
	return pos

func _compute_dynamic_stack_offset() -> float:
	# Devuelve distancia entre centros para el siguiente nivel según overlap.
	var h := _get_coin_height()
	# Distancia entre centros = h * (1 - overlap). Limitar mínimo pequeño para evitar coincidencia exacta.
	var dist := h * (1.0 - stack_overlap_factor)
	return max(stack_min_distance, dist)

func _get_coin_height() -> float:
	if _cached_coin_height > 0.0:
		return _cached_coin_height
	var inst = coin_scene.instantiate()
	var h: float = fallback_coin_height
	if inst is Node:
		var sprite = inst.get_node_or_null("Sprite2D")
		if sprite and sprite is Sprite2D and sprite.texture:
			var tex_h = float(sprite.texture.get_height())
			var scale_y = sprite.scale.y
			h = tex_h * scale_y
	_cached_coin_height = h
	if inst and inst.get_parent() == null:
		inst.queue_free() # por si acaso
	return h
