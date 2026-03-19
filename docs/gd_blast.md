🎮 G.D.B.L.A.S.T. Game Development Protocol
Purpose

This document defines the Game Development B.L.A.S.T. protocol, a deterministic framework for designing and building games with AI collaboration.

The goal is to ensure AI behaves as a structured game development partner, not an uncontrolled idea generator.

The protocol prioritizes:

Playable loops over ideas

Systems over features

Deterministic architecture over improvisation

Iterative testing over speculative design

🧠 Core Philosophy

Games should be built in the following order:

Core Loop
→ Systems
→ Mechanics
→ Content
→ Polish

Feature stacking before establishing a core loop leads to unstable projects.

The AI must always guide development toward a playable vertical slice first.

🚀 The G.D.B.L.A.S.T. Pipeline

The Game Development BLAST protocol consists of five phases:

Blueprint
Link
Architect
Stylize
Trigger

Each phase has strict responsibilities.

Phase 1 — B: Blueprint (Game Vision)

The Blueprint phase defines the foundation of the game.

Before suggesting mechanics or writing code, the AI must ask discovery questions.

Discovery Questions

North Star Experience

What experience should the player have?

Examples:

feel like a hacker sabotaging machines

build a thriving bee colony

survive a haunted house

Core Gameplay Loop

Define the 30-second player loop.

Example:

Explore
Collect resources
Return to base
Upgrade
Expand territory

The game must be fun at this level before adding complexity.

Primary Systems

Identify the systems required to support the loop.

Examples:

Movement
AI behavior
Resource economy
Crafting
Procedural generation
Combat
Genetics

Systems must be modular and independent.

Feedback Systems

Define how the game communicates state.

Examples:

Sound effects
Particles
Animation
Camera movement
UI indicators
Color changes

Every player action must produce feedback.

Constraints

Define limitations.

Examples:

Engine
Platform
Art style
Performance targets
Development timeline
Team size

Constraints guide design decisions.

Phase 2 — L: Link (Technical Foundations)

Before implementing gameplay systems, verify that core technical foundations exist.

Required foundations:

Input system
Camera controller
Entity spawning
Basic UI framework
Debug tools
Save/load system

These systems form the technical backbone of the game.

Gameplay mechanics should not be implemented until these foundations are stable.

Phase 3 — A: Architect (Game Systems Architecture)

Game systems should be implemented using a three-layer architecture.

Layer 1 — Design Architecture

Markdown documents describing gameplay systems.

Example:

architecture/combat_system.md
architecture/economy_system.md
architecture/genetics_system.md

Each system document must define:

Purpose
Inputs
Outputs
Rules
Edge cases
Tunable variables

Rule:

If gameplay logic changes, the architecture document must be updated before code changes.

Layer 2 — Game Logic

This layer coordinates gameplay systems.

Responsibilities:

Game state management
Mission logic
Event routing
World simulation

Example scripts:

game_controller.gd
world_manager.gd
mission_manager.gd
Layer 3 — Deterministic Systems

This layer contains the actual gameplay mechanics.

Examples:

systems/ai_behavior.gd
systems/resource_economy.gd
systems/plant_growth.gd
systems/combat_system.gd

Each system must be:

Modular
Testable
Reusable
Data-driven

Avoid monolithic scripts.

Phase 4 — S: Stylize (Game Feel & Presentation)

Once gameplay mechanics function correctly, focus on improving game feel.

Areas to refine:

Animation timing
Particles
Sound design
Camera shake
Hit stop
UI clarity
Interaction feedback

Game feel transforms systems into player experience.

Phase 5 — T: Trigger (Playtesting & Deployment)

Once the core loop and systems are implemented, deploy the game for testing.

Testing methods include:

Internal playtests
Game jam submissions
itch.io builds
Steam demos
Closed beta tests

Each playtest should produce feedback stored in documentation.

🔁 Iteration Protocol

When bugs or design issues occur:

Analyze

Reproduce the issue and identify the root cause.

Patch

Modify the relevant system.

Test

Verify that the fix works and does not break system interactions.

Document

Update architecture or findings documentation to prevent repeated mistakes.

📂 Recommended Project Documentation

Projects should maintain the following documentation:

docs/
 ├── game_vision.md
 ├── mechanics.md
 ├── architecture.md
 ├── findings.md
 └── progress_log.md
game_vision.md

Defines:

Player fantasy
Target emotion
Genre
Platform
Constraints
mechanics.md

Defines gameplay mechanics using:

Mechanic Name
Player Action
Game Response
Feedback
Failure Conditions
System Interactions
architecture.md

Defines:

Scene structure
System boundaries
Data models
Save/load systems
Event architecture
findings.md

Stores discoveries such as:

Engine limitations
Performance insights
Design discoveries
Playtest feedback
progress_log.md

Tracks development progress:

Date
Feature
Result
Bugs
Next Step
🛠 Operating Principles
1. Loop First

Always build the core gameplay loop before adding content.

Avoid starting with:

Story
Menus
Cosmetics
Levels

Focus on gameplay first.

2. Systems Before Content

Systems generate infinite gameplay.

Content alone creates limited experiences.

3. Small Vertical Slices

Develop small playable slices of the game rather than building large systems all at once.

Example slice:

movement → combat → enemy → feedback
4. Data-Driven Design

Where possible:

Store gameplay values in data resources
Keep systems reusable
Allow rapid tuning
Completion Criteria

A prototype is considered successful when:

The core gameplay loop is playable
Systems interact correctly
Player actions produce clear feedback
External playtesting is possible
AI Behavior Rules

When assisting with development:

Ask discovery questions before suggesting mechanics

Avoid generating excessive feature lists

Define systems using inputs, outputs, and rules

Prefer modular architecture

Prioritize player experience

Optimize for iteration speed

End of Protocol