extends RefCounted
## An order is intent passed down the chain of command: what to do (kind),
## where (objective), how hard (intensity) and any preferences the issuer cares
## to state. Everything left AUTO is the recipient's to decide, the front it
## takes included. The recipient may be any Command, from a corps to a battalion.
##
## Lifecycle: WRITTEN -> RIDING (courier) -> PREPARING (staff work) -> EXECUTING
## -> COMPLETE | SUPERSEDED | FAILED (the attack broke), or LOST with its courier.
## Only the sim changes it.

const Objective = preload("res://src/objective.gd")

## REJOIN: a detached unit goes back under its own commander.
enum Kind { MOVE, ATTACK, HOLD, REJOIN }
enum Intensity { PROBE, PRESS, ALL_OUT }
enum Status { WRITTEN, RIDING, PREPARING, EXECUTING, COMPLETE, SUPERSEDED, LOST, FAILED }
const KIND_NAMES := ["Move", "Attack", "Hold", "Rejoin"]
const INTENSITY_NAMES := ["Probe", "Press", "All-out"]
const STATUS_NAMES := ["written", "riding", "preparing", "executing", "complete", "superseded", "lost", "failed"]
const AUTO := -1

var id := 0
var army := 0
var recipient = null     # Command
var issuer = null        # Command; null when the general (the player) wrote it
var parent_order = null  # the order this one was written to carry out
var children: Array = []
var kind: int = Kind.MOVE
var objective = null     # Objective
var intensity: int = Intensity.PRESS
var ftype: int = AUTO       # preferred formation (Formation.Type)
var fire_mode: int = AUTO   # preferred fire (Formation.Fire)
var skirmishers: int = AUTO # 1 out, 0 in
var status: int = Status.WRITTEN
var issued := 0.0
var delivered := -1.0
var exec_at := -1.0
var finished := -1.0
var facing = null  # chosen by the recipient when it acts (Orientation)
var facing_reason := -1
## Written by a superior who skipped the recipient's own commander: the
## recipient is detached from its parent until the order is done.
var detached := false


func dest() -> Vector2:
	return objective.anchor()


func by_player() -> bool:
	return issuer == null


func is_active() -> bool:
	return status == Status.RIDING or status == Status.PREPARING or status == Status.EXECUTING


func status_name() -> String:
	return STATUS_NAMES[status]
