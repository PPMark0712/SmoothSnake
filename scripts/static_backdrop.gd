extends Node2D
## Drawn once into a viewport-sized texture and reused without resampling.

const Model = preload("res://scripts/snake_model.gd")
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

var font: Font
var bold: Font
var board_dot_segments := PackedVector2Array()
var rounded_style_cache: Dictionary = {}


func configure(normal_font: Font, bold_font: Font, dots: PackedVector2Array) -> void:
	font = normal_font
	bold = bold_font
	board_dot_segments = dots
	queue_redraw()


func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(0, 0, 1440, 900), PAPER)
	draw_brand()
	draw_hud_frame()
	rounded_box(
		Rect2(Model.ARENA.position + Vector2(0, 4), Model.ARENA.size),
		Color(0.33, 0.36, 0.20, 0.09),
		Model.ARENA_CORNER_RADIUS,
	)
	rounded_box(
		Model.ARENA,
		Color("#fdfbed"),
		Model.ARENA_CORNER_RADIUS,
		Color("#d5d6b7"),
		3,
	)
	draw_multiline(board_dot_segments, Color(0.57, 0.60, 0.42, 0.14), 1.6, true)
	draw_footer()


func draw_brand() -> void:
	for i in range(3):
		ball(Vector2(64 + i * 13, 62 + sin(float(i)) * 7), 9.0, Color("#9fb86d"))
	ball(Vector2(98, 60), 12, Color("#aac477"))
	draw_circle(Vector2(101, 57), 2, INK)
	text_at("SmoothSnake", Vector2(126, 70), 30, INK, bold)
	text_at("SMALL TURNS. BIG ADVENTURES.", Vector2(49, 108), 11, MUTED)


func draw_hud_frame() -> void:
	rounded_box(Rect2(1016, 35, 104, 76), Color("#efecd7"), 16)
	rounded_box(Rect2(1132, 35, 108, 76), Color("#e3eacb"), 16)
	text_at("BEST", Vector2(1034, 58), 11, MUTED, bold)
	text_at("SCORE", Vector2(1150, 58), 11, GREEN, bold)


func draw_footer() -> void:
	draw_apple(Vector2(66, 817), Model.Apple.RED, 0.65)
	text_at("+1", Vector2(86, 824), 15, INK, bold)
	draw_apple(Vector2(140, 817), Model.Apple.GREEN, 0.65)
	text_at("+2", Vector2(160, 824), 15, INK, bold)
	draw_apple(Vector2(220, 817), Model.Apple.GOLD, 0.65)
	text_at("+5  ·  1.5× speed / 10s", Vector2(240, 824), 14, INK)
	draw_apple(Vector2(435, 817), Model.Apple.RAINBOW, 0.65)
	text_at("+10  ·  10 apples / 10s", Vector2(455, 824), 14, INK)
	draw_circle(Vector2(670, 817), 8, Color("#505d53"))
	text_at("5s fuse · keep clear", Vector2(689, 824), 14, MUTED)
	keycap(Rect2(1045, 802, 32, 29), "←")
	keycap(Rect2(1084, 802, 32, 29), "→")
	text_at("steer", Vector2(1127, 823), 15, INK)
	keycap(Rect2(1212, 802, 47, 29), "esc")
	text_at("pause", Vector2(1270, 823), 15, INK)
	text_at("Wide glances slide. Sharp hits end the run.", Vector2(181, 871), 12, MUTED)
	right_text("MADE FOR A LITTLE BREAK", Vector2(1391, 871), 11, MUTED)


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


func ball(position: Vector2, radius: float, color: Color) -> void:
	draw_circle(
		position + Vector2(1, 4),
		radius + 0.6,
		Color(0.36, 0.40, 0.20, 0.13),
		true,
		-1,
		true
	)
	draw_circle(position, radius + 0.8, color.darkened(0.21), true, -1, true)
	draw_circle(position, radius, color, true, -1, true)
	draw_circle(
		position + Vector2(-radius * 0.15, -radius * 0.22),
		radius * 0.73,
		color.lightened(0.08),
		true,
		-1,
		true
	)
	draw_circle(
		position + Vector2(-radius * 0.30, -radius * 0.38),
		radius * 0.30,
		Color(1.0, 1.0, 0.87, 0.23),
		true,
		-1,
		true
	)


func draw_apple(position: Vector2, kind: int, scale_value: float = 1.0) -> void:
	var color: Color = APPLE_COLORS[kind]
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
				[Vector2(-11, -8), Vector2(10, -8), Vector2(12, -5), Vector2(-12, -5)]
			),
			Color("#df6e73")
		)
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(-12, -4), Vector2(12, -4), Vector2(12, -1), Vector2(-12, -1)]
			),
			Color("#efa34f")
		)
		draw_colored_polygon(
			PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(11, 3), Vector2(-11, 3)]),
			Color("#e8cf55")
		)
		draw_colored_polygon(
			PackedVector2Array([Vector2(-11, 4), Vector2(11, 4), Vector2(9, 7), Vector2(-10, 7)]),
			Color("#78b979")
		)
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(-9, 8),
					Vector2(8, 8),
					Vector2(6, 11),
					Vector2(0, 9),
					Vector2(-7, 10),
				]
			),
			Color("#65a9c4")
		)
	draw_rect(Rect2(-9, -6, 4, 6), Color(1, 1, 0.91, 0.70))
	draw_rect(Rect2(-1, -17, 3, 8), Color("#7b6443"))
	draw_colored_polygon(
		PackedVector2Array([Vector2(1, -15), Vector2(5, -20), Vector2(12, -20), Vector2(9, -15)]),
		Color("#7b9a54")
	)
	draw_set_transform(Vector2.ZERO)


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
	var selected_font := typeface if typeface else font
	text_at(
		value,
		position
		- Vector2(
			selected_font.get_string_size(
				value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value
			).x
			/ 2,
			0
		),
		size_value,
		color,
		selected_font
	)


func right_text(value: String, position: Vector2, size_value: int, color: Color) -> void:
	text_at(
		value,
		position
		- Vector2(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x, 0),
		size_value,
		color
	)
