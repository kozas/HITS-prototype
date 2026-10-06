# HITS-prototype: Headquarters in the Saddle

A first-person gunpowder-era wargame prototype. You are a general on horseback,
commanding a 1:1-scale army through mounted couriers.

- **Design & technical plan:** [docs/DESIGN.md](docs/DESIGN.md)
- **Engine:** Godot 4.6 (Forward+, D3D12). Project lives in [hits-prototype/](hits-prototype/).

## M0 stress test

192,000 men (320 battalions of 600) on a 6 × 6 km field, with every man drawn.
Battalions march, change formation, fire volleys, take casualties, rout and leave
their dead on the field. You ride around in first person and send orders by courier.

### Run

Open `hits-prototype/project.godot` in Godot 4.6 and press F5, or:

```bash
C:/Godot/Godot_v4.6.1-stable_win64.exe --path hits-prototype
```

Command-line options (after `--`): `--bns=N` battalions per side (default 160),
`--men=N` men per battalion (default 600).

### Controls

| Key | Action |
|---|---|
| Mouse | look |
| W / Shift+W / Ctrl+W | trot / gallop / walk |
| S, A/D | back up, sidestep |
| M or Tab | map. LMB selects a brigade; RMB-drag from the destination sets the facing; 1–4 picks Line / Column / Square / March. Releasing sends a courier |
| = / - | time scale (×0.5 … ×16) |
| P | pause |
| F | free camera (WASD, Q/E, Shift) |
| G | AI autopilot for your own army |
| L | cycle LOD mode (auto / force NEAR / MID / FAR / RIBBON) |
| O | toggle line-of-sight culling |
| K | chaos: every battalion changes formation at once |
| H | toggle help, Esc releases the mouse |

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

`sim_profile.gd` gives a per-phase sim cost. `order_test.gd` checks the command
loop end to end: order → courier → staff delay → execution.

### Code map

| File | Role |
|---|---|
| `src/formation.gd` | Battalion state. The atom of the sim |
| `src/battle_sim.gd` | 10 Hz fixed-tick sim: orders, movement, musketry, morale, AI |
| `src/formation_renderer.gd` | Per-battalion LOD tier, LOS culling, event-driven uniforms |
| `shaders/soldier.gdshader` | Every man: layout, formation transitions, marching, volleys, rout |
| `shaders/ribbon.gdshader` | Whole battalion as one box at long range |
| `src/smoke.gd` + `shaders/smoke.gdshader` | Stateless smoke and dust ring buffer |
| `src/corpses.gd` | The fallen, 1:1, in spatial chunks |
| `src/couriers.gd` | Riders that carry orders and can be shot |
| `src/terrain.gd` | Heightmap shared by GPU and CPU, LOS raymarch |
| `src/map_overlay.gd` | The general's map (own troops, enemy at last-seen) |
