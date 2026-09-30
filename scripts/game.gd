# gdlint: disable=max-public-methods
extends Node2D
## Presentation only: the simulation is independently runnable in headless tests.

enum State { READY, PLAYING, PAUSED, OVER }

const Model = preload("res://scripts/snake_model.gd")
const INK := Color("#354737")
const MUTED := Color("#859077")
const GREEN := Color("#577d46")
const PAPER := Color("#f8f4df")
const ARENA_PANEL := Rect2(48, 130, 1344, 658)

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
var secondary := Button.new()
var pause_button := Button.new()
var sound_button := Button.new()
var sound_enabled := true
var audio := AudioStreamPlayer.new()


func _ready() -> void:
	font = ThemeDB.fallback_font
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_embolden = 0.7
	bold = variation
	var save := ConfigFile.new()
	if save.load("user://smoothsnake.cfg") == OK:
		best = int(save.get_value("game", "best", 0))
		sound_enabled = bool(save.get_value("game", "sound", true))
	model.apple_eaten.connect(_on_apple)
	model.exploded.connect(_on_explosion)
	model.died.connect(_on_death)
	add_child(audio)
	build_ui()
	model.reset()
	set_state(State.READY)
	get_viewport().size_changed.connect(layout_ui)
	layout_ui()


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(menu)
	menu.add_child(primary)
	menu.add_child(secondary)
	layer.add_child(pause_button)
	layer.add_child(sound_button)
	style_button(primary, true)
	style_button(secondary, false)
	style_button(pause_button, false)
	style_button(sound_button, false)
	primary.pressed.connect(
		func():
			if state == State.PAUSED:
				set_state(State.PLAYING)
			else:
				start_run()
	)
	secondary.pressed.connect(start_run)
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
	primary.position = Vector2(520, 526)
	primary.size = Vector2(400, 52)
	secondary.position = Vector2(520, 590)
	secondary.size = Vector2(400, 44)
	pause_button.position = Vector2(1260, 47)
	pause_button.size = Vector2(132, 48)
	sound_button.position = Vector2(48, 851)
	sound_button.size = Vector2(116, 28)
	sound_button.add_theme_font_size_override("font_size", 12)


func set_state(value: State) -> void:
	state = value
	menu.visible = state != State.PLAYING
	secondary.visible = state == State.PAUSED
	pause_button.visible = state == State.PLAYING
	primary.text = (
		"Let's play"
		if state == State.READY
		else ("Resume" if state == State.PAUSED else "Play again")
	)
	secondary.text = "Restart run"
	if menu.visible:
		primary.grab_focus()
	else:
		primary.release_focus()
	sync_web_status()
	queue_redraw()


func sync_web_status() -> void:
	if not OS.has_feature("web"):
		return
	# Publish the visible state on the canvas for accessibility and browser checks.
	var status_name: String = ["ready", "playing", "paused", "over"][state]
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
	if event.keycode == KEY_ESCAPE:
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and state in [State.PAUSED, State.OVER]:
		start_run()
	elif event.keycode == KEY_ENTER and state == State.READY:
		start_run()


func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
		var right := (
			Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
		)
		model.step(delta, float(right) - float(left))


func _process(delta: float) -> void:
	if state != State.PAUSED:
		visual_time += delta
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
	queue_redraw()


