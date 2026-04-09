# item_gem.gd
# res://world/items/item_gem.gd
#
# A single collectible item gem. Spawned by ItemGemManager at plant kill sites.
# Auto-collects into the first nearby pawn inventory that has space.
#
# SCENE STRUCTURE (built in code by ItemGemManager, no .tscn needed):
#   ItemGem (Node3D, this script)
#   ├── Visual (Node3D) — mesh + bob animation
#   │   └── MeshInstance3D
#   └── PickupArea (Area3D) — auto-collection trigger
#       └── CollisionShape3D (SphereShape3D, radius = PICKUP_RADIUS)
#
# PHYSICS LAYERS:
#   PickupArea collision_mask should include the layer your CharacterBody3D
#   pawns are on (default = layer 1). Adjust in ItemGemManager._build_gem()
#   if needed.

class_name ItemGem
extends Node3D

const PICKUP_RADIUS: float = 2.5   # world units — about half a hex
const LIFETIME:      float = 300.0 # seconds before auto-expire (5 min)
const BOB_SPEED:     float = 2.2
const BOB_HEIGHT:    float = 0.12
const SPIN_SPEED:    float = 1.1

var item_id:  StringName = &""
var item_count: int      = 1

var _age:        float  = 0.0
var _bob_offset: float  = 0.0
var _collected:  bool   = false
var _visual:     Node3D = null
var _pickup_delay: float = 0.25


func setup(p_item_id: StringName, p_count: int, p_bob_offset: float = 0.0) -> void:
	item_id      = p_item_id
	item_count   = p_count
	_bob_offset  = p_bob_offset


func _ready() -> void:
	add_to_group("item_gems")
	_build_visual()
	_build_pickup_area()


func _process(delta: float) -> void:
	if _collected:
		return

	_age += delta

	# Auto-expire
	if _age >= LIFETIME:
		queue_free()
		return

	# Bob and spin
	if _visual:
		var t: float = _age * BOB_SPEED + _bob_offset
		_visual.position.y = sin(t) * BOB_HEIGHT
		_visual.rotation.y += SPIN_SPEED * delta


# ── Construction ─────────────────────────────────────────────────────────────

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"

	var mi   := MeshInstance3D.new()
	var mat  := StandardMaterial3D.new()
	var tint := _resolve_color()

	var item: ItemDef = ItemRegistry.get_def(item_id) if ItemRegistry else null
	var icon: Texture2D = item.icon if item else null

	if icon:
		# ── Billboard quad with item icon ──────────────────────────────────
		var mesh        := QuadMesh.new()
		mesh.size        = Vector2(2, 2)
		mi.mesh          = mesh

		mat.texture_filter           = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.billboard_mode           = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture           = icon
		mat.albedo_color             = tint
		# Slight emission so gem is visible in shadow
		mat.emission_enabled         = true
		mat.emission                 = tint
		mat.emission_energy_multiplier = 0.25
	else:
		# ── Fallback sphere when no icon is authored ───────────────────────
		var mesh            := SphereMesh.new()
		mesh.radius          = 0.22
		mesh.height          = 0.44
		mesh.radial_segments = 8
		mesh.rings           = 4
		mi.mesh              = mesh

		mat.albedo_color             = tint
		mat.emission_enabled         = true
		mat.emission                 = tint
		mat.emission_energy_multiplier = 0.6

	mi.material_override = mat
	#mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_visual.add_child(mi)
	add_child(_visual)


func _build_pickup_area() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	# Monitor only — does not need its own collision layer.
	area.collision_layer = 0
	area.collision_mask  = 1   # layer 1 = default pawn layer; adjust if needed

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape   = sphere
	area.add_child(shape)

	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _resolve_color() -> Color:
	if ItemRegistry == null:
		return Color.WHITE
	var def: ItemDef = ItemRegistry.get_def(item_id)
	if def == null or def.icon_tint == Color.WHITE:
		# Fallback palette for common items
		match item_id:
			&"pollen":  return Color(1.0,  0.85, 0.1,  1.0)
			&"nectar":  return Color(1.0,  0.6,  0.05, 1.0)
			&"water":   return Color(0.2,  0.6,  1.0,  1.0)
			&"log":     return Color(0.5,  0.3,  0.1,  1.0)
			&"fiber":   return Color(0.4,  0.7,  0.2,  1.0)
			_:          return Color(0.85, 0.85, 0.85, 1.0)
	return def.icon_tint


# ── Collection ────────────────────────────────────────────────────────────────

## Public manual collection — called by PickupAbilityDef.execute().
## Returns true if the item was successfully added to pawn's inventory.
func collect(pawn: PawnBase) -> bool:
	if _collected:
		return false
	if pawn.state == null or pawn.state.inventory == null:
		return false
	if pawn.state.inventory.is_full():
		return false
	var overflow: int = pawn.state.inventory.add_item(item_id, item_count)
	if overflow == item_count:
		return false
	_collected = true
	EventBus.item_collected.emit(pawn.pawn_id, item_id, item_count - overflow)
	EventBus.pawn_inventory_changed.emit(pawn.pawn_id, item_id)
	queue_free()
	return true

func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if _age < _pickup_delay:
		return
	var pawn: PawnBase = body as PawnBase
	if pawn == null:
		return
	if pawn.state == null or pawn.state.inventory == null:
		return
	if pawn.state.inventory.is_full():
		return

	var overflow: int = pawn.state.inventory.add_item(item_id, item_count)
	if overflow == item_count:
		return   # no room — gem stays

	_collected = true
	EventBus.item_collected.emit(pawn.pawn_id, item_id, item_count - overflow)
	EventBus.pawn_inventory_changed.emit(pawn.pawn_id, item_id)
	queue_free()
