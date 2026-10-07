extends Node
## Autoload: carries the scenario chosen in the main menu into battle.tscn.

enum Scenario { BENCHMARK, BRIGADE_CONTACT }

const BATTLE_SCENE := "res://battle.tscn"
const MENU_SCENE := "res://menu.tscn"

var scenario: int = Scenario.BENCHMARK


func start(s: int) -> void:
	scenario = s
	get_tree().change_scene_to_file(BATTLE_SCENE)


func to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