func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(0, 0, 1440, 900), PAPER)
	draw_brand()
	draw_hud()
	rounded_box(ARENA_PANEL, Color("#fdfbed"), 24, Color("#dcdcc0"), 2)
	for x in range(78, 1380, 26):
		for y in range(158, 774, 26):
			draw_circle(Vector2(x, y), 0.8, Color(0.57, 0.60, 0.42, 0.14))
	for apple in model.apples:
		var p: Vector2 = apple["position"]
		draw_apple(p + Vector2(0, sin(visual_time * 2.6 + p.x) * 2.0), apple["kind"])
	for bomb in model.bombs:
		draw_bomb(bomb)
	draw_snake()
	for blast in blasts:
		var alpha: float = blast["life"] / 0.65
		draw_circle(
			blast["position"],
			blast["radius"] * (1.0 - alpha * 0.3),
			Color(0.90, 0.39, 0.24, alpha * 0.20)
		)
		draw_arc(
			blast["position"],
			blast["radius"] * (1.0 - alpha * 0.15),
			0,
			TAU,
			80,
			Color(0.91, 0.45, 0.27, alpha),
			3,
			true
		)
	for particle in effects:
		var color: Color = particle["color"]
		color.a = clampf(particle["life"] * 1.4, 0.0, 1.0)
		draw_circle(particle["position"], particle["size"], color)
	for popup in popups:
		var color: Color = popup["color"]
		color.a = minf(1.0, popup["life"] * 2.0)
		text_at(popup["text"], popup["position"], 25, color, bold)
	draw_footer()
	if state != State.PLAYING:
		draw_menu()


func draw_brand() -> void:
	for i in range(3):
		ball(Vector2(64 + i * 13, 62 + sin(float(i)) * 7), 9.0, Color("#9fb86d"))
	ball(Vector2(98, 60), 12, Color("#aac477"))
	draw_circle(Vector2(101, 57), 2, INK)
	text_at("SmoothSnake", Vector2(126, 70), 30, INK, bold)
	text_at("SMALL TURNS. BIG ADVENTURES.", Vector2(49, 108), 11, MUTED)


func draw_hud() -> void:
	if model.gold_left > 0:
		status_pill(Vector2(638, 52), "2× SPEED", model.gold_left, 10.0, Color("#c49a39"))
	if model.rainbow_left > 0:
		status_pill(Vector2(818, 52), "APPLE RAIN", model.rainbow_left, 20.0, Color("#9b7cbd"))
	rounded_box(Rect2(1016, 35, 104, 76), Color("#efecd7"), 16)
	rounded_box(Rect2(1132, 35, 108, 76), Color("#e3eacb"), 16)
	text_at("BEST", Vector2(1034, 58), 11, MUTED, bold)
	text_at(str(best).pad_zeros(2), Vector2(1034, 91), 29, INK, bold)
	text_at("SCORE", Vector2(1150, 58), 11, GREEN, bold)
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
	for i in range(model.body.size() - 1, -1, -1):
		var t := float(i) / maxf(1.0, model.body.size() - 1.0)
		ball(model.body[i], model.radius(), Color("#a9c775").lerp(Color("#cfdb94"), t * 0.65))
	if model.gold_left > 0:
		draw_arc(model.head, model.head_radius() + 6, 0, TAU, 48, Color("#dec270"), 2, true)
	ball(model.head, model.head_radius(), Color("#a7c774"))
	var forward := Vector2.from_angle(model.heading)
	var side := forward.orthogonal()
	for sign_value in [-1.0, 1.0]:
		var eye: Vector2 = (
			model.head
			+ forward * model.head_radius() * 0.40
			+ side * sign_value * model.head_radius() * 0.46
		)
		draw_circle(eye, model.head_radius() * 0.25, Color("#fffef1"))
		if state == State.OVER:
			var r := model.head_radius() * 0.10
			draw_line(eye - Vector2(r, r), eye + Vector2(r, r), INK, 1.7, true)
			draw_line(eye + Vector2(-r, r), eye + Vector2(r, -r), INK, 1.7, true)
		else:
			draw_circle(eye + forward * 1.1, model.head_radius() * 0.12, INK)
			draw_circle(eye + forward * 1.1 + Vector2(-0.5, -0.7), 0.65, Color.WHITE)
		var cheek: Vector2 = model.head + side * sign_value * model.head_radius() * 0.70
		draw_circle(cheek, model.head_radius() * 0.14, Color("#dfac83"))


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
	var colors := [Color("#df6e55"), Color("#e6b947"), Color("#b093ce")]
	var color: Color = colors[kind]
	var outline := PackedVector2Array(
		[
			Vector2(-3, -10),
			Vector2(-9, -12),
			Vector2(-13, -8),
			Vector2(-15, -2),
			Vector2(-13, 7),
			Vector2(-8, 13),
			Vector2(-2, 14),
			Vector2(1, 12),
			Vector2(7, 14),
			Vector2(12, 9),
			Vector2(15, 1),
			Vector2(13, -7),
			Vector2(8, -11),
			Vector2(2, -10)
		]
	)
	draw_set_transform(position, 0.0, Vector2.ONE * scale_value)
	ellipse(Vector2(0, 17), Vector2(13, 3), Color(0.40, 0.38, 0.22, 0.13))
	draw_colored_polygon(outline, color.darkened(0.15))
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-11, -7),
				Vector2(-5, -10),
				Vector2(1, -7),
				Vector2(8, -9),
				Vector2(12, -4),
				Vector2(11, 5),
				Vector2(6, 11),
				Vector2(0, 9),
				Vector2(-7, 10),
				Vector2(-12, 3)
			]
		),
		color
	)
	if kind == Model.Apple.RAINBOW:
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(-12, -4), Vector2(12, -4), Vector2(12, 0), Vector2(-12, 0)]
			),
			Color("#ebbc73")
		)
		draw_colored_polygon(
			PackedVector2Array([Vector2(-11, 1), Vector2(12, 1), Vector2(10, 5), Vector2(-10, 5)]),
			Color("#91b888")
		)
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(-9, 6), Vector2(10, 6), Vector2(6, 11), Vector2(0, 9), Vector2(-7, 10)]
			),
			Color("#85b8c2")
		)
	draw_rect(Rect2(-9, -6, 4, 6), Color(1, 1, 0.91, 0.70))
	draw_rect(Rect2(-1, -17, 3, 8), Color("#7b6443"))
	draw_colored_polygon(
		PackedVector2Array([Vector2(1, -15), Vector2(5, -20), Vector2(12, -20), Vector2(9, -15)]),
		Color("#7b9a54")
	)
	draw_set_transform(Vector2.ZERO)


