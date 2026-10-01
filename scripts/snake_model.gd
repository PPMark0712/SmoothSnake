# gdlint: disable=max-public-methods
class_name SnakeModel
extends RefCounted
## Deterministic simulation; drawing, input, and wall-clock time live elsewhere.

signal apple_eaten(kind: int, position: Vector2, points: int)
signal exploded(position: Vector2, radius: float)
signal died(reason: String)
signal contact_evaluated(info: Dictionary)

enum Apple { RED, GOLD, RAINBOW, GREEN }
enum Difficulty { EASY, MEDIUM, HARD }

const ARENA := Rect2(48, 130, 1344, 658)
const ARENA_CORNER_RADIUS := 28
const APPLE_RADIUS := 13.0
const BLAST_RADIUS := 108.0
const BOMB_RADIUS := 22.0
const BOMB_INTERVALS := [5.0, 2.5, 1.25]
const BOMB_FUSE := 5.0
const BOMB_SPAWN_REACTION_TIME := 1.0
const TURN_RATE := 6.5
const BASE_APPLES := 5
const GOLD_SPEED_MULTIPLIER := 1.5
const RAINBOW_DURATION := 10.0
const RAINBOW_INTERVAL := 1.0
const CONTACT_COS := 0.7071067811865476
const WALL_EPSILON := 0.001

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
var difficulty := Difficulty.MEDIUM
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
	return base * (GOLD_SPEED_MULTIPLIER if gold_left > 0.0 else 1.0)


func bomb_interval() -> float:
	return BOMB_INTERVALS[difficulty]


func set_difficulty(value: int) -> void:
	var next_difficulty := clampi(value, Difficulty.EASY, Difficulty.HARD)
	if next_difficulty != difficulty:
		bomb_tick = 0.0
	difficulty = next_difficulty


static func lethal_contact(direction: Vector2, separation_normal: Vector2) -> bool:
	# The normal points toward free space, opposite the incoming velocity.
	# A strict comparison keeps the exact 45-degree boundary non-lethal.
	return -direction.normalized().dot(separation_normal.normalized()) > CONTACT_COS + 0.000001


func step(delta: float, steering: float) -> void:
	if not alive:
		return
	elapsed += delta
	gold_left = maxf(0.0, gold_left - delta)
	if rainbow_left > 0.0:
		var active_delta := minf(delta, rainbow_left)
		rainbow_tick += active_delta
		rainbow_left = maxf(0.0, rainbow_left - delta)
		while rainbow_tick >= RAINBOW_INTERVAL - 0.000001:
			rainbow_tick -= RAINBOW_INTERVAL
			spawn_apple(Apple.RED if rng.randi() % 2 == 0 else Apple.GREEN)
	for i in range(bombs.size() - 1, -1, -1):
		bombs[i]["left"] -= delta
		if bombs[i]["left"] <= 0.0:
			detonate_bomb(i)
			if not alive:
				return
	bomb_tick += delta
	var interval := bomb_interval()
	while bomb_tick >= interval - 0.000001:
		bomb_tick -= interval
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
		resolve_bombs()
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


func resolve_bombs() -> void:
	var collision_radius := head_radius() + BOMB_RADIUS
	for i in range(bombs.size() - 1, -1, -1):
		if head.distance_squared_to(bombs[i]["position"]) <= collision_radius * collision_radius:
			detonate_bomb(i)
			return


func detonate_bomb(index: int) -> void:
	var center: Vector2 = bombs[index]["position"]
	bombs.remove_at(index)
	exploded.emit(center, BLAST_RADIUS)
	if head.distance_to(center) <= BLAST_RADIUS:
		kill("Caught in a blast")


func resolve_walls(direction: Vector2) -> void:
	var contact := arena_contact(head)
	if not contact.outside:
		return
	var normal: Vector2 = contact.normal
	var lethal := lethal_contact(direction, normal)
	head = contact.point
	report_contact(
		"wall",
		contact.segment_a,
		contact.segment_b,
		contact.wall_point,
		normal,
		direction,
		lethal,
		-1
	)
	if lethal:
		kill("A head-on wall collision")
		return
	var tangent := Vector2.from_angle(heading).slide(normal)
	if tangent.length_squared() > 0.0001:
		heading = tangent.angle()


