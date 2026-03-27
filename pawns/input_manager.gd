extends Node

#region Signals
signal player_assigned(player_index: int)
signal player_unassigned(player_index: int)
signal player_device_lost(player_index: int)
signal player_device_restored(player_index: int)
signal bindings_changed(player_index: int, base_action: StringName)
#endregion


#region Enums
enum DeviceType { NONE, KEYBOARD, JOYPAD }
enum KeyboardLayout { WASD, ARROWS }
#endregion


#region Constants / Config
const MAX_PLAYERS: int = 4
const BASE_ACTIONS_OVERRIDE: Array[StringName] = []
const EXCLUDE_PREFIXES: Array[String] = ["ui_"]
const EXCLUDE_ACTIONS: Array[StringName] = []
const ACTION_DEADZONES: Dictionary = {
	&"move_left": 0.4,
	&"move_right": 0.4,
	&"move_up": 0.4,
	&"move_down": 0.4,
}

# Join buttons (raw) for hot-joining with gamepads.
const JOIN_JOY_BUTTONS: Array[int] = [JOY_BUTTON_START, JOY_BUTTON_A]
#endregion


#region State / Data
var _base_actions: Array[StringName] = []

class PlayerSlot:
	var index: int
	var device_type: DeviceType = DeviceType.NONE
	var joy_id: int = -1
	var joy_guid: String = ""
	var keyboard_layout: KeyboardLayout = KeyboardLayout.WASD
	var active: bool = false          # has a player in this slot
	var device_lost: bool = false     # was assigned, then unplugged

	func _init(i: int) -> void:
		index = i

var _slots: Array[PlayerSlot] = []
var _device_to_player: Dictionary = {} # joy_id -> player_index

# Cache: (player_index, base_action) -> StringName("pX_base")
var _action_cache: Array[Dictionary] = []

# Rebind state
var _rebind_active := false
var _rebind_player := -1
var _rebind_action: StringName = &""
var _rebind_allow_keyboard := true
var _rebind_allow_joypad := true
#endregion


#region Lifecycle
func _ready() -> void:
	_slots.clear()
	_action_cache.clear()
	_device_to_player.clear()

	for i in MAX_PLAYERS:
		_slots.append(PlayerSlot.new(i))
		_action_cache.append({})

	#_base_actions = _discover_base_actions()
	#_ensure_prefixed_actions_exist()
	
	_setup()
	
	_connect_joy_signals()
	_auto_assign_existing_joypads()
	#_setup_default_assignments()
	
	#dump_localinput_state(false, false)
	#pretty_print_input_map()

	pass
#endregion


#region Base Action Discovery
func _setup():
	_base_actions = InputMap.get_actions()
	var actions_to_copy:Array[StringName] = []
	
	for _action in _base_actions:
		if _is_excluded_action(_action):
			continue
		else:
			actions_to_copy.append(_action)
			
		
	#print(_base_actions)
	
	for player_index in range(1,MAX_PLAYERS + 1):
		var prefixed_actions:Array[StringName] = actions_to_copy.duplicate()
		#print("\n")
		for i in range(prefixed_actions.size()):
			prefixed_actions[i] = "p%d_%s" % [player_index, prefixed_actions[i]]
			#prints(prefixed_actions[i])
			var orig_action_name := actions_to_copy[i] 
			
			InputMap.add_action(prefixed_actions[i], InputMap.action_get_deadzone(orig_action_name))
			var device_id:int = player_index - 1
			var event:InputEvent = null
			var events:= InputMap.action_get_events(orig_action_name)
			
			for e in events:
				if e is InputEventKey and player_index == 1:
					event = e.duplicate()
					event.device = device_id
					event.keycode = e.keycode
					
				elif e is InputEventMouseButton and player_index == 1:
					event = e.duplicate()
					event.device = device_id
					event.button_index = e.button_index
					
				elif e is InputEventMouseMotion and player_index == 1:
					event = e.duplicate()
					event.device = device_id
					
				elif e is InputEventJoypadButton:
					event = e.duplicate()
					event.device = device_id
					event.button_index = e.button_index
					
				elif e is InputEventJoypadMotion:
					event = e.duplicate()
					event.device = device_id
					event.axis = e.axis
					
				if event is InputEvent and InputMap.has_action(prefixed_actions[i]):
					InputMap.action_add_event(prefixed_actions[i], event)
				#prints(prefixed_action, _describe_event(event))
					
				
	for _action in actions_to_copy:
		if InputMap.has_action(_action):
			InputMap.erase_action(_action)
	
	#pretty_print_input_map()
	#print(InputMap.get_actions())
	
