# gdlint: disable=max-public-methods
extends Node2D
## Presentation only: the simulation is independently runnable in headless tests.

enum State { READY, PLAYING, PAUSED, OVER, DYING }

const Model = preload("res://scripts/snake_model.gd")
const StaticBackdrop = preload("res://scripts/static_backdrop.gd")
const AppleAtlas = preload("res://scripts/apple_atlas.gd")
const PICKUP_SOUNDS = [
	preload("res://assets/audio/pickup_red.wav"),
	preload("res://assets/audio/pickup_gold.wav"),
	preload("res://assets/audio/pickup_rainbow.wav"),
	preload("res://assets/audio/pickup_green.wav"),
]
const APPLE_COLORS = [
	Color("#df6e55"),
	Color("#e6b947"),
	Color("#b093ce"),
	Color("#6db84f"),
]
const INK := Color("#354737")
const MUTED := Color("#859077")
const GREEN := Color("#577d46")
const PAPER := Color("#f8f4df")
const DEBUG_LINE := Color("#1596a6")
const DEBUG_WALL := Color("#d28a32")
const DEBUG_SAFE := Color("#3fa66b")
const DEBUG_LETHAL := Color("#dc4c45")
const BLAST_ANIMATION_DURATION := 0.85
const BLAST_DEATH_DELAY := 0.85
const SKINS := [
	{
		"name": "Forest",
		"body": Color("#77a64f"),
		"tail": Color("#b7cf67"),
		"head": Color("#659443"),
		"accent": Color("#294f35"),
		"cheek": Color("#ef9d7d"),
		"pattern": 0,
	},
	{
		"name": "Coral",
		"body": Color("#d9574f"),
		"tail": Color("#f28a64"),
		"head": Color("#c94345"),
		"accent": Color("#7d2638"),
		"cheek": Color("#ffd0a8"),
		"pattern": 1,
	},
	{
		"name": "Ocean",
		"body": Color("#238da3"),
		"tail": Color("#55c2b2"),
		"head": Color("#176d8a"),
		"accent": Color("#123f68"),
		"cheek": Color("#f2a58f"),
		"pattern": 2,
	},
	{
		"name": "Midnight",
		"body": Color("#414657"),
		"tail": Color("#687186"),
		"head": Color("#292f42"),
		"accent": Color("#8be0c5"),
		"cheek": Color("#e99ca5"),
		"pattern": 3,
	},
	{
		"name": "Honey",
		"body": Color("#d99b23"),
		"tail": Color("#f2c94c"),
		"head": Color("#b87318"),
		"accent": Color("#68431f"),
		"cheek": Color("#f28e72"),
		"pattern": 4,
	},
	{
		"name": "Berry",
		"body": Color("#9f4d91"),
		"tail": Color("#d06ca0"),
		"head": Color("#763d7d"),
		"accent": Color("#4b285f"),
		"cheek": Color("#f3a09a"),
		"pattern": 5,
	},
]

var model := Model.new()
var state := State.READY
var font: Font
var bold: Font
var best := 0
var last_best := 0
var visual_time := 0.0
var effects: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var death_reason := ""
var menu := Control.new()
var primary := Button.new()
var difficulty_buttons: Array[Button] = []
var skin_buttons: Array[Button] = []
var skin_index := 0
var pause_button := Button.new()
var sound_button := Button.new()
var sound_enabled := true
var audio := AudioStreamPlayer.new()
var pickup_audio := AudioStreamPlayer.new()
var board_dot_segments := PackedVector2Array()
var bomb_dash_segments := PackedVector2Array()
var rounded_style_cache: Dictionary = {}
var debug_mode := false
var debug_contact: Dictionary = {}
var debug_contact_left := 0.0
var eat_pulse := 0.0
var impact_flash := 0.0
var slide_fx_cooldown := 0.0
var blast_death_left := 0.0
var apple_atlas: Texture2D


