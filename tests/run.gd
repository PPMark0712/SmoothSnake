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


func test_contacts() -> void:
	check(Model.lethal_contact(Vector2.RIGHT, Vector2.LEFT), "Head-on contact is lethal")
	check(Model.lethal_contact(Vector2(1, 1), Vector2.LEFT), "Exactly 45 degrees is lethal")
	check(not Model.lethal_contact(Vector2(1, 1.01), Vector2.LEFT), "Over 45 degrees slides")
	check(not Model.lethal_contact(Vector2.LEFT, Vector2.LEFT), "Moving away is not lethal")
	var model := fresh()
	model.head = Vector2(Model.ARENA.end.x, 400)
	model.resolve_walls(Vector2.RIGHT)
	check(not model.alive, "Wall collision kills")
	model = fresh()
	model.head = Vector2(Model.ARENA.end.x, 400)
	model.heading = deg_to_rad(65)
	model.resolve_walls(Vector2.from_angle(model.heading))
	check(model.alive, "Glancing wall collision survives")
	check(
		is_equal_approx(model.head.x, Model.ARENA.end.x - model.head_radius()),
		"Wall slide stays inside"
	)
	check(absf(cos(model.heading)) < 0.0001, "Wall slide follows tangent")
	model = fresh()
	model.body = [Vector2(0, 0), Vector2(0, 0), model.head + Vector2(20, 0)]
	model.resolve_body(Vector2.RIGHT)
	check(not model.alive, "Head-on self collision kills")
	model = fresh()
	model.body = [Vector2(0, 0), Vector2(0, 0), model.head + Vector2(20, 0)]
	model.heading = deg_to_rad(75)
	model.resolve_body(Vector2.from_angle(model.heading))
	check(model.alive, "Glancing self collision survives")
	model = fresh()
	no_food(model)
	model.gold_left = 10
	model.head = Vector2(Model.ARENA.end.x - 25, 400)
	model.heading = 0
	model.step(0.25, 0)
	check(not model.alive, "Boosted movement cannot tunnel through walls")


func test_effects() -> void:
	var model := fresh()
	model.award_apple(Model.Apple.GOLD, model.head)
	check(model.score == 5 and model.gold_left == 10, "Gold grants five points and ten seconds")
	var boosted := model.speed()
	model.gold_left = 0
	check(is_equal_approx(boosted, model.speed() * 2), "Gold exactly doubles current speed")
	model.gold_left = 0.1
	no_food(model)
	model.step(0.11, 0)
	check(model.gold_left == 0, "Gold expires")
	model = fresh()
	model.award_apple(Model.Apple.RAINBOW, model.head)
	check(
		model.score == 10 and model.rainbow_left == 20,
		"Rainbow grants ten points and twenty seconds"
	)
	# Keep the short snake moving safely in a circle while observing timer behavior.
	model.score = 0
	model.rebuild_body()
	no_food(model)
	var starting_count := model.apples.size()
	for tick in range(2400):
		model.bombs.clear()
		model.step(1.0 / 120.0, 1)
	check(model.alive, "Timer fixture survives twenty seconds")
	check(
		model.apples.size() == starting_count + 10,
		"Rainbow spawns ten extras, every two seconds including expiry"
	)
	check(model.rainbow_left < 0.00001, "Rainbow expires after twenty seconds")
	model.award_apple(Model.Apple.RAINBOW, model.head)
	check(
		model.rainbow_left == 20 and model.rainbow_tick == 0, "Repeated rainbow refreshes duration"
	)
	model.award_apple(Model.Apple.GOLD, model.head)
	model.gold_left = 2
	model.award_apple(Model.Apple.GOLD, model.head)
	check(model.gold_left == 10, "Repeated gold refreshes, without multiplying speed again")


func test_bombs() -> void:
	var model := fresh()
	no_food(model)
	for i in range(1200):
		model.step(1.0 / 120.0, 1)
	check(model.bombs.size() == 1, "First bomb spawns at ten seconds")
	check(is_equal_approx(model.bombs[0]["left"], 5.0), "New bombs have a full five-second fuse")
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
	for i in range(80):
		var position := model.empty_position(Model.APPLE_RADIUS)
		check(
			Model.ARENA.grow(-Model.APPLE_RADIUS).has_point(position), "Spawn remains inside bounds"
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


func test_menu() -> void:
	var game := Game.instantiate()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	check(game.state == game.State.READY, "Game starts on ready screen")
	game.start_run()
	game.model.award_apple(Model.Apple.GOLD, game.model.head)
	game.toggle_pause()
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
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == game.State.PAUSED, "Losing focus pauses")
	game.start_run()
	check(
		game.model.score == 0 and game.model.gold_left == 0 and game.model.bombs.is_empty(),
		"Restart clears run state"
	)
	game.model.kill("Test collision")
	check(game.state == game.State.OVER, "Death opens replay screen")
	game.queue_free()
	await process_frame