func _discover_base_actions() -> Array[StringName]:
	if BASE_ACTIONS_OVERRIDE.size() > 0:
		var copy := BASE_ACTIONS_OVERRIDE.duplicate()
		copy.sort_custom(func(a, b): return String(a) < String(b))
		return copy

	var out: Array[StringName] = []
	var actions: Array[StringName] = InputMap.get_actions()

	for a in actions:
		var s := String(a)

		# Skip already player-prefixed actions like p1_jump, p12_attack, etc.
		if _is_player_prefixed_action(s):
			continue

		# Skip excluded exact names
		if EXCLUDE_ACTIONS.has(s):
			continue

		# Skip excluded prefixes (ui_ by default)
		var bad := false
		for p in EXCLUDE_PREFIXES:
			if s.begins_with(p):
				bad = true
				break
		if bad:
			continue

		out.append(a)

	out.sort_custom(func(x, y): return String(x) < String(y))
	return out


func _is_player_prefixed_action(s: String) -> bool:
	# Matches: p<digits>_  e.g. p1_, p2_, p12_
	if s.length() < 3:
		return false
	if not s.begins_with("p"):
		return false

	var i := 1
	# must have at least one digit
	if i >= s.length():
		return false

	var ch := s.substr(i, 1)
	if ch < "0" or ch > "9":
		return false

	while i < s.length():
		ch = s.substr(i, 1)
		if ch < "0" or ch > "9":
			break
		i += 1

	return i < s.length() and s.substr(i, 1) == "_"
#endregion


#region Public API
func action(player_index: int, base_action: StringName) -> StringName:
	return _prefixed_action(player_index, base_action)