func _ready() -> void:
	if OS.has_feature("web"):
		Engine.max_fps = 60
	font = ThemeDB.fallback_font
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_embolden = 0.7
	bold = variation
	var save := ConfigFile.new()
	if save.load("user://smoothsnake.cfg") == OK:
		best = int(save.get_value("game", "best", 0))
		sound_enabled = bool(save.get_value("game", "sound", true))
		model.set_difficulty(int(save.get_value("game", "difficulty", Model.Difficulty.MEDIUM)))
		skin_index = clampi(int(save.get_value("game", "skin", 0)), 0, SKINS.size() - 1)
	model.apple_eaten.connect(_on_apple)
	model.exploded.connect(_on_explosion)
	model.died.connect(_on_death)
	model.contact_evaluated.connect(_on_contact_evaluated)
	build_draw_batches()
	build_static_backdrop()
	build_apple_atlas()
	add_child(audio)
	add_child(pickup_audio)
	pickup_audio.volume_db = -9.0
	build_ui()
	model.reset()
	set_state(State.READY)
	get_viewport().size_changed.connect(layout_ui)
	layout_ui()


func build_static_backdrop() -> void:
	var static_viewport := SubViewport.new()
	static_viewport.name = "StaticBackdropViewport"
	static_viewport.size = Vector2i(1440, 900)
	static_viewport.disable_3d = true
	static_viewport.gui_disable_input = true
	static_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(static_viewport)

	var backdrop := StaticBackdrop.new()
	static_viewport.add_child(backdrop)
	backdrop.configure(font, bold, board_dot_segments)

	var sprite := Sprite2D.new()
	sprite.name = "StaticBackdrop"
	sprite.centered = false
	sprite.texture = static_viewport.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = -100
	add_child(sprite)
	static_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func build_apple_atlas() -> void:
	var atlas_viewport := SubViewport.new()
	atlas_viewport.name = "AppleAtlasViewport"
	atlas_viewport.size = Vector2i(AppleAtlas.CELL_SIZE * APPLE_COLORS.size(), AppleAtlas.CELL_SIZE)
	atlas_viewport.transparent_bg = true
	atlas_viewport.disable_3d = true
	atlas_viewport.gui_disable_input = true
	atlas_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(atlas_viewport)
	atlas_viewport.add_child(AppleAtlas.new())
	apple_atlas = atlas_viewport.get_texture()
	atlas_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func build_draw_batches() -> void:
	for x in range(78, 1380, 26):
		for y in range(158, 774, 26):
			var center := Vector2(x, y)
			board_dot_segments.append(center - Vector2(0.15, 0))
			board_dot_segments.append(center + Vector2(0.15, 0))
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		bomb_dash_segments.append(Vector2.from_angle(angle) * Model.BLAST_RADIUS)
		bomb_dash_segments.append(Vector2.from_angle(angle + 0.10) * Model.BLAST_RADIUS)


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(menu)
	menu.add_child(primary)
	layer.add_child(pause_button)
	layer.add_child(sound_button)
	style_button(primary, true)
	style_button(pause_button, false)
	style_button(sound_button, false)
	primary.pressed.connect(
		func():
			if state == State.PAUSED:
				set_state(State.PLAYING)
			else:
				start_run()
	)
	for difficulty in range(Model.Difficulty.HARD + 1):
		var button := Button.new()
		button.text = ["Easy", "Medium", "Hard"][difficulty]
		button.pressed.connect(start_difficulty.bind(difficulty))
		menu.add_child(button)
		difficulty_buttons.append(button)
	update_difficulty_buttons()
	for index in range(SKINS.size()):
		var button := Button.new()
		button.tooltip_text = SKINS[index]["name"]
		button.pressed.connect(set_skin.bind(index))
		menu.add_child(button)
		skin_buttons.append(button)
	update_skin_buttons()
	pause_button.text = "II   Pause"
	pause_button.pressed.connect(toggle_pause)
	sound_button.pressed.connect(
		func():
			sound_enabled = not sound_enabled
			update_sound_button()
			save_settings()
	)
	update_sound_button()


