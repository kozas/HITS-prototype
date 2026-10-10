# HITS-prototype: Headquarters in the Saddle

A first-person gunpowder-era wargame prototype. You are a general on horseback,
commanding a 1:1-scale army through mounted couriers.

- **Design & technical plan:** [docs/DESIGN.md](docs/DESIGN.md)
- **Engine:** Godot 4.6 (Forward+, D3D12). Project lives in [hits-prototype/](hits-prototype/).

## M0 prototype

The game opens on a main menu with two scenarios:

- **Brigade contact:** one French brigade (4 battalions, 2,400 men) advances in
  line on an Allied brigade standing on open, level ground in the valley at the
  centre of the map. The lines come into musket range after about 30 s (first
  volley at about 32 s), and the firefight runs on from there. You start just
  behind the right of your brigade with both lines in view.
- **Corps command:** a new map with a prominent hill (about 45 m), where you
  start on the summit. Your corps of four divisions (32 battalions) is halted
  below you, drawn up in the manner of the period:
  - 1st Division deployed in line as the first line, about 1.1 km of front.
  - 2nd Division about 220 m behind in battalion columns at deploying distance,
    posted behind the first line's intervals so it can pass through them.
  - 3rd and 4th Divisions in route column on two roads to the rear.
  
  An Anglo-Allied corps of two divisions holds the ridge 1.1 km to the north:
  one division in line on the crest, the other in columns on the reverse slope.
  Everyone is halted and waiting for your orders.
- **Benchmark:** the full stress test. 192,000 men (320 battalions of 600) on a
  6 × 6 km field, with every man drawn. Battalions march, change formation, fire
  volleys, take casualties, rout and leave their dead on the field. You ride around
  in first person and send orders by courier.

In battle, **Esc** pauses and offers Resume or Main menu.

### Run

Open `hits-prototype/project.godot` in Godot 4.6 and press F5, or:

```bash
C:/Godot/Godot_v4.6.1-stable_win64.exe --path hits-prototype
```

Command-line options (after `--`):
- `--scenario=contact`, `--scenario=corps` or `--scenario=benchmark` skips the menu.
- `--bns=N` sets battalions per side in the benchmark (default 160).
- `--men=N` sets men per battalion (default 600).
- `--autoshot=DIR` saves timed screenshots and quits (a dev aid).

### Controls

| Key | Action |
|---|---|
| Mouse | look |
| W / Shift+W / Ctrl+W | trot / gallop / walk |
| S, A/D | back up, sidestep |
| T | telescope: the general halts and raises his glass (4–20×, mouse wheel); detail follows the magnification |
| M or Tab | map. Wheel zooms at the cursor and dragging (left on empty ground, or middle) pans. LMB selects a brigade; RMB sets its destination and opens the order popup: pick the formation to take on arrival (or 1–4: Line / Column / Square / March), then Issue (Enter) to send a courier, or Cancel (Esc). A green ghost shows the brigade as it would stand. You don't set a facing: the brigade chooses its own front when it acts on the order |
| O | order of battle: Army > Corps > Division > Brigade > Battalion, with commanders, strength and situation. The enemy shows only as far as he has been seen. Double-click a unit to find it on the map |
| = / - | time scale (×0.5 … ×16) |
| P | pause |
| F | free camera (WASD, Q/E, Shift) |
| G | AI autopilot for your own army |
| L | cycle LOD mode (auto / force NEAR / MID / FAR / RIBBON) |
| V | toggle line-of-sight culling |
| K | chaos: every battalion changes formation at once |
| H | toggle help |
| Esc | close the map, order of battle or telescope, otherwise open the pause menu (Resume / Main menu) |