func is_action_pressed(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_pressed(_prefixed_action(player_index, base_action))

func is_action_just_pressed(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_just_pressed(_prefixed_action(player_index, base_action))

func is_action_just_released(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_just_released(_prefixed_action(player_index, base_action))

func get_vector(player_index: int,
	left: StringName, right: StringName,
	up: StringName, down: StringName,
	deadzone := 0.2) -> Vector2:
	return Input.get_vector(
		_prefixed_action(player_index, left),
		_prefixed_action(player_index, right),
		_prefixed_action(player_index, up),
		_prefixed_action(player_index, down),
		deadzone
	)

func slot_is_active(player_index: int) -> bool:
	return _valid_player(player_index) and _slots[player_index].active and not _slots[player_index].device_lost

func get_slot_info(player_index: int) -> Dictionary:
	if not _valid_player(player_index):
		return {}
	var s := _slots[player_index]
	return {
		"active": s.active,
		"device_type": s.device_type,
		"joy_id": s.joy_id,
		"joy_guid": s.joy_guid,
		"keyboard_layout": s.keyboard_layout,
		"device_lost": s.device_lost
	}
#endregion


#region Player Assignment
func assign_keyboard(player_index: int, layout: KeyboardLayout = KeyboardLayout.WASD) -> void:
	if not _valid_player(player_index): return
	_unassign_if_needed(player_index)

	var s := _slots[player_index]
	s.device_type = DeviceType.KEYBOARD
	s.keyboard_layout = layout
	s.joy_id = -1
	s.joy_guid = ""
	s.active = true
	s.device_lost = false

	_apply_keyboard_layout(player_index, layout)
	emit_signal("player_assigned", player_index)

func assign_joypad(player_index: int, joy_id: int) -> void:
	if not _valid_player(player_index): return
	if joy_id < 0: return

	# Ensure one joypad controls only one player slot.
	if _device_to_player.has(joy_id):
		var other := int(_device_to_player[joy_id])
		if other != player_index:
			unassign_player(other)

	_unassign_if_needed(player_index)

	var s := _slots[player_index]
	s.device_type = DeviceType.JOYPAD
	s.joy_id = joy_id
	s.joy_guid = Input.get_joy_guid(joy_id)
	s.active = true
	s.device_lost = false

	_device_to_player[joy_id] = player_index
	_apply_gamepad_layout(player_index, joy_id)
	emit_signal("player_assigned", player_index)

func unassign_player(player_index: int) -> void:
	if not _valid_player(player_index): return
	var s := _slots[player_index]
	if s.device_type == DeviceType.JOYPAD and s.joy_id >= 0:
		_device_to_player.erase(s.joy_id)

	s.device_type = DeviceType.NONE
	s.joy_id = -1
	s.joy_guid = ""
	s.active = false
	s.device_lost = false
	_clear_bindings(player_index)
	emit_signal("player_unassigned", player_index)

# Simple “join” helper: assigns an unassigned joypad to first free slot.
func assign_next_free_slot_for_joypad(joy_id: int) -> int:
	for i in MAX_PLAYERS:
		if not _slots[i].active:
			assign_joypad(i, joy_id)
			return i
	return -1

func refresh_from_inputmap() -> void:
	_base_actions = _discover_base_actions()
	_ensure_prefixed_actions_exist()
#endregion


#region Remapping
func begin_rebind(player_index: int, base_action: StringName, allow_keyboard := true, allow_joypad := true) -> void:
	if not _valid_player(player_index): return
	_rebind_active = true
	_rebind_player = player_index
	_rebind_action = base_action
	_rebind_allow_keyboard = allow_keyboard
	_rebind_allow_joypad = allow_joypad

func cancel_rebind() -> void:
	_rebind_active = false
	_rebind_player = -1
	_rebind_action = &""

func set_binding_replace(player_index: int, base_action: StringName, event: InputEvent) -> void:
	if not _valid_player(player_index): return
	if event == null: return

	var action_name := _prefixed_action(player_index, base_action)
	var fixed := _normalize_event_for_player(player_index, event)
	if fixed == null:
		return

	# Only replace the same *kind* of binding.
	if _is_keyboard_event(fixed):
		_erase_events_matching(action_name, Callable(self, "_is_keyboard_event"))
	else:
		_erase_events_matching(action_name, Callable(self, "_is_joy_event"))

	InputMap.action_add_event(action_name, fixed)
	emit_signal("bindings_changed", player_index, base_action)

func add_binding(player_index: int, base_action: StringName, event: InputEvent) -> void:
	if not _valid_player(player_index): return
	if event == null: return

	var action_name := _prefixed_action(player_index, base_action)
	var fixed := _normalize_event_for_player(player_index, event)
	if fixed == null:
		return

	InputMap.action_add_event(action_name, fixed)
	emit_signal("bindings_changed", player_index, base_action)

func clear_bindings_for_action(player_index: int, base_action: StringName) -> void:
	if not _valid_player(player_index): return
	InputMap.action_erase_events(_prefixed_action(player_index, base_action))
	emit_signal("bindings_changed", player_index, base_action)

func get_events(player_index: int, base_action: StringName) -> Array[InputEvent]:
	if not _valid_player(player_index): return []
	return InputMap.action_get_events(_prefixed_action(player_index, base_action))
#endregion


#region Save / Load Bindings
# Save/Load bindings (ConfigFile friendly)
func export_player_bindings(player_index: int) -> Dictionary:
	if not _valid_player(player_index): return {}
	var out := {}
	for a in _base_actions:
		var events := InputMap.action_get_events(_prefixed_action(player_index, a))
		var arr: Array = []
		for e in events:
			arr.append(_event_to_dict(e))
		out[String(a)] = arr
	return out

func import_player_bindings(player_index: int, data: Dictionary) -> void:
	if not _valid_player(player_index): return
	for a in _base_actions:
		var key := String(a)
		if not data.has(key): continue
		var action_name := _prefixed_action(player_index, a)
		InputMap.action_erase_events(action_name)
		for ed in data[key]:
			var ev := _event_from_dict(ed)
			if ev != null:
				var fixed := _normalize_event_for_player(player_index, ev)
				if fixed != null:
					InputMap.action_add_event(action_name, fixed)
		emit_signal("bindings_changed", player_index, a)

# Saves bindings for all players into ONE file.
func save_all_players(path: String = "user://input.cfg") -> void:
	var cfg := ConfigFile.new()

	# Load existing so we don't wipe other unrelated settings in the same file.
	cfg.load(path)

	for player_index in MAX_PLAYERS:
		var section := "p%s" % player_index
		cfg.set_value(section, "bindings", export_player_bindings(player_index))

	cfg.save(path)


func load_all_players(path: String = "user://input.cfg") -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for player_index in MAX_PLAYERS:
		var section := "p%s" % player_index
		var data = cfg.get_value(section, "bindings", null)
		if data == null:
			continue
		import_player_bindings(player_index, data)

func save_config(player_index: int, path: String = "user://input.cfg") -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("p%s" % player_index, "bindings", export_player_bindings(player_index))
	cfg.save(path)

func load_config(player_index: int, path: String = "user://input.cfg") -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	import_player_bindings(player_index, cfg.get_value("p%s" % player_index, "bindings", {}))
#endregion


#region Input Hook
func _unhandled_input(event: InputEvent) -> void:
	if _rebind_active:
		_handle_rebind_capture(event)
		return

	# Optional: hot-join on any unassigned joypad pressing Start or A.
	if event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		if JOIN_JOY_BUTTONS.has(jb.button_index) and not _device_to_player.has(jb.device):
			assign_next_free_slot_for_joypad(jb.device)
#endregion


#region Core Internals
func _valid_player(i: int) -> bool:
	return i >= 0 and i < MAX_PLAYERS

func _prefixed_action(player_index: int, base_action: StringName) -> StringName:
	var cache := _action_cache[player_index]
	if cache.has(base_action):
		return cache[base_action]
	
	var action_name := StringName("p%d_%s" % [player_index + 1, String(base_action)])
	cache[base_action] = action_name
	return action_name

func _ensure_prefixed_actions_exist() -> void:
	for p in MAX_PLAYERS:
		for a in _base_actions:
			var an := _prefixed_action(p, a)
			if not InputMap.has_action(an):
				var dz := 0.5
				if ACTION_DEADZONES.has(a):
					dz = float(ACTION_DEADZONES[a])
				InputMap.add_action(an, dz)

func _connect_joy_signals() -> void:
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _auto_assign_existing_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var pad_i := 0
	for p in MAX_PLAYERS:
		if pad_i >= pads.size(): break
		# Only auto-assign if slot unused.
		if not _slots[p].active:
			assign_joypad(p, int(pads[pad_i]))
			pad_i += 1

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_try_restore_lost_slot(device)
	else:
		_mark_slot_lost(device)

func _mark_slot_lost(device: int) -> void:
	if not _device_to_player.has(device):
		return
	var p := int(_device_to_player[device])
	var s := _slots[p]
	s.device_lost = true
	# Keep guid so we can restore if it comes back.
	_device_to_player.erase(device)
	s.joy_id = -1
	emit_signal("player_device_lost", p)

func _try_restore_lost_slot(new_device: int) -> void:
	var guid := Input.get_joy_guid(new_device)
	# If this device is already assigned, nothing to do.
	if _device_to_player.has(new_device):
		return

	# Restore to slot with matching GUID.
	for p in MAX_PLAYERS:
		var s := _slots[p]
		if s.active and s.device_type == DeviceType.JOYPAD and s.device_lost and s.joy_guid == guid:
			s.device_lost = false
			s.joy_id = new_device
			_device_to_player[new_device] = p
			_apply_gamepad_layout(p, new_device)
			emit_signal("player_device_restored", p)
			return

	# Otherwise leave unassigned, player can hot-join.

func _unassign_if_needed(player_index: int) -> void:
	# If slot was active, clear previous mapping.
	var s := _slots[player_index]
	if not s.active:
		return
	if s.device_type == DeviceType.JOYPAD and s.joy_id >= 0:
		_device_to_player.erase(s.joy_id)

func _clear_bindings(player_index: int) -> void:
	for a in _base_actions:
		InputMap.action_erase_events(_prefixed_action(player_index, a))

func _setup_default_assignments() -> void:
	# Always give P1 keyboard defaults first
	assign_keyboard(0, KeyboardLayout.WASD)

	# Then layer gamepads on top:
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		# P1 also gets the first gamepad (hybrid)
		assign_joypad(0, int(pads[0]))

	# Remaining pads go to remaining slots
	for player_index in range(1, MAX_PLAYERS):
		var pad_index := player_index
		if pad_index >= pads.size():
			break
		assign_joypad(player_index, int(pads[pad_index]))

#endregion


#region Rebind Internals
func _normalize_event_for_player(player_index: int, event: InputEvent) -> InputEvent:
	var s := _slots[player_index]
	var e := event.duplicate() as InputEvent
	if e == null:
		return null

	# For gamepads, lock the device id so only that controller triggers these actions.
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		if not _rebind_allow_joypad and _rebind_active:
			return null
		if s.device_type != DeviceType.JOYPAD:
			# If the slot is keyboard-only, reject joypad events.
			return null
		e.device = s.joy_id

		# For motion, normalize axis_value to sign threshold so it behaves like an action.
		if e is InputEventJoypadMotion:
			var jm := e as InputEventJoypadMotion
			if abs(jm.axis_value) < 0.5:
				return null
			jm.axis_value = sign(jm.axis_value) # -1 or 1

	else:
		# Keyboard/mouse events
		if not _rebind_allow_keyboard and _rebind_active:
			return null
		# Slot must be keyboard to accept keyboard/mouse events.
		if s.device_type != DeviceType.KEYBOARD:
			return null

	return e

func _handle_rebind_capture(event: InputEvent) -> void:
	# Ignore noise
	if event is InputEventMouseMotion:
		return

	# Only capture "press" style events
	var accept := false
	if event is InputEventKey:
		var k := event as InputEventKey
		accept = k.pressed and not k.echo
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		accept = mb.pressed
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		accept = jb.pressed
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		accept = abs(jm.axis_value) >= 0.7

	if not accept:
		return

	set_binding_replace(_rebind_player, _rebind_action, event)
	cancel_rebind()
#endregion


#region Default Layouts
func _apply_keyboard_layout(player_index: int, layout: KeyboardLayout) -> void:
	# Remove only keyboard events for this player's actions, keep joypad events.
	for a in _base_actions:
		_erase_events_matching(_prefixed_action(player_index, a), Callable(self, "_is_keyboard_event"))

	match layout:
		KeyboardLayout.WASD:
			_bind_key(player_index, &"move_forward", KEY_W as Key)
			_bind_key(player_index, &"move_back",    KEY_S as Key)
			_bind_key(player_index, &"move_left",    KEY_A as Key)
			_bind_key(player_index, &"move_right",   KEY_D as Key)
			_bind_key(player_index, &"start",        KEY_ESCAPE as Key)
			_bind_key(player_index, &"select",       KEY_BACKSPACE as Key)
			_bind_key(player_index, &"confirm",      KEY_ENTER as Key)
			_bind_key(player_index, &"cancel",       KEY_BACKSPACE as Key)
			# add your other actions here (jump/attack/etc) if they exist in your map

		KeyboardLayout.ARROWS:
			_bind_key(player_index, &"move_left",  KEY_LEFT as Key)
			_bind_key(player_index, &"move_right", KEY_RIGHT as Key)
			_bind_key(player_index, &"move_up",    KEY_UP as Key)
			_bind_key(player_index, &"move_down",  KEY_DOWN as Key)
			# etc...

func _apply_gamepad_layout(player_index: int, joy_id: int) -> void:
	# Remove only joypad events for this player's actions, keep keyboard events.
	#for a in _base_actions:
		#_erase_events_matching(_prefixed_action(player_index, a), Callable(self, "_is_joy_event"))

	# Bind whatever actions exist in your project’s map.
	_bind_axis(player_index, &"move_left",    JOY_AXIS_LEFT_X, -1.0, joy_id)
	_bind_axis(player_index, &"move_right",   JOY_AXIS_LEFT_X,  1.0, joy_id)
	_bind_axis(player_index, &"move_forward", JOY_AXIS_LEFT_Y, 1.0, joy_id)
	_bind_axis(player_index, &"move_back",    JOY_AXIS_LEFT_Y, -1.0, joy_id)
	_bind_axis(player_index, &"move_up",      JOY_AXIS_RIGHT_Y, -1.0, joy_id)
	_bind_axis(player_index, &"move_down",    JOY_AXIS_RIGHT_Y,  1.0, joy_id)

	# These only work if your base actions include them (they do: pause/confirm/cancel/action).
	_bind_button(player_index, &"start",   JOY_BUTTON_START, joy_id)
	_bind_button(player_index, &"select",   JOY_BUTTON_BACK, joy_id)
	_bind_button(player_index, &"confirm", JOY_BUTTON_A,     joy_id)
	_bind_button(player_index, &"cancel",  JOY_BUTTON_B,     joy_id)
	_bind_button(player_index, &"action",  JOY_BUTTON_X,     joy_id)
#endregion


#region Binding Helpers
func _bind_key(player_index: int, base_action: StringName, keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	InputMap.action_add_event(_prefixed_action(player_index, base_action), e)

func _bind_button(player_index: int, base_action: StringName, button: JoyButton, joy_id: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = joy_id
	e.button_index = button
	InputMap.action_add_event(_prefixed_action(player_index, base_action), e)

func _bind_axis(player_index: int, base_action: StringName, axis: JoyAxis, axis_value: float, joy_id: int) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = joy_id
	e.axis = axis
	e.axis_value = axis_value
	InputMap.action_add_event(_prefixed_action(player_index, base_action), e)
#endregion


#region Serialization
func _event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"t":"key", "kc": int(k.keycode)}
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		return {"t":"mouse", "b": int(mb.button_index)}
	if e is InputEventJoypadButton:
		var jb := e as InputEventJoypadButton
		return {"t":"jb", "btn": int(jb.button_index)}
	if e is InputEventJoypadMotion:
		var jm := e as InputEventJoypadMotion
		return {"t":"jm", "ax": int(jm.axis), "v": float(sign(jm.axis_value))}
	return {"t":"unknown"}

func _event_from_dict(d: Dictionary) -> InputEvent:
	if not d.has("t"): return null
	match String(d["t"]):
		"key":
			var k := InputEventKey.new()
			k.keycode = int(d.get("kc", 0)) as Key
			return k
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("b", MOUSE_BUTTON_LEFT)) as MouseButton
			return mb
		"jb":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("btn", JOY_BUTTON_A)) as JoyButton
			return jb
		"jm":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("ax", JOY_AXIS_LEFT_X)) as JoyAxis
			jm.axis_value = float(d.get("v", 1.0))
			return jm
	return null
#endregion


#region Event-Type Filtering Helpers
static func _is_keyboard_event(e: InputEvent) -> bool:
	return e is InputEventKey or e is InputEventMouseButton

static func _is_joy_event(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion

func _erase_events_matching(action_name: StringName, predicate: Callable) -> void:
	var events := InputMap.action_get_events(action_name)
	for e in events:
		if predicate.call(e):
			InputMap.action_erase_event(action_name, e)
#endregion


#region Debug / Dumping (Enhanced)

func dump_localinput_state(include_base := true, include_prefixed := true) -> void:
	print("\n=== LocalInput State ===")
	print("Base actions count: ", _base_actions.size())
	print("Slots:")

	for i in MAX_PLAYERS:
		var s := _slots[i]
		var dtype := "NONE"
		if s.device_type == DeviceType.KEYBOARD: dtype = "KEYBOARD"
		elif s.device_type == DeviceType.JOYPAD: dtype = "JOYPAD"

		print("  P", i + 1,
			" active=", s.active,
			" type=", dtype,
			" joy_id=", s.joy_id,
			" lost=", s.device_lost,
			" guid=", s.joy_guid,
			" kbd_layout=", int(s.keyboard_layout)
		)

	if include_base:
		print("\n--- Base Actions (unprefixed) ---")
		for a in _base_actions:
			print("\n", a)
			for e in InputMap.action_get_events(a):
				print("  - ", _describe_event(e))

	if include_prefixed:
		for p in MAX_PLAYERS:
			print("\n--- Prefixed Actions for P", p + 1, " ---")
			for a in _base_actions:
				var pa := _prefixed_action(p, a)
				print("\n", pa)
				for e in InputMap.action_get_events(pa):
					print("  - ", _describe_event(e))

	print("\n=== End LocalInput State ===\n")


func dump_action_events(action_name: StringName) -> String:
	var text:String = "[%s]\n" % [action_name.to_upper()]
	if not InputMap.has_action(action_name):
		text += "\t" + "  (missing action)"
	else:
		var events := InputMap.action_get_events(action_name)
		if events.is_empty():
			text += "\t" + "  (no events bound)"
		else:
			for e in events:
				text += "--" + _describe_event(e)  + "\n"
	return text


func _describe_event(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		return "Key " + OS.get_keycode_string(k.keycode)
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		return "MouseBtn %d" % mb.button_index
	if e is InputEventJoypadButton:
		var jb := e as InputEventJoypadButton
		return "JoyBtn dev=%d btn=%d" % [jb.device, jb.button_index]
	if e is InputEventJoypadMotion:
		var jm := e as InputEventJoypadMotion
		return "JoyAxis dev=%d ax=%d v=%s" % [jm.device, jm.axis, str(jm.axis_value)]
	return "e.get_class()"


func pretty_print_input_map():
	var text:String = ""
	for i in range(1,MAX_PLAYERS+1):
		text += "============[P%d Inputs]============\n" % i
		for a:StringName in InputMap.get_actions():
			if not _is_excluded_action(a) and a.begins_with("p%d"%i):
				text += dump_action_events(a) + "\n"
		text += "\n\n"
	
	print(text)


func _is_excluded_action(action_name:StringName) -> bool:
	if action_name in EXCLUDE_ACTIONS:
		return true
	else:
		for prefix in EXCLUDE_PREFIXES:
			if action_name.begins_with(prefix):
				return true
				
	return false


#endregion