func resolve_body(direction: Vector2) -> void:
	# Ignore the neck, which is attached to the head, but test all later balls.
	for i in range(2, body.size()):
		var contact_radius := head_radius() + radius()
		if head.distance_squared_to(body[i]) > contact_radius * contact_radius:
			continue
		var contact := body_segment_contact(i, direction)
		var normal: Vector2 = contact.normal
		var lethal := lethal_contact(direction, normal)
		report_contact(
			"body",
			contact.segment_a,
			contact.segment_b,
			contact.point,
			normal,
			direction,
			lethal,
			i
		)
		if lethal:
			kill("A head-on body collision")
			return
		head = contact.point + normal * (contact_radius + 0.05)
		var tangent := Vector2.from_angle(heading).slide(normal)
		if tangent.length_squared() > 0.0001:
			heading = tangent.angle()
		break
	# A body slide near an edge must still respect the arena.
	resolve_walls(Vector2.from_angle(heading))


func body_segment_contact(body_index: int, direction: Vector2) -> Dictionary:
	var best_point := body[body_index]
	var best_tangent := Vector2.ZERO
	var best_distance := INF
	var best_segment_a := body[body_index]
	var best_segment_b := body[body_index]
	for neighbor in [body_index - 1, body_index + 1]:
		if neighbor < 0 or neighbor >= body.size():
			continue
		var segment := body[neighbor] - body[body_index]
		if segment.length_squared() <= 0.0001:
			continue
		var point := Geometry2D.get_closest_point_to_segment(head, body[body_index], body[neighbor])
		var distance := head.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = point
			best_tangent = segment.normalized()
			best_segment_a = body[body_index]
			best_segment_b = body[neighbor]
	if best_tangent == Vector2.ZERO:
		var radial := head - body[body_index]
		var fallback := radial.normalized() if radial.length_squared() > 0.0001 else -direction
		return {
			"point": body[body_index],
			"normal": fallback,
			"segment_a": body[body_index],
			"segment_b": body[body_index],
		}
	var normal := best_tangent.orthogonal()
	var side := (head - best_point).dot(normal)
	if side < -0.0001 or (absf(side) <= 0.0001 and direction.dot(normal) > 0.0):
		normal = -normal
	return {
		"point": best_point,
		"normal": normal,
		"segment_a": best_segment_a,
		"segment_b": best_segment_b,
		"body_index": body_index,
	}


func arena_contact(position: Vector2) -> Dictionary:
	var center_bounds := ARENA.grow(-head_radius())
	var center_radius := maxf(0.0, ARENA_CORNER_RADIUS - head_radius())
	var core_start := center_bounds.position + Vector2.ONE * center_radius
	var core_end := center_bounds.end - Vector2.ONE * center_radius
	var core_point := position.clamp(core_start, core_end)
	var offset := position - core_point
	if offset.length() <= center_radius + WALL_EPSILON:
		return {"outside": false}
	var point := core_point
	if center_radius > 0.0001:
		point += offset.normalized() * center_radius
	var correction := point - position
	if correction.length_squared() <= WALL_EPSILON * WALL_EPSILON:
		return {"outside": false}
	var normal := correction.normalized()
	var wall_point := point - normal * head_radius()
	var segment := arena_debug_segment(normal, wall_point)
	return {
		"outside": true,
		"point": point,
		"wall_point": wall_point,
		"normal": normal,
		"segment_a": segment.a,
		"segment_b": segment.b,
	}


func arena_debug_segment(normal: Vector2, wall_point: Vector2) -> Dictionary:
	var radius := float(ARENA_CORNER_RADIUS)
	if normal.x > 0.999:
		return {
			"a": Vector2(ARENA.position.x, ARENA.position.y + radius),
			"b": Vector2(ARENA.position.x, ARENA.end.y - radius),
		}
	if normal.x < -0.999:
		return {
			"a": Vector2(ARENA.end.x, ARENA.position.y + radius),
			"b": Vector2(ARENA.end.x, ARENA.end.y - radius),
		}
	if normal.y > 0.999:
		return {
			"a": Vector2(ARENA.position.x + radius, ARENA.position.y),
			"b": Vector2(ARENA.end.x - radius, ARENA.position.y),
		}
	if normal.y < -0.999:
		return {
			"a": Vector2(ARENA.position.x + radius, ARENA.end.y),
			"b": Vector2(ARENA.end.x - radius, ARENA.end.y),
		}
	var tangent := normal.orthogonal()
	return {
		"a": wall_point - tangent * 24.0,
		"b": wall_point + tangent * 24.0,
	}


