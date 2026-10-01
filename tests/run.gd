extends SceneTree
## Run with: godot --headless --path . --script tests/run.gd

const Model = preload("res://scripts/snake_model.gd")
const Game = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func fresh() -> SnakeModel:
	var model := Model.new()
	model.reset(42)
	return model


func no_food(model: SnakeModel) -> void:
	model.apples.clear()
	for i in range(Model.BASE_APPLES):
		model.apples.append(
			{"position": Vector2(-10000 - i * 100, -10000), "kind": Model.Apple.RED}
		)


func run() -> void:
	test_growth()
	test_steering_and_collection()
	test_contacts()
	test_effects()
	test_bombs()
	test_apple_probabilities()
	test_spawning()
	await test_menu()
	print("SmoothSnake: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_growth() -> void:
	var model := fresh()
	check(model.body.size() == 2, "Start with exactly two body balls")
	for points in range(1, 6):
		model.award_apple(Model.Apple.RED, model.head)
		check(model.body.size() == 2 + points, "One new body ball per point through five")
	var last_length := Model.length_at(0)
	var last_radius := Model.radius_at(0)
	var last_increment := INF
	for points in range(1, 10001):
		var length_value := Model.length_at(points)
		var radius_value := Model.radius_at(points)
		check(length_value > last_length, "Length strictly grows at %d" % points)
		check(radius_value > last_radius, "Width strictly grows at %d" % points)
		if points > 6:
			check(
				length_value - last_length <= last_increment + 0.00001, "Length growth decelerates"
			)
		last_increment = length_value - last_length
		last_length = length_value
		last_radius = radius_value
	check(Model.radius_at(15) / Model.radius_at(5) > 1.15, "Ten points noticeably increase width")
	check(Model.length_at(15) / Model.length_at(5) > 1.6, "Ten points noticeably increase length")


func test_steering_and_collection() -> void:
	var model := fresh()
	no_food(model)
	var start := model.head
	for i in range(120):
		model.step(1.0 / 120.0, 0)
	check(absf(start.distance_to(model.head) - 156.0) < 0.02, "Continuous movement uses seconds")
	model = fresh()
	no_food(model)
	var heading := model.heading
	model.step(0.1, 1)
	check(
		absf(model.heading - heading - Model.TURN_RATE * 0.1) < 0.0001,
		"Right steering rotates clockwise"
	)
	model.step(0.1, -1)
	check(absf(model.heading - heading) < 0.0001, "Left steering reverses rotation")
	model = fresh()
	model.apples = [{"position": model.head, "kind": Model.Apple.RED}]
	model.step(1.0 / 120.0, 0)
	check(model.score == 1 and model.body.size() == 3, "Real apple contact awards score and grows")
	check(model.apples.size() > 0, "Collected apples are replenished")
	model = fresh()
	model.apples = [{"position": model.head, "kind": Model.Apple.GREEN}]
	model.step(1.0 / 120.0, 0)
	check(model.score == 2 and model.body.size() == 4, "Green apple awards two points and grows")
	check(
		model.gold_left == 0.0 and model.rainbow_left == 0.0,
		"Green apple does not grant a timed power-up",
	)


func test_contacts() -> void:
	check(Model.lethal_contact(Vector2.RIGHT, Vector2.LEFT), "Head-on contact is lethal")
	check(
		Model.lethal_contact(Vector2.from_angle(deg_to_rad(44)), Vector2.LEFT),
		"Under 45 degrees is lethal",
	)
	check(
		not Model.lethal_contact(Vector2.from_angle(deg_to_rad(45)), Vector2.LEFT),
		"Exactly 45 degrees slides",
	)
	check(
		not Model.lethal_contact(Vector2.from_angle(deg_to_rad(46)), Vector2.LEFT),
		"Over 45 degrees slides",
	)
	check(not Model.lethal_contact(Vector2.LEFT, Vector2.LEFT), "Moving away is not lethal")
	var model := fresh()
	var reports: Array[Dictionary] = []
	model.contact_evaluated.connect(func(info: Dictionary): reports.append(info))
	model.head = Vector2(Model.ARENA.end.x, 400)
	model.resolve_walls(Vector2.RIGHT)
	check(not model.alive, "Wall collision kills")
	check(
		(
			reports.size() == 1
			and reports[0].kind == "wall"
			and reports[0].lethal
			and is_zero_approx(reports[0].angle)
		),
		"Collision report contains the segment, vectors, angle, and result",
	)
	model = fresh()
	model.head = Vector2(Model.ARENA.end.x, 400)
	model.heading = deg_to_rad(45)
	model.resolve_walls(Vector2.from_angle(model.heading))
	check(model.alive, "A 45-degree wall collision survives")
	check(
		is_equal_approx(model.head.x, Model.ARENA.end.x - model.head_radius()),
		"Wall slide stays inside"
	)
	check(absf(cos(model.heading)) < 0.0001, "Wall slide follows tangent")
	model = fresh()
	model.head = Vector2(500, 500)
	model.body = [
		Vector2(500, 560),
		Vector2(520, 530),
		Vector2(520, 500),
		Vector2(520, 470),
	]
	reports.clear()
	model.contact_evaluated.connect(func(info: Dictionary): reports.append(info))
	model.resolve_body(Vector2.RIGHT)
	check(not model.alive, "Head-on self collision kills")
	check(
		(
			reports.size() == 1
			and reports[0].kind == "body"
			and reports[0].segment_a == model.body[2]
			and reports[0].segment_b == model.body[1]
		),
		"Self collision reports the selected adjacent body segment",
	)
	model = fresh()
	model.head = Vector2(500, 500)
	model.body = [
		Vector2(500, 560),
		Vector2(520, 530),
		Vector2(520, 500),
		Vector2(520, 470),
	]
	model.heading = deg_to_rad(45)
	model.resolve_body(Vector2.from_angle(model.heading))
	check(model.alive, "A 45-degree self collision survives")
	check(absf(cos(model.heading)) < 0.0001, "Body slide follows the local tangent")
	model = fresh()
	model.head = Vector2(500, 510)
	model.body = [
		Vector2(480, 540),
		Vector2(520, 540),
		Vector2(520, 500),
		Vector2(560, 500),
	]
	var contact := model.body_segment_contact(2, Vector2.RIGHT)
	check(contact.normal.is_equal_approx(Vector2.LEFT), "Nearest previous segment supplies normal")
	check(
		contact.segment_a == model.body[2] and contact.segment_b == model.body[1],
		"Previous body segment is reported for debugging",
	)
	model.head = Vector2(530, 480)
	contact = model.body_segment_contact(2, Vector2.DOWN)
	check(contact.normal.is_equal_approx(Vector2.UP), "Nearest next segment supplies normal")
	check(
		contact.segment_a == model.body[2] and contact.segment_b == model.body[3],
		"Next body segment is reported for debugging",
	)
	model.head = Vector2(Model.ARENA.end.x, 400)
	var wall := model.arena_contact(model.head)
	check(wall.outside, "Head center beyond its inset reaches the visible wall")
	check(
		is_equal_approx(wall.wall_point.x, Model.ARENA.end.x),
		"Resolved head edge touches the visible wall exactly",
	)
	check(
		(
			(
				wall.segment_a
				== Vector2(Model.ARENA.end.x, Model.ARENA.position.y + Model.ARENA_CORNER_RADIUS)
			)
			and (
				wall.segment_b
				== Vector2(Model.ARENA.end.x, Model.ARENA.end.y - Model.ARENA_CORNER_RADIUS)
			)
		),
		"Wall collision reports the visible straight border",
	)
	var corner_center := Vector2(
		Model.ARENA.end.x - Model.ARENA_CORNER_RADIUS,
		Model.ARENA.position.y + Model.ARENA_CORNER_RADIUS,
	)
	var corner_direction := Vector2(1, -1).normalized()
	var center_radius := Model.ARENA_CORNER_RADIUS - model.head_radius()
	model.head = corner_center + corner_direction * (center_radius + 2.0)
	var corner := model.arena_contact(model.head)
	check(corner.outside, "Rounded corner excludes head centers outside its arc")
	check(
		is_equal_approx(
			corner.wall_point.distance_to(corner_center),
			float(Model.ARENA_CORNER_RADIUS),
		),
		"Rounded corner contact lies on the visible border",
	)
	check(
		absf((corner.segment_b - corner.segment_a).normalized().dot(corner.normal)) < 0.0001,
		"Rounded corner debug segment is tangent to the collision normal",
	)
	model = fresh()
	no_food(model)
	model.gold_left = 10
	model.head = Vector2(Model.ARENA.end.x - 25, 400)
	model.heading = 0
	model.step(0.25, 0)
	check(not model.alive, "Boosted movement cannot tunnel through walls")
	model = fresh()
	no_food(model)
	model.head = Vector2(
		Model.ARENA.end.x - model.head_radius(),
		Model.ARENA.position.y + Model.ARENA_CORNER_RADIUS + 20.0,
	)
	model.heading = PI / 2.0
	for tick in range(3600):
		model.bombs.clear()
		model.step(1.0 / 120.0, 0)
	check(model.alive, "A parallel wall follower survives for more than one full lap")
	check(
		not model.arena_contact(model.head).outside,
		"Wall follower remains inside the visible border"
	)


func test_effects() -> void:
	var model := fresh()
	model.award_apple(Model.Apple.GOLD, model.head)
	check(model.score == 5 and model.gold_left == 10, "Gold grants five points and ten seconds")
	var boosted := model.speed()
	model.gold_left = 0
	check(
		is_equal_approx(boosted, model.speed() * Model.GOLD_SPEED_MULTIPLIER),
		"Gold applies the configured 1.5 speed multiplier",
	)
	model.gold_left = 0.1
	no_food(model)
	model.step(0.11, 0)
	check(model.gold_left == 0, "Gold expires")
	model = fresh()
	model.award_apple(Model.Apple.RAINBOW, model.head)
	check(
		model.score == 10 and model.rainbow_left == Model.RAINBOW_DURATION,
		"Rainbow grants ten points and ten seconds",
	)
	# Keep the short snake moving safely in a circle while observing timer behavior.
	model.score = 0
	model.rebuild_body()
	no_food(model)
	var starting_count := model.apples.size()
	for tick in range(1200):
		model.bombs.clear()
		model.step(1.0 / 120.0, 1)
	check(model.alive, "Timer fixture survives ten seconds")
	check(
		model.apples.size() == starting_count + 10,
		"Rainbow spawns ten extras beyond the five-apple baseline",
	)
	for i in range(starting_count, model.apples.size()):
		check(
			model.apples[i]["kind"] in [Model.Apple.RED, Model.Apple.GREEN],
			"Apple rain only drops red and green apples",
		)
	check(model.rainbow_left < 0.00001, "Rainbow expires after ten seconds")
	model.award_apple(Model.Apple.RAINBOW, model.head)
	check(
		model.rainbow_left == Model.RAINBOW_DURATION and model.rainbow_tick == 0,
		"Repeated rainbow refreshes duration",
	)
	model.award_apple(Model.Apple.GOLD, model.head)
	model.gold_left = 2
	model.award_apple(Model.Apple.GOLD, model.head)
	check(model.gold_left == 10, "Repeated gold refreshes, without multiplying speed again")


func test_bombs() -> void:
	var model: SnakeModel
	for difficulty in range(Model.Difficulty.HARD + 1):
		model = fresh()
		no_food(model)
		model.set_difficulty(difficulty)
		var interval := float(Model.BOMB_INTERVALS[difficulty])
		check(is_equal_approx(model.bomb_interval(), interval), "Difficulty sets bomb cadence")
		model.bomb_tick = interval - 0.01
		model.step(0.011, 1)
		check(model.bombs.size() == 1, "Bomb spawns at the selected difficulty interval")
		check(
			is_equal_approx(model.bombs[0]["left"], Model.BOMB_FUSE),
			"New bombs have a full five-second fuse",
		)
	for boosted in [false, true]:
		model = fresh()
		no_food(model)
		model.gold_left = 10.0 if boosted else 0.0
		var required_clearance := (
			model.speed() * Model.BOMB_SPAWN_REACTION_TIME + model.head_radius() + Model.BOMB_RADIUS
		)
		var spawned := model.spawn_bomb()
		check(spawned, "Bomb placement succeeds outside the one-second reach")
		if spawned:
			check(
				model.bombs[0]["position"].distance_to(model.head) > required_clearance,
				"Bomb does not spawn within one second of head travel",
			)
	model = fresh()
	model.bomb_tick = 1.0
	model.set_difficulty(Model.Difficulty.HARD)
	check(model.bomb_tick == 0.0, "Changing difficulty resets the spawn timer")
	no_food(model)
	for i in range(4):
		check(model.spawn_bomb(), "Bomb placement succeeds on an open board")
	for i in range(model.bombs.size()):
		for j in range(i + 1, model.bombs.size()):
			check(
				(
					model.bombs[i]["position"].distance_to(model.bombs[j]["position"])
					>= Model.BLAST_RADIUS * 2.0 + 8.0
				),
				"Bomb blast areas do not overlap while space is available",
			)
	model = fresh()
	no_food(model)
	var detonations := [0]
	model.exploded.connect(func(_position: Vector2, _radius: float): detonations[0] += 1)
	model.bombs = [
		{
			"position":
			(
				model.head
				+ (
					Vector2.from_angle(model.heading)
					* (model.head_radius() + Model.BOMB_RADIUS + 1.0)
				)
			),
			"left": Model.BOMB_FUSE,
		}
	]
	model.step(0.02, 0)
	check(
		not model.alive and model.bombs.is_empty() and detonations[0] == 1,
		"Touching a bomb immediately detonates it",
	)
	model = fresh()
	model.bombs = [{"position": model.head, "left": 0.01}]
	model.step(0.02, 0)
	check(
		not model.alive and model.bombs.is_empty(),
		"Blast kills head inside radius and removes bomb"
	)
	model = fresh()
	model.bombs = [{"position": model.head + Vector2(Model.BLAST_RADIUS, 0), "left": 0.01}]
	model.step(0.02, 0)
	check(not model.alive, "Blast radius boundary is included")
	model = fresh()
	model.bombs = [{"position": model.head + Vector2(Model.BLAST_RADIUS + 1, 0), "left": 0.01}]
	model.step(0.02, 0)
	check(model.alive and model.bombs.is_empty(), "Head outside blast survives")


func test_spawning() -> void:
	var model := fresh()
	for seed_value in range(30):
		model.reset(seed_value)
		model.gold_left = 10.0 if seed_value % 2 else 0.0
		for i in range(4):
			check(model.spawn_bomb(), "Room for four bombs with the whole blast inside the arena")
		for bomb in model.bombs:
			check(
				Model.arena_contains_circle(bomb.position, Model.BLAST_RADIUS + 2.0),
				"Blast circle and stroke remain inside the visible arena",
			)
			check(
				(
					bomb.position.distance_to(model.head)
					> model.speed() + model.head_radius() + Model.BOMB_RADIUS
				),
				"Edge-safe placement still respects the one-second exclusion",
			)
	model = fresh()
	check(
		not Model.arena_contains_circle(Model.ARENA.position + Vector2(13, 13), 13),
		"Rounded corner rejects a circle inside only the rectangular bounds",
	)
	check(
		Model.arena_contains_circle(
			Model.ARENA.position + Vector2(Model.ARENA_CORNER_RADIUS, 13), 13
		),
		"Circle tangent to a straight wall remains valid near a corner",
	)
	for i in range(80):
		var position := model.empty_position(Model.APPLE_RADIUS)
		check(
			Model.arena_contains_circle(position, Model.APPLE_RADIUS + 12),
			"Spawn remains inside the rounded arena",
		)
		check(
			position.distance_to(model.head) >= model.head_radius() + Model.APPLE_RADIUS + 100,
			"Spawn keeps distance from head"
		)
		for ball in model.body:
			check(
				position.distance_to(ball) > model.radius() + Model.APPLE_RADIUS,
				"Spawn never overlaps body"
			)
	model.apples.clear()
	for x in range(65, 1380, 24):
		for y in range(145, 774, 24):
			model.apples.append({"position": Vector2(x, y), "kind": Model.Apple.RED})
	check(not model.spawn_apple(), "Full board defers spawning without looping forever")


func test_apple_probabilities() -> void:
	var model := fresh()
	for difficulty in range(3):
		model.set_difficulty(difficulty)
		model.rng.seed = 2026
		var counts := [0, 0, 0, 0]
		for i in range(20000):
			counts[model.random_kind()] += 1
		var expected := (
			[0.30, 0.30, 0.10, 0.30]
			if difficulty == Model.Difficulty.HARD
			else [0.36, 0.18, 0.10, 0.36]
		)
		for kind in range(4):
			check(
				absf(float(counts[kind]) / 20000.0 - expected[kind]) < 0.015,
				"All four apple probabilities match the difficulty distribution",
			)
	model.set_difficulty(Model.Difficulty.MEDIUM)
	var medium_gold := 0
	var medium_rainbow := 0
	model.rng.seed = 7319
	for i in range(10000):
		var kind := model.random_kind()
		medium_gold += int(kind == Model.Apple.GOLD)
		medium_rainbow += int(kind == Model.Apple.RAINBOW)
	model.set_difficulty(Model.Difficulty.HARD)
	model.rng.seed = 7319
	var hard_gold := 0
	var hard_rainbow := 0
	for i in range(10000):
		var kind := model.random_kind()
		hard_gold += int(kind == Model.Apple.GOLD)
		hard_rainbow += int(kind == Model.Apple.RAINBOW)
	check(hard_gold > medium_gold, "Hard mode raises the gold apple probability")
	check(hard_rainbow == medium_rainbow, "Difficulty does not alter rainbow probability")


func test_menu() -> void:
	var game := Game.instantiate()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	check(game.state == game.State.READY, "Game starts on ready screen")
	check(game.difficulty_buttons.size() == 3, "Menu shows three direct difficulty buttons")
	game.difficulty_buttons[Model.Difficulty.HARD].pressed.emit()
	check(
		game.model.difficulty == Model.Difficulty.HARD and game.state == game.State.PLAYING,
		"Difficulty button immediately starts a new run",
	)
	game.sound_enabled = true
	game.update_sound_button()
	game.model.award_apple(Model.Apple.GREEN, game.model.head)
	check(
		game.pickup_audio.stream == game.PICKUP_SOUNDS[Model.Apple.GREEN],
		"Green pickup uses its own cheerful phrase",
	)
	game.model.award_apple(Model.Apple.GOLD, game.model.head)
	game.toggle_pause()
	check(game.pickup_audio.stream_paused, "Pause freezes active sound effects")
	var old_head: Vector2 = game.model.head
	var old_time: float = game.model.gold_left
	await physics_frame
	await physics_frame
	check(
		game.model.head == old_head and game.model.gold_left == old_time,
		"Pause freezes movement and effect timers"
	)
	game.toggle_pause()
	check(game.state == game.State.PLAYING, "Resume restores play")
	check(not game.pickup_audio.stream_paused, "Resume releases paused sound effects")
	game.sound_enabled = false
	game.update_sound_button()
	check(
		not game.pickup_audio.playing and not game.audio.playing,
		"Sound off silences all effects immediately",
	)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == game.State.PAUSED, "Losing focus pauses")
	game.difficulty_buttons[Model.Difficulty.EASY].pressed.emit()
	check(
		(
			game.state == game.State.PLAYING
			and game.model.difficulty == Model.Difficulty.EASY
			and game.model.score == 0
			and game.model.gold_left == 0
			and game.model.bombs.is_empty()
		),
		"Choosing a difficulty while paused restarts with a clean run",
	)
	game.model.kill("Test collision")
	check(game.state == game.State.OVER, "Death opens replay screen")
	game.start_run()
	game.model.bombs.clear()
	game.model.bombs.append({"position": game.model.head, "left": Model.BOMB_FUSE})
	game.model.detonate_bomb(0)
	check(
		game.state == game.State.DYING and not game.menu.visible,
		"Blast death keeps the result menu hidden during the explosion",
	)
	check(
		game.blasts.size() == 1 and game.effects.size() >= 28,
		"Blast death starts the shockwave and debris animation",
	)
	await create_timer(game.BLAST_DEATH_DELAY * 0.55).timeout
	check(game.state == game.State.DYING, "Blast death remains visible midway through")
	await create_timer(game.BLAST_DEATH_DELAY * 0.60).timeout
	check(game.state == game.State.OVER and game.menu.visible, "Replay screen follows the blast")
	game.queue_free()
	await process_frame
	# Give the audio mixer time to release queued playbacks before quitting the test runner.
	await create_timer(0.12).timeout
