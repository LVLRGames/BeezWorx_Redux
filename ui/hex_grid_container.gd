@tool
class_name HexGridContainer
extends Container

enum VerticalAlign { TOP, BOTTOM }
enum HexGrowDirection { DOWN, UP }

const SQRT3: float = 1.7320508075688772

@export var grow_direction: HexGrowDirection = HexGrowDirection.DOWN:
	set(v):
		grow_direction = v
		queue_sort()

@export var vertical_alignment: VerticalAlign = VerticalAlign.TOP:
	set(v):
		vertical_alignment = v
		queue_sort()

@export var columns: int = 5:
	set(v):
		columns = max(1, v)
		queue_sort()

@export var hex_radius: float = 0.0:
	set(v):
		hex_radius = maxf(0.0, v)
		queue_sort()

@export var gap: float = 2.0:
	set(v):
		gap = maxf(0.0, v)
		queue_sort()

@export var padding: Vector2 = Vector2.ZERO:
	set(v):
		padding = v
		queue_sort()

@export var odd_row_right: bool = true:
	set(v):
		odd_row_right = v
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_do_layout()


func _get_minimum_size() -> Vector2:
	var g := _get_layout_metrics()
	var children := _get_visible_children()
	var count: int = children.size()
	if count == 0:
		return Vector2.ZERO

	var rows: int = int(ceil(float(count) / float(columns)))
	var cols: int = mini(count, columns)

	var total_w: float = _get_content_width(cols, rows, g)
	var total_h: float = _get_content_height(rows, g)

	return Vector2(total_w, total_h) + padding * 2.0


func _do_layout() -> void:
	var children := _get_visible_children()
	var count: int = children.size()
	if count == 0:
		return

	var rows: int = int(ceil(float(count) / float(columns)))
	var g := _get_layout_metrics(count)

	var idx: int = 0
	for child: Control in children:
		var logical_col: int = idx % columns
		var logical_row: int = idx / columns
		var rect := _get_cell_rect_internal(logical_col, logical_row, rows, g)
		fit_child_in_rect(child, rect)
		idx += 1


func get_cell_center(col: int, row: int) -> Vector2:
	var children := _get_visible_children()
	var count: int = children.size()
	if count == 0:
		return Vector2.ZERO

	var rows: int = int(ceil(float(count) / float(columns)))
	var g := _get_layout_metrics(count)
	return _get_cell_rect_internal(col, row, rows, g).get_center()


func get_cell_rect(col: int, row: int) -> Rect2:
	var children := _get_visible_children()
	var count: int = children.size()
	if count == 0:
		return Rect2()

	var rows: int = int(ceil(float(count) / float(columns)))
	var g := _get_layout_metrics(count)
	return _get_cell_rect_internal(col, row, rows, g)


func index_to_col_row(i: int) -> Vector2i:
	return Vector2i(i % columns, i / columns)


func col_row_to_index(col: int, row: int) -> int:
	var idx: int = row * columns + col
	var children = _get_visible_children()
	if idx < 0 or idx >= children.size():
		return -1
	return idx


func _get_cell_rect_internal(col: int, logical_row: int, rows: int, g: Dictionary) -> Rect2:
	var physical_row: int = logical_row
	if grow_direction == HexGrowDirection.UP:
		physical_row = (rows - 1) - logical_row

	var row_offset: float = 0.0
	if physical_row % 2 == 1:
		row_offset = g.row_offset_dir * g.row_offset_amount

	var x: float = padding.x + col * g.step_x + row_offset
	var y: float = padding.y + g.v_offset + physical_row * g.step_y

	return Rect2(Vector2(x, y), Vector2(g.cell_w, g.cell_h))


func _get_layout_metrics(count: int = -1) -> Dictionary:
	var r: float = _get_effective_radius()
	var cell_w: float = SQRT3 * r
	var cell_h: float = 2.0 * r
	var h_gap: float = gap
	var v_gap: float = gap * 0.866
	var step_x: float = cell_w + h_gap
	var step_y: float = cell_h * 0.75 + v_gap

	if count < 0:
		count = _get_visible_children().size()

	var rows: int = int(ceil(float(count) / float(columns))) if count > 0 else 0
	var content_h: float = _get_content_height(rows, {
		"cell_h": cell_h,
		"step_y": step_y
	})

	var v_offset: float = 0.0
	if grow_direction == HexGrowDirection.UP:
		v_offset = maxf(0.0, size.y - content_h)

	return {
		"cell_w": cell_w,
		"cell_h": cell_h,
		"step_x": step_x,
		"step_y": step_y,
		"v_offset": v_offset,
		"row_offset_amount": step_x * 0.5,
		"row_offset_dir": 1.0 if odd_row_right else -1.0,
	}


func _get_content_width(cols: int, rows: int, g: Dictionary) -> float:
	if cols <= 0:
		return 0.0

	var width: float = g.cell_w
	if cols > 1:
		width += float(cols - 1) * g.step_x

	if rows > 1:
		width += g.row_offset_amount

	return width


func _get_content_height(rows: int, g: Dictionary) -> float:
	if rows <= 0:
		return 0.0

	var height: float = g.cell_h
	if rows > 1:
		height += float(rows - 1) * g.step_y

	return height


func _get_effective_radius() -> float:
	if hex_radius > 0.0:
		return hex_radius

	var max_dim: float = 0.0
	for child in get_children():
		if child is Control and child.visible:
			var ms: Vector2 = (child as Control).get_combined_minimum_size()
			max_dim = maxf(max_dim, maxf(ms.x / SQRT3, ms.y * 0.5))
	return maxf(max_dim, 16.0)


func _get_visible_children() -> Array[Control]:
	var out: Array[Control] = []
	for child in get_children():
		if child is Control and (child as Control).visible:
			out.append(child as Control)
	return out
