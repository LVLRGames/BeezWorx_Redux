# BeezWorx Findings & Discoveries

*(This document stores engine quirks, performance constraints, and playtest insights.)*

### Current Findings:
- Using `Array[Resource]` in Godot 4 exports works reasonably well for typed data definitions (like Recipes using `Array[ItemDef]`), avoiding the current limitations of Typed Dictionaries in the inspector.
- Deterministic simulation relies heavily on isolating the RNG seed and ensuring logic steps via predictable `advance_tick()` methods rather than variable delta time in `_process`.

### Performance: Colony Inventory Query Scaling (HiveSystem)
- **Finding:** `HiveSystem.get_colony_inventory_count` uses a dirty-flag aggregate cache rebuilt on every `deposit_item` / `withdraw_item` call. `find_nearest_hive_with_item` is O(hives) per call, invoked by every pawn task planner evaluation.
- **At MVP scale** (≤30 hives, ≤150 pawns): acceptable. Cache rebuilds are fast; worst-case `find_nearest_hive_with_item` load is ~4500 distance checks/second.
- **Scaling wall:** At 50+ hives with dense ant conveyor throughput, `find_nearest_hive_with_item` becomes the bottleneck as task planner calls multiply.
- **Proposed solution (implement when needed):** Replace the linear hive scan with a **per-item spatial index**: `Dictionary[StringName, Array[int]]` mapping `item_id → [hive_ids sorted by world position]`. Rebuild the sorted list only when that item's count in any hive crosses zero (stock appears or is fully depleted). Task planners scan the front of a short sorted list rather than all hives. The existing dirty-flag cache for `get_colony_inventory_count` remains unchanged — only `find_nearest_hive_with_item` needs the spatial index.
