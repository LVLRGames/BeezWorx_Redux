# slot_designation_def.gd
# res://defs/hive/slot_designation_def.gd
#
# Author one .tres per designation in res://defs/hive/designations/
# Example files to create:
#   locked.tres, general.tres, bed.tres, storage.tres, crafting.tres, nursery.tres

class_name SlotDesignationDef
extends Resource

# ── Identity ──────────────────────────────────────────────────────────────────
@export var designation_id:  int        = 0
@export var display_name:    String     = ""
@export var label_initial:   String     = "?"

# ── Visual ────────────────────────────────────────────────────────────────────
@export_group("Visual")
## Column in the icon atlas (0-7)
@export var icon_col:        int        = 0
## Background hex modulate color
@export var color:           Color      = Color(0.6, 0.6, 0.6)

## How the progress bar behaves for this designation
@export_enum("None", "LinearFill", "Radial") var progress_type: int = 0

## What the ItemIcon sprite shows
@export_enum("None", "FilterItem", "RecipeProduct", "SleeperRole", "Contextual") \
	var item_icon_behavior: int = 0

# ── Permissions ───────────────────────────────────────────────────────────────
@export_group("Permissions")
@export var can_deposit:        bool = false
@export var can_withdraw:       bool = false
@export var can_sleep:          bool = false
@export var can_craft:          bool = false
@export var can_feed_egg:       bool = false
@export var can_change_desig:   bool = true    # queen only gate is in overlay
@export var is_locked:          bool = false   # true only for LOCKED designation

# ── Progress thresholds ───────────────────────────────────────────────────────
@export_group("Progress")
## For LINEAR_FILL: max units for a full bar (eg storage capacity)
@export var progress_max:       float = 100.0

# ── Constants — progress_type ─────────────────────────────────────────────────
const PROGRESS_NONE:   int = 0
const PROGRESS_LINEAR: int = 1
const PROGRESS_RADIAL: int = 2

# ── Constants — item_icon_behavior ────────────────────────────────────────────
const ITEM_NONE:          int = 0
const ITEM_FILTER:        int = 1
const ITEM_RECIPE_PRODUCT: int = 2
const ITEM_SLEEPER_ROLE:  int = 3
const ITEM_CONTEXTUAL:    int = 4