func report_contact(
	kind: String,
	segment_a: Vector2,
	segment_b: Vector2,
	point: Vector2,
	normal: Vector2,
	direction: Vector2,
	lethal: bool,
	body_index: int
) -> void:
	var incoming_cos := clampf(-direction.normalized().dot(normal.normalized()), -1.0, 1.0)
	(
		contact_evaluated
		. emit(
			{
				"kind": kind,
				"segment_a": segment_a,
				"segment_b": segment_b,
				"point": point,
				"normal": normal,
				"direction": direction.normalized(),
				"angle": rad_to_deg(acos(incoming_cos)),
				"lethal": lethal,
				"body_index": body_index,
			}
		)
	)


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
		rainbow_left = RAINBOW_DURATION
		rainbow_tick = 0.0
	elif kind == Apple.GREEN:
		points = 2
	score += points
	rebuild_body()
	apple_eaten.emit(kind, position, points)


func random_kind() -> int:
	var roll := rng.randf()
	if roll < 0.10:
		return Apple.RAINBOW
	var gold_cutoff := 0.40 if difficulty == Difficulty.HARD else 0.28
	if roll < gold_cutoff:
		return Apple.GOLD
	return Apple.RED if roll < (1.0 + gold_cutoff) / 2.0 else Apple.GREEN


func empty_position(clearance: float) -> Vector2:
	# Bounded search: crowded boards defer spawning instead of hanging.
	var bounds := ARENA.grow(-clearance - 12.0)
	for attempt in range(180):
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not arena_contains_circle(candidate, clearance + 12.0):
			continue
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


static func arena_contains_circle(position: Vector2, circle_radius: float) -> bool:
	var center_bounds := ARENA.grow(-circle_radius)
	if not center_bounds.has_point(position):
		return false
	var center_radius := maxf(0.0, ARENA_CORNER_RADIUS - circle_radius)
	if center_radius <= 0.0001:
		return true
	var core_start := center_bounds.position + Vector2.ONE * center_radius
	var core_end := center_bounds.end - Vector2.ONE * center_radius
	var core_point := position.clamp(core_start, core_end)
	return position.distance_squared_to(core_point) <= center_radius * center_radius


func spawn_apple(kind: int = -1) -> bool:
	var position := empty_position(APPLE_RADIUS)
	if position == Vector2.INF:
		return false
	apples.append({"position": position, "kind": random_kind() if kind < 0 else kind})
	return true


func spawn_bomb() -> bool:
	var fallback := Vector2.INF
	var fallback_distance := -1.0
	var head_clearance := speed() * BOMB_SPAWN_REACTION_TIME + head_radius() + BOMB_RADIUS
	for attempt in range(64):
		var candidate := empty_position(BOMB_RADIUS)
		if candidate == Vector2.INF:
			break
		# Include the warning/explosion outline, not just the bomb's physical body.
		if not arena_contains_circle(candidate, BLAST_RADIUS + 2.0):
			continue
		if candidate.distance_to(head) <= head_clearance:
			continue
		var nearest_bomb := INF
		for bomb in bombs:
			nearest_bomb = minf(nearest_bomb, candidate.distance_to(bomb["position"]))
		if nearest_bomb >= BLAST_RADIUS * 2.0 + 8.0:
			bombs.append({"position": candidate, "left": BOMB_FUSE})
			return true
		if nearest_bomb > fallback_distance:
			fallback = candidate
			fallback_distance = nearest_bomb
	if fallback == Vector2.INF:
		return false
	bombs.append({"position": fallback, "left": BOMB_FUSE})
	return true


func kill(reason: String) -> void:
	if not alive:
		return
	alive = false
	died.emit(reason)