func draw_bomb(bomb: Dictionary) -> void:
	var p: Vector2 = bomb["position"]
	var remaining: float = bomb["left"]
	var pulse := 0.5 + sin(visual_time * (14.0 if remaining < 2.0 else 6.0)) * 0.5
	draw_circle(p, Model.BLAST_RADIUS, Color(0.83, 0.38, 0.26, 0.035 + pulse * 0.035))
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		draw_arc(
			p, Model.BLAST_RADIUS, angle, angle + 0.10, 4, Color(0.76, 0.44, 0.29, 0.28), 1.4, true
		)
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


func draw_footer() -> void:
	draw_apple(Vector2(66, 817), Model.Apple.RED, 0.65)
	text_at("+1", Vector2(86, 824), 15, INK, bold)
	draw_apple(Vector2(157, 817), Model.Apple.GOLD, 0.65)
	text_at("+5  ·  2× speed / 10s", Vector2(177, 824), 14, INK)
	draw_apple(Vector2(372, 817), Model.Apple.RAINBOW, 0.65)
	text_at("+10  ·  apple rain / 20s", Vector2(392, 824), 14, INK)
	draw_circle(Vector2(609, 817), 8, Color("#505d53"))
	text_at("5s fuse · keep clear", Vector2(628, 824), 14, MUTED)
	keycap(Rect2(1045, 802, 32, 29), "←")
	keycap(Rect2(1084, 802, 32, 29), "→")
	text_at("steer", Vector2(1127, 823), 15, INK)
	keycap(Rect2(1212, 802, 47, 29), "esc")
	text_at("pause", Vector2(1270, 823), 15, INK)
	text_at("Glancing hits slide. Head-on hits end the run.", Vector2(181, 871), 12, MUTED)
	right_text("MADE FOR A LITTLE BREAK", Vector2(1391, 871), 11, MUTED)


