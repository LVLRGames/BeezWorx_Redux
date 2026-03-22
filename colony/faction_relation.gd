# FILE: res://colony/faction_relation.gd
# Tracks diplomatic standing and trade history with a specific faction.
class_name FactionRelation
extends RefCounted

var faction_id: StringName = &""
var relation_score: float = 0.0
var is_allied: bool = false
var is_hostile: bool = false
var trade_history: Array[TradeRecord] = []
var first_contact_day: int = 0
var last_gift_day: int = 0
var preference_revealed: bool = false

# ════════════════════════════════════════════════════════════════════════════ #
#  Serialization
# ════════════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	var th: Array = []
	for tr: TradeRecord in trade_history:
		th.append({
			"day":           tr.day,
			"item_id":       str(tr.item_id),
			"item_count":    tr.item_count,
			"match_score":   tr.match_score,
			"relation_delta": tr.relation_delta,
		})
	return {
		"faction_id":          str(faction_id),
		"relation_score":      relation_score,
		"is_allied":           is_allied,
		"is_hostile":          is_hostile,
		"trade_history":       th,
		"first_contact_day":   first_contact_day,
		"last_gift_day":       last_gift_day,
		"preference_revealed": preference_revealed,
	}

static func from_dict(data: Dictionary) -> FactionRelation:
	var fr := FactionRelation.new()
	fr.faction_id          = StringName(data.get("faction_id",    ""))
	fr.relation_score      = data.get("relation_score",      0.0)
	fr.is_allied           = data.get("is_allied",           false)
	fr.is_hostile          = data.get("is_hostile",          false)
	fr.first_contact_day   = data.get("first_contact_day",   0)
	fr.last_gift_day       = data.get("last_gift_day",       0)
	fr.preference_revealed = data.get("preference_revealed", false)
	for tr_dict in data.get("trade_history", []):
		var tr := TradeRecord.new()
		tr.day            = tr_dict.get("day",            0)
		tr.item_id        = StringName(tr_dict.get("item_id", ""))
		tr.item_count     = tr_dict.get("item_count",     0)
		tr.match_score    = tr_dict.get("match_score",    0.0)
		tr.relation_delta = tr_dict.get("relation_delta", 0.0)
		fr.trade_history.append(tr)
	return fr
