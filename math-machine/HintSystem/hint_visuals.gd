class_name HintVisuals
extends RefCounted

## Shared color/timing constants for hint visuals (connection glow, store
## ghost value) so every hint reads as the same visual language.

const COLOR: Color = Color(1.0, 0.83, 0.2, 1.0)
const BORDER_COLOR: Color = Color(0.6, 0.42, 0.0, 1.0)
const DIM_ALPHA: float = 0.35
const GLOW_ALPHA: float = 1.0
const PULSE_DURATION: float = 0.6
const STORE_VALUE_PULSE_COUNT: int = 5

## When true, every hint inside a latch phase pulses that phase's goal value
## on its store, not just the hint for the wire that causes the latch.
## Set false to fall back to latch-connection-only.
const SHOW_PHASE_GOAL_VALUE: bool = true