func style_button(button: Button, filled: bool) -> void:
	button.add_theme_font_override("font", bold)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", PAPER if filled else INK)
	button.add_theme_color_override("font_hover_color", PAPER if filled else INK)
	button.add_theme_color_override("font_pressed_color", PAPER if filled else INK)
	for button_state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = GREEN if filled else Color("#eeeacf")
		if button_state == "hover":
			style.bg_color = Color("#466a37") if filled else Color("#e2dfc3")
		if button_state == "pressed":
			style.bg_color = Color("#3e5f31") if filled else Color("#d7d6b7")
		style.set_corner_radius_all(12)
		if button_state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color = Color("#b3a24e")
		button.add_theme_stylebox_override(button_state, style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func layout_ui() -> void:
	# The viewport stretches the complete 1440 × 900 canvas with its controls.
	primary.size = Vector2(400, 52)
	for i in range(difficulty_buttons.size()):
		difficulty_buttons[i].position = Vector2(568 + i * 104, 486)
		difficulty_buttons[i].size = Vector2(96, 36)
		difficulty_buttons[i].add_theme_font_size_override("font_size", 14)
	for i in range(skin_buttons.size()):
		skin_buttons[i].position = Vector2(574 + i * 50, 536)
		skin_buttons[i].size = Vector2(42, 34)
	primary.position = Vector2(520, 580)
	pause_button.position = Vector2(1260, 47)
	pause_button.size = Vector2(132, 48)
	sound_button.position = Vector2(48, 851)
	sound_button.size = Vector2(116, 28)
	sound_button.add_theme_font_size_override("font_size", 12)


func set_state(value: State) -> void:
	state = value
	menu.visible = state in [State.READY, State.PAUSED, State.OVER]
	pause_button.visible = state == State.PLAYING
	primary.text = (
		"Let's play"
		if state == State.READY
		else ("Resume" if state == State.PAUSED else "Play again")
	)
	update_difficulty_buttons()
	if menu.visible:
		primary.grab_focus()
	else:
		primary.release_focus()
	update_audio()
	sync_web_status()
	queue_redraw()


func start_difficulty(difficulty: int) -> void:
	model.set_difficulty(difficulty)
	update_difficulty_buttons()
	save_settings()
	start_run()


func update_difficulty_buttons() -> void:
	for i in range(difficulty_buttons.size()):
		style_button(difficulty_buttons[i], i == model.difficulty)


func set_skin(index: int) -> void:
	skin_index = clampi(index, 0, SKINS.size() - 1)
	update_skin_buttons()
	save_settings()
	queue_redraw()


func update_skin_buttons() -> void:
	for i in range(skin_buttons.size()):
		var button := skin_buttons[i]
		var skin: Dictionary = SKINS[i]
		button.add_theme_color_override("font_color", Color.TRANSPARENT)
		for button_state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = skin["body"].lightened(0.10 if button_state == "hover" else 0.0)
			style.set_corner_radius_all(8)
			style.set_border_width_all(3 if i == skin_index else 1)
			style.border_color = INK if i == skin_index else Color("#fffdf0")
			button.add_theme_stylebox_override(button_state, style)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func sync_web_status() -> void:
	if not OS.has_feature("web"):
		return
	# Publish the visible state on the canvas for accessibility and browser checks.
	var status_name: String = ["ready", "playing", "paused", "over", "dying"][state]
	var label := (
		"SmoothSnake. %s. Score %d. Arrow keys steer; Escape pauses." % [status_name, model.score]
	)
	JavaScriptBridge.eval(
		(
			"(() => { const c = document.getElementById('canvas'); if (c) {"
			+ (
				"c.dataset.state = %s; c.dataset.score = '%d';"
				% [JSON.stringify(status_name), model.score]
			)
			+ "c.setAttribute('aria-label', %s); } })();" % JSON.stringify(label)
		)
	)


func start_run() -> void:
	last_best = best
	model.reset()
	effects.clear()
	popups.clear()
	blasts.clear()
	death_reason = ""
	debug_contact.clear()
	debug_contact_left = 0.0
	eat_pulse = 0.0
	impact_flash = 0.0
	slide_fx_cooldown = 0.0
	blast_death_left = 0.0
	set_state(State.PLAYING)


func toggle_pause() -> void:
	if state == State.PLAYING:
		set_state(State.PAUSED)
	elif state == State.PAUSED:
		set_state(State.PLAYING)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		set_state(State.PAUSED)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_D:
		debug_mode = not debug_mode
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and state in [State.PAUSED, State.OVER]:
		start_run()
	elif event.keycode == KEY_ENTER and state == State.READY:
		start_run()


func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		var left := Input.is_physical_key_pressed(KEY_LEFT)
		var right := Input.is_physical_key_pressed(KEY_RIGHT)
		model.step(delta, float(right) - float(left))


func _process(delta: float) -> void:
	if state != State.PAUSED:
		visual_time += delta
		eat_pulse = maxf(0.0, eat_pulse - delta)
		impact_flash = maxf(0.0, impact_flash - delta)
		slide_fx_cooldown = maxf(0.0, slide_fx_cooldown - delta)
		for i in range(effects.size() - 1, -1, -1):
			effects[i]["life"] -= delta
			effects[i]["position"] += effects[i]["velocity"] * delta
			effects[i]["velocity"] *= exp(-delta * 3.0)
			if effects[i]["life"] <= 0.0:
				effects.remove_at(i)
		for i in range(popups.size() - 1, -1, -1):
			popups[i]["life"] -= delta
			popups[i]["position"].y -= delta * 27.0
			if popups[i]["life"] <= 0.0:
				popups.remove_at(i)
		for i in range(blasts.size() - 1, -1, -1):
			blasts[i]["life"] -= delta
			if blasts[i]["life"] <= 0.0:
				blasts.remove_at(i)
	if state == State.DYING:
		blast_death_left -= delta
		if blast_death_left <= 0.0:
			set_state(State.OVER)
	if state == State.PLAYING and debug_contact_left > 0.0:
		debug_contact_left -= delta
		if debug_contact_left <= 0.0:
			debug_contact.clear()
	queue_redraw()


func _draw() -> void:
	if font == null:
		return
	draw_hud()
	for apple in model.apples:
		var p: Vector2 = apple["position"]
		var bob := sin(visual_time * 2.6 + p.x) * 2.0
		var proximity := clampf(1.0 - model.head.distance_to(p) / 100.0, 0.0, 1.0)
		var anticipation := 1.0 + proximity * (0.025 + 0.025 * sin(visual_time * 9.0))
		draw_apple(p + Vector2(0, bob), apple["kind"], anticipation)
	for bomb in model.bombs:
		draw_bomb(bomb)
	draw_snake()
	for blast in blasts:
		var progress: float = 1.0 - blast["life"] / BLAST_ANIMATION_DURATION
		var fade := 1.0 - progress
		var expansion := ease(progress, -2.0)
		draw_circle(
			blast["position"],
			blast["radius"] * (0.18 + expansion * 0.82),
			Color(0.94, 0.42, 0.18, sin(progress * PI) * 0.34),
		)
		draw_arc(
			blast["position"],
			blast["radius"] * (0.20 + expansion * 0.96),
			0,
			TAU,
			80,
			Color(0.91, 0.35, 0.18, fade),
			5.0 - progress * 2.0,
			true,
		)
		draw_circle(
			blast["position"],
			blast["radius"] * 0.22 * fade,
			Color(1.0, 0.86, 0.46, fade * 0.82),
		)
	for particle in effects:
		var color: Color = particle["color"]
		color.a = clampf(particle["life"] * 1.4, 0.0, 1.0)
		draw_circle(particle["position"], particle["size"], color)
	for popup in popups:
		var color: Color = popup["color"]
		color.a = minf(1.0, popup["life"] * 2.0)
		text_at(popup["text"], popup["position"], 25, color, bold)
	if impact_flash > 0.0:
		var impact_alpha := impact_flash / 0.45
		draw_circle(
			model.head,
			30.0 + (1.0 - impact_alpha) * 58.0,
			Color(0.86, 0.25, 0.19, 0.10 * impact_alpha),
		)
		draw_arc(
			model.head,
			34.0 + (1.0 - impact_alpha) * 70.0,
			0,
			TAU,
			64,
			Color(0.79, 0.24, 0.18, 0.65 * impact_alpha),
			3.0,
			true,
		)
	if menu.visible:
		draw_menu()
	if debug_mode:
		draw_debug_overlay()


func draw_hud() -> void:
	if model.gold_left > 0:
		status_pill(Vector2(638, 52), "1.5× SPEED", model.gold_left, 10.0, Color("#c49a39"))
	if model.rainbow_left > 0:
		status_pill(
			Vector2(818, 52),
			"APPLE RAIN",
			model.rainbow_left,
			Model.RAINBOW_DURATION,
			Color("#9b7cbd"),
		)
	text_at(str(best).pad_zeros(2), Vector2(1034, 91), 29, INK, bold)
	text_at(str(model.score).pad_zeros(2), Vector2(1150, 91), 29, INK, bold)


func status_pill(
	position: Vector2, title: String, remaining: float, duration: float, color: Color
) -> void:
	rounded_box(Rect2(position, Vector2(164, 49)), Color(color, 0.10), 10)
	text_at(title, position + Vector2(12, 19), 11, color, bold)
	text_at("%ds" % ceili(remaining), position + Vector2(124, 19), 12, INK, bold)
	rounded_box(Rect2(position + Vector2(12, 31), Vector2(140, 4)), Color(color, 0.18), 2)
	rounded_box(Rect2(position + Vector2(12, 31), Vector2(140 * remaining / duration, 4)), color, 2)


func draw_snake() -> void:
	var forward := Vector2.from_angle(model.heading)
	var skin: Dictionary = SKINS[skin_index]
	if model.gold_left > 0:
		for i in range(3, 0, -1):
			var wake_position := model.head - forward * (16.0 + i * 12.0)
			draw_circle(
				wake_position,
				model.head_radius() * (0.52 - i * 0.07),
				Color(0.86, 0.71, 0.30, 0.06 + i * 0.025),
			)
	for i in range(model.body.size() - 1, -1, -1):
		var t := float(i) / maxf(1.0, model.body.size() - 1.0)
		var body_color: Color = skin["body"].lerp(skin["tail"], t * 0.72)
		ball(model.body[i], model.radius(), body_color)
		draw_body_pattern(i, skin)
	if model.gold_left > 0:
		draw_arc(model.head, model.head_radius() + 6, 0, TAU, 48, Color("#dec270"), 2, true)
	var pulse_phase := 1.0 - eat_pulse / 0.28
	var visual_head_radius := model.head_radius()
	if eat_pulse > 0.0:
		visual_head_radius *= 1.0 + sin(pulse_phase * PI) * 0.09
	ball(model.head, visual_head_radius, skin["head"])
	var side := forward.orthogonal()
	for sign_value in [-1.0, 1.0]:
		var eye: Vector2 = (
			model.head
			+ forward * visual_head_radius * 0.40
			+ side * sign_value * visual_head_radius * 0.46
		)
		draw_circle(eye, visual_head_radius * 0.25, Color("#fffef1"))
		if state == State.OVER:
			var r := visual_head_radius * 0.10
			draw_line(eye - Vector2(r, r), eye + Vector2(r, r), INK, 1.7, true)
			draw_line(eye + Vector2(-r, r), eye + Vector2(r, -r), INK, 1.7, true)
		else:
			draw_circle(eye + forward * 1.1, visual_head_radius * 0.12, INK)
			draw_circle(eye + forward * 1.1 + Vector2(-0.5, -0.7), 0.65, Color.WHITE)
		var cheek: Vector2 = model.head + side * sign_value * visual_head_radius * 0.70
		draw_circle(cheek, visual_head_radius * 0.14, skin["cheek"])


func draw_body_pattern(index: int, skin: Dictionary) -> void:
	var position: Vector2 = model.body[index]
	var r := model.radius()
	var accent: Color = skin["accent"]
	accent.a = 0.62
	var pattern: int = skin["pattern"]
	if pattern == 0:
		if index % 2 == 1:
			draw_circle(position - Vector2(r * 0.22, r * 0.24), maxf(1.2, r * 0.11), accent)
	elif pattern == 1:
		draw_arc(position, r * 0.56, 0, TAU, 24, accent, maxf(1.3, r * 0.12), true)
	elif pattern == 2:
		if index % 2 == 0:
			var normal := body_axis(index).orthogonal()
			draw_line(
				position - normal * r * 0.70,
				position + normal * r * 0.70,
				accent,
				maxf(2.0, r * 0.22),
				true,
			)
	elif pattern == 3:
		draw_circle(position + Vector2(-r * 0.28, -r * 0.16), maxf(1.1, r * 0.10), accent)
		if index % 2 == 0:
			draw_circle(position + Vector2(r * 0.22, r * 0.27), maxf(0.9, r * 0.07), accent)
	elif pattern == 4:
		if index % 2 == 1:
			var normal := body_axis(index).orthogonal()
			draw_line(
				position - normal * r * 0.78,
				position + normal * r * 0.78,
				accent,
				maxf(3.0, r * 0.34),
				true,
			)
	elif pattern == 5:
		draw_arc(
			position + Vector2(0, r * 0.18),
			r * 0.43,
			PI,
			TAU,
			12,
			accent,
			maxf(1.3, r * 0.11),
			true,
		)


func body_axis(index: int) -> Vector2:
	var before := model.head if index == 0 else model.body[index - 1]
	var after := model.body[index + 1] if index + 1 < model.body.size() else model.body[index]
	var axis: Vector2 = before - after
	return axis.normalized() if axis.length_squared() > 0.0001 else Vector2.from_angle(model.heading)


func draw_debug_overlay() -> void:
	rounded_box(
		Model.ARENA,
		Color.TRANSPARENT,
		Model.ARENA_CORNER_RADIUS,
		DEBUG_WALL,
		2,
	)
	if not model.body.is_empty():
		draw_line(model.head, model.body[0], Color(DEBUG_LINE, 0.45), 1.5, true)
	for i in range(1, model.body.size()):
		draw_line(model.body[i - 1], model.body[i], Color(DEBUG_LINE, 0.85), 2.0, true)
	for center in model.body:
		draw_circle(center, 2.5, DEBUG_LINE)
	draw_debug_arrow(
		model.head,
		Vector2.from_angle(model.heading),
		72.0,
		Color("#6956c7"),
	)
	if debug_contact.is_empty():
		return

	var segment_a: Vector2 = debug_contact.segment_a
	var segment_b: Vector2 = debug_contact.segment_b
	var point: Vector2 = debug_contact.point
	var normal: Vector2 = debug_contact.normal
	var result_color := DEBUG_LETHAL if debug_contact.lethal else DEBUG_SAFE
	draw_line(segment_a, segment_b, Color(result_color, 0.28), 9.0, true)
	draw_line(segment_a, segment_b, result_color, 3.5, true)
	draw_circle(point, 5.0, result_color)
	draw_debug_arrow(point, normal, 64.0, Color("#ee5ead"))
	draw_debug_arrow(point, debug_contact.direction, 64.0, Color("#6956c7"))


func draw_debug_arrow(origin: Vector2, vector: Vector2, length: float, color: Color) -> void:
	if vector.length_squared() <= 0.0001:
		return
	var direction := vector.normalized()
	var tip := origin + direction * length
	var side := direction.orthogonal()
	draw_line(origin, tip, color, 2.5, true)
	draw_colored_polygon(
		PackedVector2Array(
			[
				tip,
				tip - direction * 11.0 + side * 5.0,
				tip - direction * 11.0 - side * 5.0,
			]
		),
		color,
	)


func ball(position: Vector2, r: float, color: Color) -> void:
	draw_circle(position + Vector2(1, 4), r + 0.6, Color(0.36, 0.40, 0.20, 0.13), true, -1, true)
	draw_circle(position, r + 0.8, color.darkened(0.21), true, -1, true)
	draw_circle(position, r, color, true, -1, true)
	draw_circle(
		position + Vector2(-r * 0.15, -r * 0.22), r * 0.73, color.lightened(0.08), true, -1, true
	)
	draw_circle(
		position + Vector2(-r * 0.30, -r * 0.38),
		r * 0.30,
		Color(1.0, 1.0, 0.87, 0.23),
		true,
		-1,
		true
	)


func draw_apple(position: Vector2, kind: int, scale_value: float = 1.0) -> void:
	if apple_atlas == null:
		return
	var display_size := Vector2.ONE * AppleAtlas.DISPLAY_SIZE * scale_value
	draw_texture_rect_region(
		apple_atlas,
		Rect2(position - display_size * 0.5, display_size),
		Rect2(kind * AppleAtlas.CELL_SIZE, 0, AppleAtlas.CELL_SIZE, AppleAtlas.CELL_SIZE),
	)


func draw_bomb(bomb: Dictionary) -> void:
	var p: Vector2 = bomb["position"]
	var remaining: float = bomb["left"]
	var pulse := 0.5 + sin(visual_time * (14.0 if remaining < 2.0 else 6.0)) * 0.5
	draw_circle(p, Model.BLAST_RADIUS, Color(0.83, 0.38, 0.26, 0.035 + pulse * 0.035))
	draw_set_transform(p)
	draw_multiline(bomb_dash_segments, Color(0.76, 0.44, 0.29, 0.28), 1.4, true)
	draw_set_transform(Vector2.ZERO)
	ellipse(p + Vector2(0, 23), Vector2(19, 5), Color(0.34, 0.34, 0.25, 0.15))
	var polygon := PackedVector2Array()
	for i in range(12):
		polygon.append(p + Vector2.from_angle(TAU * float(i) / 12.0 + PI / 12.0) * 21.0)
	draw_colored_polygon(polygon, Color("#505d53"))
	draw_rect(Rect2(p + Vector2(-7, -25), Vector2(13, 8)), Color("#707967"))
	draw_polyline(
		PackedVector2Array([p + Vector2(1, -25), p + Vector2(5, -32), p + Vector2(13, -32)]),
		Color("#9b8150"),
		3,
		false
	)
	draw_circle(p + Vector2(14, -32), 3 + pulse * 2, Color("#e6a849"))
	draw_rect(Rect2(p + Vector2(-13, -10), Vector2(4, 7)), Color("#7e8a75"))
	center_text(str(ceili(remaining)), p + Vector2(0, 8), 23, Color("#fff3cf"), bold)
	draw_arc(
		p, 27, -PI / 2, -PI / 2 + TAU * remaining / Model.BOMB_FUSE, 48, Color("#cb815a"), 2.5, true
	)


func draw_menu() -> void:
	rounded_box(
		Model.ARENA.grow(-2),
		Color(0.973, 0.957, 0.875, 0.66),
		Model.ARENA_CORNER_RADIUS - 2,
	)
	var card := Rect2(470, 253, 500, 430)
	rounded_box(Rect2(card.position + Vector2(0, 10), card.size), Color(0.30, 0.35, 0.22, 0.08), 26)
	rounded_box(card, Color("#fffdf0"), 26, Color("#dfdfc4"), 1)
	if state == State.READY:
		draw_apple(Vector2(660, 312), Model.Apple.RED, 0.8)
		draw_apple(Vector2(700, 305), Model.Apple.GREEN, 0.9)
		draw_apple(Vector2(740, 305), Model.Apple.GOLD, 0.95)
		draw_apple(Vector2(780, 312), Model.Apple.RAINBOW, 0.8)
		center_text("Ready to roll?", Vector2(720, 382), 38, INK, bold)
		center_text("Follow your appetite.", Vector2(720, 425), 18, MUTED)
		center_text("Left / Right to turn. Leave room to grow.", Vector2(720, 456), 17, INK)
		center_text("Press Enter to start", Vector2(720, 657), 13, MUTED)
	elif state == State.PAUSED:
		center_text("TAKE YOUR TIME", Vector2(720, 317), 12, GREEN, bold)
		center_text("A little breather.", Vector2(720, 382), 36, INK, bold)
		center_text("Your apples can wait.", Vector2(720, 427), 18, MUTED)
		center_text(
			(
				"Score %d    ·    %02d:%02d"
				% [model.score, int(model.elapsed) / 60, int(model.elapsed) % 60]
			),
			Vector2(720, 472),
			18,
			INK,
			bold
		)
	else:
		center_text(
			"NEW PERSONAL BEST" if model.score > last_best else "UNTIL NEXT BITE",
			Vector2(720, 311),
			12,
			GREEN,
			bold
		)
		center_text("That's a wrap.", Vector2(720, 368), 36, INK, bold)
		center_text(death_reason, Vector2(720, 402), 16, MUTED)
		center_text(str(model.score), Vector2(720, 446), 40, GREEN, bold)
		center_text("POINTS", Vector2(720, 469), 11, MUTED, bold)
		center_text("Press R to try again", Vector2(720, 657), 13, MUTED)


func rounded_box(
	rect: Rect2, color: Color, corner: int, border: Color = Color.TRANSPARENT, width: int = 0
) -> void:
	var key := "%s:%d:%s:%d" % [color.to_html(), corner, border.to_html(), width]
	var style: StyleBoxFlat = rounded_style_cache.get(key)
	if style == null:
		style = StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(corner)
		style.border_color = border
		style.set_border_width_all(width)
		rounded_style_cache[key] = style
	draw_style_box(style, rect)


func ellipse(position: Vector2, size_value: Vector2, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in range(24):
		polygon.append(position + Vector2.from_angle(float(i) * TAU / 24.0) * size_value)
	draw_colored_polygon(polygon, color)


func text_at(
	value: String, position: Vector2, size_value: int, color: Color, typeface: Font = null
) -> void:
	draw_string(
		typeface if typeface else font,
		position,
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size_value,
		color
	)


func center_text(
	value: String, position: Vector2, size_value: int, color: Color, typeface: Font = null
) -> void:
	var f := typeface if typeface else font
	text_at(
		value,
		(
			position
			- Vector2(f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x / 2, 0)
		),
		size_value,
		color,
		f
	)


func _on_apple(kind: int, position: Vector2, points: int) -> void:
	eat_pulse = 0.28
	popups.append(
		{
			"position": position + Vector2(-10, -24),
			"text": "+%d" % points,
			"life": 1.2,
			"color": APPLE_COLORS[kind]
		}
	)
	for i in range(12):
		effects.append(
			{
				"position": position,
				"velocity": Vector2.from_angle(TAU * i / 12.0) * (45.0 + i * 4),
				"life": 0.7,
				"size": 2.0 + i % 3,
				"color": APPLE_COLORS[kind]
			}
		)
	if model.score > best:
		best = model.score
		save_settings()
	sync_web_status()
	if sound_enabled:
		pickup_audio.stream = PICKUP_SOUNDS[kind]
		pickup_audio.play()


func _on_explosion(position: Vector2, blast_radius: float) -> void:
	blasts.append({"position": position, "radius": blast_radius, "life": BLAST_ANIMATION_DURATION})
	for i in range(28):
		var direction := Vector2.from_angle(TAU * i / 28.0)
		(
			effects
			. append(
				{
					"position": position + direction * 8.0,
					"velocity": direction * (95.0 + float(i % 7) * 22.0),
					"life": 0.55 + float(i % 5) * 0.055,
					"size": 2.5 + float(i % 4),
					"color": Color("#ffd05a") if i % 3 == 0 else Color("#e8653f"),
				}
			)
		)
	play_tone(85, 0.23)


func _on_contact_evaluated(info: Dictionary) -> void:
	debug_contact = info.duplicate()
	debug_contact_left = 3.0
	if info.lethal or slide_fx_cooldown > 0.0:
		return
	slide_fx_cooldown = 0.08
	var tangent: Vector2 = info.direction.slide(info.normal).normalized()
	for i in range(4):
		var spread := (float(i) - 1.5) * 9.0
		(
			effects
			. append(
				{
					"position": info.point + info.normal * 2.0,
					"velocity": -tangent * (28.0 + i * 7.0) + info.normal * spread,
					"life": 0.28 + i * 0.035,
					"size": 1.4 + i * 0.35,
					"color": Color("#c6a85b"),
				}
			)
		)


func _on_death(reason: String) -> void:
	death_reason = reason
	impact_flash = 0.45
	if reason == "Caught in a blast":
		blast_death_left = BLAST_DEATH_DELAY
		set_state(State.DYING)
	else:
		set_state(State.OVER)
	play_tone(180, 0.30)


func update_sound_button() -> void:
	sound_button.text = "Sound " + ("on" if sound_enabled else "off")
	update_audio()


func update_audio() -> void:
	if not sound_enabled:
		audio.stop()
		pickup_audio.stop()
		return
	audio.stream_paused = state == State.PAUSED
	pickup_audio.stream_paused = state == State.PAUSED


func save_settings() -> void:
	var save := ConfigFile.new()
	save.set_value("game", "best", best)
	save.set_value("game", "sound", sound_enabled)
	save.set_value("game", "difficulty", model.difficulty)
	save.set_value("game", "skin", skin_index)
	var error := save.save("user://smoothsnake.cfg")
	if error != OK:
		push_warning("Could not save local preferences: %s" % error_string(error))


func play_tone(frequency: float, duration: float) -> void:
	if not sound_enabled:
		return
	var sample_rate := 22050
	var samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / sample_rate
		var envelope := minf(t * 150.0, 1.0) * pow(1.0 - float(i) / samples, 2)
		var value := int(sin(TAU * frequency * t * (1.0 - t * 0.5)) * envelope * 4500)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	audio.stream = stream
	audio.play()
