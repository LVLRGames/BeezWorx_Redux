# slot_deposit_rules.gd
# res://colony/hive/slot_deposit_rules.gd
#
# Pure static helper — no state, no nodes.
# Determines what items are valid for deposit into a given slot type.
# Called by HiveOverlay before showing deposit options.

class_name SlotDepositRules
extends RefCounted

# Items valid for nursery slots
const NURSERY_ITEMS: Array[StringName] = [
	&"royal_jelly",
	&"bee_jelly",
	&"bee_bread",
	&"honey",
	&"pollen",
	&"egg",
]

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

## Returns true if item_id can be deposited into this slot.
static func can_deposit(item_id: StringName, slot: HiveSlot) -> bool:
	match slot.designation:
		HiveSlot.SlotDesignation.GENERAL:
			return true
		HiveSlot.SlotDesignation.BED:
			return false
		HiveSlot.SlotDesignation.STORAGE:
			if slot.locked_item_id == &"":
				return true   # unset — first deposit will lock it
			return item_id == slot.locked_item_id
		HiveSlot.SlotDesignation.CRAFTING:
			if slot.locked_item_id == &"":
				return true   # no recipe set yet — accept anything
			# TODO Phase 5: check if item_id is an ingredient for slot.locked_item_id recipe
			return true
		HiveSlot.SlotDesignation.NURSERY:
			return item_id in NURSERY_ITEMS
	return false

## Returns filtered list of item_ids from inventory that are valid for this slot.
static func filter_depositable(
	inventory: PawnInventory,
	slot: HiveSlot
) -> Array[StringName]:
	var out: Array[StringName] = []
	for item_id: StringName in inventory.get_item_ids():
		if can_deposit(item_id, slot):
			out.append(item_id)
	return out

## Returns true if deposit UI should be shown at all for this slot.
static func deposit_enabled(slot: HiveSlot) -> bool:
	return slot.designation != HiveSlot.SlotDesignation.BED

## Returns true if this item placement should auto-convert slot to nursery.
static func should_auto_nursery(item_id: StringName, slot: HiveSlot) -> bool:
	return item_id == &"egg" and slot.designation != HiveSlot.SlotDesignation.NURSERY

## Returns true if this deposit should lock the storage slot to this item type.
static func should_lock_storage(item_id: StringName, slot: HiveSlot) -> bool:
	return slot.designation == HiveSlot.SlotDesignation.STORAGE \
		and slot.locked_item_id == &""
