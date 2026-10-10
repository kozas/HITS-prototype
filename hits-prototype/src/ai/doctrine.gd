extends RefCounted
## How each army fights when its officers are left to choose: one small table
## per nation, read by the brains when an order leaves a preference to AUTO.
##
## French (1808+): attack in column of divisions behind a voltigeur screen; once
##   engaged, a first volley and then fire at will (feu de deux rangs), which is
##   what French infantry actually did whatever the regulations said.
## British: fight in line; a volley, then fire by platoons (half-companies)
##   rolling along the line; volley and charge when the attacker falters.

const Formation = preload("res://src/formation.gd")
const T := Formation.Type
const F := Formation.Fire

const ARMIES := [
	{
		"attack_ftype": T.COLUMN,
		"defend_ftype": T.LINE,
		"opening_volley": true,
		"fire": F.AT_WILL,
		"skirmish_in_attack": true,
		"skirmish_in_defence": true,
	},
	{
		"attack_ftype": T.LINE,
		"defend_ftype": T.LINE,
		"opening_volley": true,
		"fire": F.PLATOON,
		"skirmish_in_attack": true,
		"skirmish_in_defence": true,
	},
]


static func of(army: int) -> Dictionary:
	return ARMIES[army]
