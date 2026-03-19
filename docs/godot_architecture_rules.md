# Godot Architecture Rules

This document defines the architectural rules for implementing systems in Godot.

AI assistants must follow these rules when generating code.

The goal is to ensure projects remain **modular, maintainable, and scalable**.

---

# Core Principles

Godot projects should prioritize:

- modular scripts
- data-driven systems
- small focused nodes
- reusable components

Avoid large monolithic scripts.

---

# Preferred Project Structure


project/
├── docs/
│ ├── game_vision.md
│ ├── mechanics.md
│ ├── architecture.md
│ ├── findings.md
│ └── progress_log.md
│
├── systems/
│ ├── ai/
│ ├── economy/
│ ├── world/
│ └── player/
│
├── entities/
│ ├── player/
│ ├── enemies/
│ └── npc/
│
├── environments/
│
├── ui/
│
├── data/
│
├── assets/
│
└── scenes/


---

# Node Responsibility Rule

Each node should have a **single responsibility**.

Example:

Bad:


Player.gd


Handles:

- input
- combat
- health
- UI
- inventory

Good:


PlayerController.gd
PlayerHealth.gd
PlayerCombat.gd
PlayerInventory.gd


---

# System Scripts vs Entity Scripts

Separate **systems** from **entities**.

Systems manage rules.

Entities represent actors.

Example:


systems/pollination_system.gd
entities/plant/plant.gd


The plant should not implement the full pollination logic.

---

# Data Driven Design

Game balance values should be stored in **Resources**.

Example:


PlantSpecies.tres
WeaponStats.tres
EnemyStats.tres


Benefits:

- easier balancing
- designer friendly
- reusable assets

---

# Signals Over Tight Coupling

Use signals to communicate between systems.

Example:


signal plant_pollinated
signal enemy_defeated
signal resource_collected


This prevents hard dependencies between scripts.

---

# Avoid Global State

Do not rely on excessive global variables.

If shared systems are required use:


Autoload singletons


Examples:


GameManager
SaveSystem
AudioManager


Use sparingly.

---

# Debugging Tools

All systems should support debugging.

Example tools:

- debug overlays
- logging
- in-editor testing

Example debug command:


print("Pollination success:", success_rate)


---

# Scene Design Rules

Scenes should represent **logical objects**.

Example:


Player.tscn
Bee.tscn
Plant.tscn
Hive.tscn


Avoid overly large scenes containing unrelated functionality.

---

# Performance Rules

Avoid:

- unnecessary `_process()` loops
- heavy per-frame allocations
- repeated scene instantiation

Prefer:

- event driven logic
- object pooling
- cached references

---

# Script Size Guideline

If a script exceeds ~400 lines, it should likely be split into smaller components.

---

# System Testing

When building new systems:

1. create a minimal test scene
2. validate system behavior
3. integrate into the main game

Example:


test_pollination_scene.tscn


---

# AI Behavior Rules

When generating Godot code:

- prefer composition over inheritance
- keep scripts small and focused
- separate systems from entities
- expose tunable variables with `@export`
- write readable and maintainable code

---

# End of Document