func draw_menu() -> void:
	draw_rect(ARENA_PANEL.grow(-2), Color(0.973, 0.957, 0.875, 0.66))
	var card := Rect2(470, 263, 500, 396)
	rounded_box(Rect2(card.position + Vector2(0, 10), card.size), Color(0.30, 0.35, 0.22, 0.08), 26)
	rounded_box(card, Color("#fffdf0"), 26, Color("#dfdfc4"), 1)
	if state == State.READY:
		draw_apple(Vector2(681, 312), Model.Apple.RED, 0.8)
		draw_apple(Vector2(720, 305), Model.Apple.GOLD, 0.95)
		draw_apple(Vector2(759, 312), Model.Apple.RAINBOW, 0.8)
		center_text("Ready to roll?", Vector2(720, 382), 38, INK, bold)
		center_text("Follow your appetite.", Vector2(720, 425), 18, MUTED)
		center_text("Left / Right to turn. Leave room to grow.", Vector2(720, 456), 17, INK)
		center_text("Press Enter to start", Vector2(720, 615), 13, MUTED)
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
		center_text(str(model.score), Vector2(720, 474), 54, GREEN, bold)
		center_text("POINTS", Vector2(720, 497), 11, MUTED, bold)
		center_text("Press R to try again", Vector2(720, 615), 13, MUTED)


func keycap(rect: Rect2, label: String) -> void:
	rounded_box(rect, Color("#eeeacf"), 6, Color("#dbdcc0"), 1)
	if label in ["←", "→"]:
		var direction := -1.0 if label == "←" else 1.0
		var center := rect.get_center()
		var tip := center + Vector2(6 * direction, 0)
		draw_line(center - Vector2(6 * direction, 0), tip, INK, 1.5, true)
		draw_polyline(
			PackedVector2Array(
				[tip + Vector2(-4 * direction, -4), tip, tip + Vector2(-4 * direction, 4)]
			),
			INK,
			1.5,
			true
		)
	else:
		center_text(label, Vector2(rect.get_center().x, rect.position.y + 20), 15, INK)


func rounded_box(
	rect: Rect2, color: Color, corner: int, border: Color = Color.TRANSPARENT, width: int = 0
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(corner)
	style.border_color = border
	style.set_border_width_all(width)
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


func right_text(value: String, position: Vector2, size_value: int, color: Color) -> void:
	text_at(
		value,
		(
			position
			- Vector2(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x, 0)
		),
		size_value,
		color
	)


func _on_apple(kind: int, position: Vector2, points: int) -> void:
	var colors := [Color("#df6e55"), Color("#dbb44f"), Color("#a78bc7")]
	popups.append(
		{
			"position": position + Vector2(-10, -24),
			"text": "+%d" % points,
			"life": 1.2,
			"color": colors[kind]
		}
	)
	for i in range(12):
		effects.append(
			{
				"position": position,
				"velocity": Vector2.from_angle(TAU * i / 12.0) * (45.0 + i * 4),
				"life": 0.7,
				"size": 2.0 + i % 3,
				"color": colors[kind]
			}
		)
	if model.score > best:
		best = model.score
		save_settings()
	sync_web_status()
	play_tone(660.0 + kind * 180.0, 0.13)


func _on_explosion(position: Vector2, blast_radius: float) -> void:
	blasts.append({"position": position, "radius": blast_radius, "life": 0.65})
	play_tone(85, 0.23)


func _on_death(reason: String) -> void:
	death_reason = reason
	set_state(State.OVER)
	play_tone(180, 0.30)


func update_sound_button() -> void:
	sound_button.text = "Sound " + ("on" if sound_enabled else "off")


func save_settings() -> void:
	var save := ConfigFile.new()
	save.set_value("game", "best", best)
	save.set_value("game", "sound", sound_enabled)
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
