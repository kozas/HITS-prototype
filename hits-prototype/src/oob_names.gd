extends RefCounted
## Names for the order of battle: unit titles, numbering and commanders.
## Army 0 is French, army 1 Anglo-Allied. Commanders are invented.

## Generals are unique within an army while the list lasts (a full army needs
## about 66); battalion commanders may share a name.
const SURNAMES := [
	["Durand", "Lefebvre", "Moreau", "Girard", "Bonnet", "Lambert", "Fontaine", "Rousseau",
	"Vincent", "Mercier", "Blanchard", "Guérin", "Boyer", "Garnier", "Chevalier", "Faure",
	"Gauthier", "Perrin", "Robin", "Clément", "Morin", "Roussel", "Mathieu", "Masson",
	"Marchand", "Duval", "Lemoine", "Brunet", "Picard", "Renard", "Barbier", "Arnaud",
	"Martel", "Leclerc", "Fabre", "Aubert", "Lacroix", "Royer", "Hubert", "Carpentier",
	"Bertrand", "Caron", "Collin", "Dumont", "Fournier", "Gaillard", "Huet", "Jacquet",
	"Joly", "Laurent", "Leroux", "Maillard", "Meunier", "Noël", "Olivier", "Paris",
	"Poulain", "Prévost", "Rey", "Rolland", "Sanchez", "Tessier", "Thomas", "Vidal",
	"Baron", "Besnard", "Charpentier", "Delmas", "Ferrand", "Gilbert", "Hamon", "Lebrun",
	"Marty", "Pelletier", "Raymond", "Simon", "Texier", "Vasseur", "Weber", "Bouvier"],
	["Ashworth", "Bradshaw", "Corbett", "Denham", "Ellerby", "Fenwick", "Gresham", "Hartley",
	"Ingram", "Jessop", "Kendall", "Langley", "Merrick", "Norbury", "Oakley", "Pemberton",
	"Radcliffe", "Selwyn", "Thornton", "Underwood", "Whitmore", "Yardley", "Ainsworth",
	"Barlow", "Cartwright", "Dunmore", "Everard", "Fairbairn", "Garside", "Holloway",
	"Kirkby", "Lockwood", "Marsden", "Netherby", "Ormerod", "Prescott", "Ridley", "Sutcliffe",
	"Appleby", "Brereton", "Calthorpe", "Dawlish", "Eastwood", "Fothergill", "Gilmour",
	"Haddon", "Ilsley", "Jarvis", "Kingsley", "Lambton", "Mallory", "Newbold", "Osborne",
	"Pickering", "Quarles", "Rowntree", "Sheridan", "Tolland", "Upton", "Verney", "Wadsworth",
	"Aldridge", "Blackwood", "Crowther", "Dixon", "Fielding", "Gaskell", "Hawksworth",
	"Kemble", "Linley", "Moxon", "Pryce", "Rushworth", "Stanway", "Tunstall", "Woolley"],
]
## By level: army, corps, division, brigade, battalion.
const RANKS := [
	["Maréchal", "Général de division", "Général de division", "Général de brigade", "Chef de bataillon"],
	["General", "Lieutenant-General", "Major-General", "Major-General", "Lieutenant-Colonel"],
]
const ARMY_TITLES := ["Armée du Nord", "Anglo-Allied Army"]

var _used := [{}, {}]
## Separate from the simulation's generator, so naming never changes a battle.
var rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	rng.seed = seed_value


## A surname; unique ones aren't reused in this army until the list runs out.
func surname(army: int, unique := true) -> String:
	var names: Array = SURNAMES[army]
	if not unique:
		return names[rng.randi() % names.size()]
	var free := names.filter(func(s): return not _used[army].has(s))
	if free.is_empty():
		return names[rng.randi() % names.size()]
	var s: String = free[rng.randi() % free.size()]
	_used[army][s] = true
	return s


## Level 0-3 are generals (army..brigade, unique names), 4 a battalion commander.
func commander(army: int, level: int) -> String:
	return "%s %s" % [RANKS[army][level], surname(army, level < 4)]


static func roman(n: int) -> String:
	var out := ""
	for pair in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= pair[0]:
			out += pair[1]
			n -= pair[0]
	return out


## French ordinal: 1er / 1re, then 2e, 3e...
static func ord_fr(n: int, feminine := false) -> String:
	if n == 1:
		return "1re" if feminine else "1er"
	return "%de" % n


static func ord_en(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


static func corps_title(army: int, n: int) -> String:
	return ("%s%s Corps" % [roman(n), "er" if n == 1 else "e"]) if army == 0 else ("%s Corps" % roman(n))


static func division_title(army: int, n: int) -> String:
	return ("%s Division" % ord_fr(n, true)) if army == 0 else ("%s Division" % ord_en(n))


## [title, map label] for a brigade named after its commander, as was the custom.
static func brigade_names(army: int, surname_: String) -> Array:
	if army == 0:
		return ["Brigade %s" % surname_, "Bde %s" % surname_]
	return ["%s's Brigade" % surname_, "%s's Bde" % surname_]


## [title, short label] for battalion `bn` of regiment number `reg`.
static func battalion_names(army: int, reg: int, bn: int, light: bool) -> Array:
	if army == 0:
		var regiment := "%s %s" % [ord_fr(reg), "Léger" if light else "de Ligne"]
		return ["%s bataillon, %s" % [ord_fr(bn), regiment], "%d/%s%s" % [bn, ord_fr(reg), " Lég" if light else ""]]
	var regiment_en := "%s %s" % [ord_en(reg), "Rifles" if light else "Foot"]
	return ["%s Battalion, %s" % [ord_en(bn), regiment_en], "%d/%s" % [bn, ord_en(reg)]]
