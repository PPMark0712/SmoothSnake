class_name SnakeModel
extends RefCounted
## Deterministic simulation; drawing, input, and wall-clock time live elsewhere.

signal apple_eaten(kind: int, position: Vector2, points: int)
signal exploded(position: Vector2, radius: float)
signal died(reason: String)

enum Apple { RED, GOLD, RAINBOW }

const ARENA := Rect2(62, 144, 1316, 628)
const APPLE_RADIUS := 13.0
const BLAST_RADIUS := 108.0
const BOMB_INTERVAL := 10.0
const BOMB_FUSE := 5.0
const TURN_RATE := 2.65
const BASE_APPLES := 5
const CONTACT_COS := 0.7071067811865476

var rng := RandomNumberGenerator.new()
var head := Vector2.ZERO
var heading := 0.0
var score := 0
var alive := true
var elapsed := 0.0
var gold_left := 0.0
var rainbow_left := 0.0
var rainbow_tick := 0.0
var bomb_tick := 0.0
var food_tick := 0.0
var apples: Array[Dictionary] = []
var bombs: Array[Dictionary] = []
var body: Array[Vector2] = []
var trail: Array[Vector2] = []


func reset(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	head = Vector2(640, 458)
	heading = -0.12
	score = 0
	alive = true
	elapsed = 0.0
	gold_left = 0.0
	rainbow_left = 0.0
	rainbow_tick = 0.0
	bomb_tick = 0.0
	food_tick = 0.0
	apples.clear()
	bombs.clear()
	trail.clear()
	for i in range(1001):
		trail.append(head - Vector2.from_angle(heading) * float(i) * 3.0)
	rebuild_body()
	# The first apple is within reach; the rest use the same empty-space checks.
	apples.append({"position": Vector2(835, 434), "kind": Apple.RED})
	for i in range(BASE_APPLES - 1):
		spawn_apple()


static func radius_at(points: int) -> float:
	return 11.0 + 6.0 * (sqrt(1.0 + float(points) / 10.0) - 1.0)


static func gap_at(points: int) -> float:
	return 8.0 / (1.0 + float(points) / 35.0)


static func length_at(points: int) -> float:
	# Length is measured along the trail, from head center to tail center.
	if points <= 5:
		var r := radius_at(points)
		return r * 2.24 + gap_at(points) + (2.0 * r + gap_at(points)) * (points + 1)
	return length_at(5) + 620.0 * (sqrt(1.0 + float(points - 5) / 10.0) - 1.0)


func radius() -> float:
	return radius_at(score)


func head_radius() -> float:
	return radius() * 1.24


func speed() -> float:
	var base := 156.0 + 65.0 * (sqrt(1.0 + float(score) / 15.0) - 1.0)
	return base * (2.0 if gold_left > 0.0 else 1.0)


static func lethal_contact(direction: Vector2, outward_normal: Vector2) -> bool:
	# Surface normals point out of the obstacle, opposite the incoming velocity.
	return -direction.normalized().dot(outward_normal.normalized()) >= CONTACT_COS - 0.000001


func step(delta: float, steering: float) -> void:
	if not alive:
		return
	elapsed += delta
	gold_left = maxf(0.0, gold_left - delta)
	if rainbow_left > 0.0:
		var active_delta := minf(delta, rainbow_left)
		rainbow_tick += active_delta
		rainbow_left = maxf(0.0, rainbow_left - delta)
		while rainbow_tick >= 2.0 - 0.000001:
			rainbow_tick -= 2.0
			spawn_apple()
	for i in range(bombs.size() - 1, -1, -1):
		bombs[i]["left"] -= delta
		if bombs[i]["left"] <= 0.0:
			var center: Vector2 = bombs[i]["position"]
			bombs.remove_at(i)
			exploded.emit(center, BLAST_RADIUS)
			if head.distance_to(center) <= BLAST_RADIUS:
				kill("Caught in a blast")
				return
	bomb_tick += delta
	while bomb_tick >= BOMB_INTERVAL - 0.000001:
		bomb_tick -= BOMB_INTERVAL
		spawn_bomb()
	# Small steps prevent tunneling, including while the gold boost is active.
	var distance := speed() * delta
	var steps := maxi(1, ceili(distance / 3.0))
	for i in range(steps):
		heading += clampf(steering, -1.0, 1.0) * TURN_RATE * delta / steps
		var direction := Vector2.from_angle(heading)
		head += direction * distance / steps
		resolve_walls(direction)
		if not alive:
			return
		resolve_body(Vector2.from_angle(heading))
		if not alive:
			return
		record_trail()
		rebuild_body()
		collect_apples()
	food_tick += delta
	if food_tick >= 0.5:
		food_tick = 0.0
		if apples.size() < BASE_APPLES:
			spawn_apple()


func resolve_walls(direction: Vector2) -> void:
	var bounds := ARENA.grow(-head_radius())
	var normals: Array[Vector2] = []
	if head.x < bounds.position.x:
		normals.append(Vector2.RIGHT)
	if head.x > bounds.end.x:
		normals.append(Vector2.LEFT)
	if head.y < bounds.position.y:
		normals.append(Vector2.DOWN)
	if head.y > bounds.end.y:
		normals.append(Vector2.UP)
	for normal in normals:
		if lethal_contact(direction, normal):
			kill("A head-on wall collision")
			return
		var tangent := Vector2.from_angle(heading).slide(normal)
		if tangent.length_squared() > 0.0001:
			heading = tangent.angle()
	head = head.clamp(bounds.position, bounds.end)


func resolve_body(direction: Vector2) -> void:
	# Ignore the neck, which is attached to the head, but test all later balls.
	for i in range(2, body.size()):
		var offset := head - body[i]
		var contact_radius := head_radius() + radius()
		if offset.length_squared() >= contact_radius * contact_radius:
			continue
		var normal := offset.normalized() if offset.length_squared() > 0.0001 else -direction
		if lethal_contact(direction, normal):
			kill("A head-on body collision")
			return
		head = body[i] + normal * (contact_radius + 0.05)
		var tangent := Vector2.from_angle(heading).slide(normal)
		if tangent.length_squared() > 0.0001:
			heading = tangent.angle()
	# A body slide near an edge must still respect the arena.
	resolve_walls(Vector2.from_angle(heading))


func record_trail() -> void:
	if trail.is_empty() or head.distance_squared_to(trail[0]) >= 1.0:
		trail.push_front(head)
	var kept := 0.0
	for i in range(1, trail.size()):
		kept += trail[i - 1].distance_to(trail[i])
		if kept > length_at(score) + 600.0:
			trail.resize(i + 1)
			break


func rebuild_body() -> void:
	body.clear()
	var first := head_radius() + radius() + gap_at(score)
	var total := length_at(score)
	var count := (
		2 + score
		if score <= 5
		else maxi(7, ceili((total - first) / (2.0 * radius() + gap_at(score))) + 1)
	)
	var spacing := (total - first) / float(count - 1)
	var path: Array[Vector2] = [head]
	path.append_array(trail)
	var segment := 0
	var walked := 0.0
	for i in range(count):
		var target := first + i * spacing
		while (
			segment < path.size() - 2
			and walked + path[segment].distance_to(path[segment + 1]) < target
		):
			walked += path[segment].distance_to(path[segment + 1])
			segment += 1
		var segment_length := path[segment].distance_to(path[segment + 1])
		var weight := clampf((target - walked) / maxf(segment_length, 0.0001), 0.0, 1.0)
		body.append(path[segment].lerp(path[segment + 1], weight))


func collect_apples() -> void:
	for i in range(apples.size() - 1, -1, -1):
		var apple: Dictionary = apples[i]
		if head.distance_to(apple["position"]) <= head_radius() + APPLE_RADIUS:
			apples.remove_at(i)
			award_apple(apple["kind"], apple["position"])
	if apples.size() < BASE_APPLES:
		spawn_apple()


func award_apple(kind: int, position: Vector2) -> void:
	var points := 1
	if kind == Apple.GOLD:
		points = 5
		gold_left = 10.0
	elif kind == Apple.RAINBOW:
		points = 10
		rainbow_left = 20.0
		rainbow_tick = 0.0
	score += points
	rebuild_body()
	apple_eaten.emit(kind, position, points)


func random_kind() -> int:
	var roll := rng.randf()
	if roll < 0.10:
		return Apple.RAINBOW
	if roll < 0.28:
		return Apple.GOLD
	return Apple.RED


func empty_position(clearance: float) -> Vector2:
	# Bounded search: crowded boards defer spawning instead of hanging.
	var bounds := ARENA.grow(-clearance - 12.0)
	for attempt in range(180):
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if candidate.distance_to(head) < head_radius() + clearance + 100.0:
			continue
		var clear := true
		for ball in body:
			if candidate.distance_to(ball) < radius() + clearance + 10.0:
				clear = false
				break
		if not clear:
			continue
		for apple in apples:
			if candidate.distance_to(apple["position"]) < clearance + APPLE_RADIUS + 22.0:
				clear = false
				break
		if not clear:
			continue
		for bomb in bombs:
			if candidate.distance_to(bomb["position"]) < clearance + 26.0:
				clear = false
				break
		if clear:
			return candidate
	return Vector2.INF


func spawn_apple(kind: int = -1) -> bool:
	var position := empty_position(APPLE_RADIUS)
	if position == Vector2.INF:
		return false
	apples.append({"position": position, "kind": random_kind() if kind < 0 else kind})
	return true


func spawn_bomb() -> bool:
	var position := empty_position(22.0)
	if position == Vector2.INF:
		return false
	bombs.append({"position": position, "left": BOMB_FUSE})
	return true


func kill(reason: String) -> void:
	if not alive:
		return
	alive = false
	died.emit(reason)
