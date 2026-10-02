extends Node2D
## Pre-renders all apple kinds into one shared texture.

const Model = preload("res://scripts/snake_model.gd")
const COLORS = [
	Color("#df6e55"),
	Color("#e6b947"),
	Color("#b093ce"),
	Color("#6db84f"),
]
const CELL_SIZE := 64
const DISPLAY_SIZE := 64.0
const RENDER_SCALE := 1.0


func _draw() -> void:
	for kind in range(COLORS.size()):
		draw_apple(
			Vector2(kind * CELL_SIZE + CELL_SIZE * 0.5, CELL_SIZE * 0.5),
			kind,
			RENDER_SCALE,
		)


func draw_apple(position: Vector2, kind: int, scale_value: float) -> void:
	var color: Color = COLORS[kind]
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


func ellipse(position: Vector2, size_value: Vector2, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in range(24):
		polygon.append(position + Vector2.from_angle(float(i) * TAU / 24.0) * size_value)
	draw_colored_polygon(polygon, color)