### Benchmark

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --path hits-prototype --resolution 1920x1080 -- --bench --bench-out=bench.txt --shots=shots
```

This flies a scripted camera through nine measured segments (about 2 minutes) and
prints a table. `--shots=DIR` saves a screenshot per segment.

### Headless tools

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --headless --path hits-prototype --script res://tools/sim_profile.gd
```

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --headless --path hits-prototype --script res://tools/order_test.gd
```

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --headless --fixed-fps 60 --path hits-prototype --script res://tools/contact_test.gd
```

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --headless --path hits-prototype --script res://tools/determinism_test.gd
```

- `sim_profile.gd` runs the real sim tick and gives its cost per phase.
- `order_test.gd` checks the command loop end to end on Corps command: order →
  courier → staff delay → execution → the brigade reports the order done.
- `contact_test.gd` checks that Brigade contact reaches musketry within 45 s.
- `determinism_test.gd` checks that the battle depends only on the tick count:
  10 sim-minutes reached in 16 ms frames and in 50 ms frames must leave every
  battalion and courier in exactly the same state.

Drill review needs a window. It puts one battalion through line → column →
square → march → line → advance and saves oblique, close, flank and top-down
screenshots:

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --path hits-prototype --resolution 1600x900 --script res://tools/drill_shots.gd -- --out=shots --bn=1
```

Use `--bn=1` for a French battalion and `--bn=5` for a British one.

UI review also needs a window. It runs the full battle for 10 minutes, then
captures the saddle view, the telescope at 10× and 20×, the map zoomed out and
in, the order of battle (own army, the enemy as observed, and a
double-click jumping to the map), and an order being written and sent:

```bash
C:/Godot/Godot_v4.6.1-stable_win64_console.exe --path hits-prototype --resolution 1600x900 --script res://tools/ui_shots.gd -- --out=shots
```

Add `--scenario=corps` to review Corps command as it starts. The run then ends
with an overhead view of the deployment.

### Code map

| File | Role |
|---|---|
| `menu.tscn` + `src/menu.gd` | Main menu (the entry scene) |
| `battle.tscn` + `src/battle.gd` | Battle scene: world setup per scenario, frame loop, input, benchmark |
| `src/game_state.gd` | Autoload carrying the chosen scenario between scenes |
| `src/formation.gd` | Battalion state. The atom of the sim |
| `src/command.gd`, `src/brigade.gd` | Chain of command: army, corps, division, brigade and (as `Formation`) battalion. Any level can receive an order |
| `src/order.gd`, `src/objective.gd` | Orders (kind, objective, intensity, preferences, lifecycle) and what they point at |
| `src/ai/` | Commanders' brains, one per level: they turn an order into orders for subordinates, or into drill |
| `src/oob_names.gd` | Unit titles, numbering and (invented) commanders for the order of battle |
| `src/oob_view.gd` | Order-of-battle viewer (O) |
| `src/battle_sim.gd` | 10 Hz fixed-tick, deterministic sim: orders, couriers, movement, musketry, morale, AI |
| `src/formation_renderer.gd` | Per-battalion LOD tier, LOS culling, event-driven uniforms |
| `shaders/soldier.gdshader` | Every man, officer and drummer: companies, formations, drill, marching, volleys, rout |
| `shaders/ribbon.gdshader` | Whole battalion as one box at long range |
| `src/smoke.gd` + `shaders/smoke.gdshader` | Stateless smoke and dust ring buffer |
| `src/corpses.gd` | The fallen, 1:1, in spatial chunks |
| `src/couriers.gd` | Draws the riders carrying orders (the sim moves them, and they can be shot) |
| `src/orientation.gd` | How a unit chooses its own front (orders carry no facing) |
| `src/terrain.gd` | Heightmap shared by GPU and CPU, LOS raymarch, map definitions (`MAPS`: "ridges", "hill") |
| `src/map_overlay.gd` + `shaders/map_relief.gdshader` | The general's map (own troops, enemy at last-seen), zoomable, with relief and contours drawn from the heightmap |
| `src/player_rider.gd` + `shaders/scope.gdshader` | The general in the saddle, and his telescope |
