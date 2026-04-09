# hex_plant_def.gd
# res://world/hex_plant_def.gd
#
# Base def for every living plant. Extends HexGridObjectDef with:
#   - PlantSubcategory enum (replaces old RESOURCE_PLANT/TREE/etc. categories)
#   - Health / toughness for the damage system
#   - Pollen species isolation (grass won't hybridize with flowers)
#   - Item drop on kill
#
# SUBCLASSES:
#   GrassDef   — plant_subcategory = GRASS, pollen isolation enforced
#   HexTreeDef — plant_subcategory = TREE, slots_occupied = 6

class_name HexPlantDef
extends HexGridObjectDef

enum PlantSubcategory {
	GRASS,            # ground cover; spreads readily; low nectar; pollen isolation
	RESOURCE,         # harvestable flowering plant (former RESOURCE_PLANT)
	ACTIVE_DEFENSE,   # attacks pawns in range (former DEFENSIVE_ACTIVE)
	PASSIVE_DEFENSE,  # blocks/damages on contact (former DEFENSIVE_PASSIVE)
	TREE,             # structural anchor; hive sites; long lifecycle
}

func _init() -> void:
	category = Category.PLANT

# ── Subcategory ───────────────────────────────────────────────────────
@export var plant_subcategory: PlantSubcategory = PlantSubcategory.RESOURCE

# ── Health ────────────────────────────────────────────────────────────
## Total HP before this plant is killed by damage.
@export var max_health: float = 100.0
## Damage reduction divisor. effective_damage = raw_damage / toughness.
## 1.0 = normal. 2.0 = takes half damage. 0.5 = takes double damage.
@export var toughness:  float = 1.0

# ── Genetics ──────────────────────────────────────────────────────────
@export var genes:      HexPlantGenes = null
@export var plant_data: HexPlantData  = null

# ── Pollen isolation ──────────────────────────────────────────────────
## Cross-pollination tag. Plants only hybridize with those sharing this tag
## when either plant has can_hybridize_across_species = false.
## Empty string = unrestricted (default for resource plants).
@export var pollen_species_tag:           StringName = &""
## If false, this plant only hybridizes with plants sharing its pollen_species_tag.
@export var can_hybridize_across_species: bool       = true

# ── Item drop on kill ─────────────────────────────────────────────────
## ItemDef id spawned as an item gem when this plant is killed by damage.
## Empty = no drop. Overrideable per-ability via DamagePlantAbilityDef.drop_item_override.
@export var drop_item_id:  StringName = &""
## 0–1 probability a kill spawns the drop. 1.0 = always, 0.3 = 30% chance.
@export var drop_chance:   float      = 1.0
## Number of item gems to drop on kill.
@export var drop_count:   int        = 1
