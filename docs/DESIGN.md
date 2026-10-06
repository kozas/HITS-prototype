# Headquarters in the Saddle: Design & Technical Plan

Working title **HITS**. You play a first-person general on horseback, commanding a
full-scale gunpowder-era army almost entirely through mounted couriers. The game
is about the reverse of micro-management: you give intent, it arrives late, it
gets interpreted, and you live with the result.

---

## 1. Pillars

1. **You are a person on a horse.** You only see what's visible from your saddle:
   ridges, smoke, dust, flags. You have no god-camera. The map is *your* map, and it
   only knows what reports have told you.
2. **Orders are physical objects.** Each order is carried by a rider who takes
   real time to cross real terrain. Riders can get lost, be killed, or reach a
   commander who has already moved. Delay is the core mechanic, not a penalty.
3. **Subordinates have agency.** You command corps, divisions or brigades. They
   interpret your intent based on their initiative and caution, and they keep
   fighting while your next order is on its way.
4. **Spectacle at 1:1 scale.** Waterloo had about 190,000 men. When you crest a
   ridge you should see a full army, every man in it, in step, under the colours.

Setting: Napoleonic is the default (it has the best-known battles, a large
audience, and the cleanest linear tactics). The systems also cover the
Seven Years' War, the ACW (Gettysburg had about 160k men), and the Franco-Prussian
War. Only the content changes; the engine doesn't care which era it is.

---

## 2. Scale reference

| Thing | Number | Source of truth |
|---|---|---|
| Battalion | 500–800 men (sim uses 600) | atom of the simulation |
| Line, French 3 ranks / British 2 ranks | ~0.6 m per file → 600 men = 120–185 m frontage | |
| Attack column ("column of divisions") | ~50 files × 12 ranks ≈ 30 × 15 m | |
| Square | ~600 men → ~45 m a side, hollow | |
| Waterloo | ~73k French, ~68k Allied, ~50k Prussian (late) | ≈ 300+ battalions, 400+ guns |
| Field size | ~5 × 4 km | prototype terrain 6.1 × 6.1 km |
| Courier at a hard canter over broken ground | ~15–25 km/h → 3 km ≈ 8–12 min, plus finding the man | |
| Staff time before an order is acted on | minutes to tens of minutes | |
| Battle length | 8–10 hours | needs time compression |

**What the eye actually resolves** (1080p, 75° vertical FOV, 1.8 m man):
`pixels tall ≈ 1267 / distance_m`

| Distance | Pixels per man | What it reads as |
|---|---|---|
| 50 m | 25 px | individual men, faces of formation, muskets |
| 200 m | 6 px | silhouettes, legs moving, flash of a volley |
| 700 m | 1.8 px | a coloured band with a flag; ranks merge |
| 1500 m | 0.85 px | a coloured line; flags, smoke and dust carry the information |
| 3000 m | 0.4 px | haze, smoke columns, dust clouds, glints |

That table drives the whole rendering plan: **past ~700 m a man is sub-pixel**,
so rendering individuals there is wasted. Rendering them badly is worse,
because it causes shimmer and aliasing. The trick is to make the far image
*correct* (right colour, right shape, right motion cues), not detailed.

---

## 3. The core trick: soldiers are a pure function

> **No soldier has CPU-side state.** Every man's position, facing, pose and
> animation is computed in the vertex shader from:
> `f(formation_state, slot_index, sim_time, seed)`.

- The CPU simulates **formations** (≈ 300–600 objects), not men (≈ 200,000).
- Each formation is one `MultiMeshInstance3D` whose instance transforms are
  identity and never change. The shader reads `INSTANCE_ID` as the slot index.
- Per-formation parameters are pushed as **instance uniforms**: formation type,
  transition start time, strength, last volley time, rout amount and colours.
  They change only on *events*, so a quiet formation costs the CPU nothing except
  its node transform while it moves.
- **Formation changes** (line → column → square) are a shader lerp between two
  slot layouts with a per-man random delay. The men visibly shuffle into place,
  and it costs the CPU one uniform write.
- **Marching** is a per-vertex leg swing and bob driven by `sim_time`, with all
  men in step (as they actually marched) plus a tiny per-man phase jitter.
- **Volleys**: the front two ranks bring muskets to "present", then fire raggedly
  (per-man random delay), with a muzzle flash. Again, one uniform (`last_volley`).
- **Casualties**: `visible_instance_count = strength`, and the layout is computed
  from the current strength, so the ranks close up toward the centre, as they
  historically did. Each dead man is appended to a static, spatially chunked
  corpse buffer, so the field fills with the fallen 1:1.
- **Rout**: one scalar scatters the men, turns them around and makes them run.
- **Terrain conformance**: the shader samples the same heightmap texture the
  terrain mesh uses, so every man stands on the ground with no CPU raycasts.

The same "stateless" pattern applies to **smoke**. Puffs are a ring buffer
written once at spawn time. Drift, growth and fade are computed in the shader
from `sim_time - spawn_time`. Thousands of drifting smoke banks cost almost
nothing on the CPU.

---

## 4. The abstraction ladder (what you see at each range)

Selection is **per formation** on the CPU (O(formations)), never per man.

| Tier | Range (tunable) | Representation | Cost |
|---|---|---|---|
| **NEAR** | < ~220 m | Full low-poly man (~180 tris), animated legs and musket, flash, casts shadows | Heavy, but only a few battalions are ever this close |
| **MID** | 220–750 m | Simplified man (~70 tris), still animated, no shadows | |
| **FAR** | 750–1700 m | One camera-facing card per man (6 tris: shako / coat / trousers bands) | Cheap, preserves the correct mass and colour |
| **RIBBON** | > 1700 m | **One mesh per battalion**: a terrain-conforming box with a procedural, anti-aliased "rank texture" | 1 draw, ~100 tris per battalion |
| **HIDDEN** | behind a ridge (LOS check vs. heightmap) | Not drawn at all. The sim still runs | 0 |

Information that carries past the point where men are visible:
- **Colours / flags**: a waving flag per battalion stays visible well past the
  men. Later we can exaggerate the scale slightly at range for readability.
- **Smoke**: you can see a firefight from 4 km by its smoke bank long before you
  can see who's in it.
- **Dust**: marching columns throw dust. A column hidden behind a ridge still
  gives itself away. (This is a gameplay mechanic: dust on the eastern horizon
  means the Prussians are coming.)
- **Sound** (later): volley rolls, cannon and drums, with distance delay.

Future rungs:
- **Hero zone** (< 30 m): promote nearby men to real per-man agents (individual
  deaths, officers shouting, wounded men) for drama. These are rare and
  budget-capped.
- **Impostor atlas** for FAR, made by baking the NEAR mesh from 8 angles, if the
  coloured card turns out to be too plain.
- **Vertex-animation textures (VAT)** for richer NEAR animation (reload cycle,
  death falls) without skeletons.

---

## 5. Hidden and distant formations: three layers of truth

| Layer | Who owns it | Used for |
|---|---|---|
| **Ground truth** | Simulation | Everything, always |
| **Seen** | Player's eyes: LOS from the saddle (terrain, later smoke and woods) | What the 3D renderer draws |
| **Believed** | Reports, sightings and courier messages, each with a timestamp | What your *map* shows |

- The renderer only draws formations the player could plausibly see. The LOS
  check is formation-level: three points per battalion, raymarched against the
  heightmap, round-robin across frames. This is both a performance win and the
  game's fog of war.
- The map shows enemy formations at their **last seen** position and fades them
  with age. Later, your *own* formations will also show at their last
  *reported* position, because your map is only as good as your couriers.
- A battalion behind a reverse slope (Wellington's trick) simply doesn't exist
  on your screen until you ride up and look.

---

## 6. Simulation architecture

### Hierarchy

```
Army (player = C-in-C)
 └─ Corps (AI commander)        ← orders from you
     └─ Division (AI)            ← orders from you, or interpreted by corps
         └─ Brigade (AI)         ← lays out its battalions
             └─ Battalion        ← atomic sim unit (formation)
             └─ Battery          ← 6–8 guns, separate unit type
         └─ Cavalry regiment → squadrons
```

Prototype M0 has Brigade → Battalion only, and the player orders brigades.

### Unit state (battalion)
Position, facing, formation type plus transition (from, to, start, duration),
strength, morale, fatigue, ammunition, current order, local SOP state
(engaged / halted / routing), and last volley time.

### Order model
An order is *intent*, not a waypoint: **objective** (place, or a unit to
support or attack), **posture** (attack / hold / screen / retire), **formation
preference**, and **conditions** ("if pressed, fall back on X"). The recipient's
AI turns it into concrete moves using its personality (initiative, aggression,
caution). The prototype implements "go to X, face Y, form Z", which has the same
plumbing.

### Order lifecycle (implemented in M0)
`written → riding → delivered → staff delay → executing → (complete | superseded)`,
with `lost` when the courier is killed. Reports flow back the other way: in M1 we
add periodic ADC reports and "no word from 3rd Brigade" when couriers don't
return.

### Combat (aggregated, not per bullet)
- **Musketry**: once per reload cycle (~20 s), shooters × hit probability at
  that range × modifiers (formation, terrain, morale, smoke) gives casualties.
- **Artillery** (M2): roundshot and canister. A few hundred guns, so individual
  roundshot *can* be real projectiles bouncing through formations. That's cheap
  and spectacular.
- **Melee / charges** (M2): a state machine between two formations. Squares
  versus cavalry is a rock-paper-scissors resolved at formation level.
- **Morale**: the real decider. Casualties, flank threats, routing neighbours
  and the commander's presence feed in. A rout can cascade.

### Tick schedule (fixed timestep, deterministic, decoupled from frame rate)

| System | Rate | Cost driver |
|---|---|---|
| Formation movement and SOP | 10 Hz | O(formations) |
| Spatial hash rebuild | 10 Hz | O(formations) |
| Separation | 2 Hz | O(formations × neighbours) |
| Musketry and morale | 1 Hz | O(formations × neighbours) |
| AI commanders | 0.1–1 Hz, staggered | O(commanders) |
| LOS / spotting | round-robin, N per frame | O(N) per frame |
| Couriers | per frame | O(couriers) |
| Render sync (transform, LOD, uniforms) | per frame | O(formations) |

Determinism matters because **time compression** is required (a 10-hour
battle), and it also enables replays and, later, lockstep multiplayer.

---

## 7. CPU budget (target: 60 fps, 16.6 ms, at ~200k men)

| Work | Budget | Notes |
|---|---|---|
| Sim at 1× (10 Hz × 320 bns) | < 1 ms/frame | GDScript is fine at this size |
| Sim at 16× compression | < 5 ms/frame | Move to C++ GDExtension when needed |
| Render sync (O(formations)) | < 2 ms | event-driven uniforms, transforms only for movers |
| LOS | < 0.5 ms | round-robin, coarse heightmap |
| Everything else (UI, couriers, smoke spawns) | < 1 ms | |

The key point is that **nothing scales with the number of men** on the CPU. Men
cost only GPU vertex work, which is bounded by the LOD ladder. If we need ten
times more formations (e.g. Leipzig, ~600k men), the plan is to move the sim to
a C++ GDExtension and multithread it with `WorkerThreadPool` (formations are
independent within a tick, apart from the spatial hash).

GPU risks to measure (that's what M0 is for):
- Vertex throughput of NEAR/MID men (including the depth prepass and shadow passes)
- Overdraw from smoke when you ride into a firefight
- Sub-pixel shimmer on FAR cards (MSAA/TAA vs. ribbon earlier)

---

## 8. Technology

- **Godot 4.6, Forward+, D3D12**: already set up. MultiMesh, instance uniforms
  and shader includes cover everything above.
- **GDScript** for the prototype. Hot loops move to **C++ GDExtension** once
  profiling says so. (C# would require the .NET build of Godot; GDExtension is
  the better long-term route for a sim core anyway.)
- Terrain: a heightmap texture shared by the terrain shader, the soldier shader
  and the CPU sampler, so there is one source of truth with identical
  interpolation. Later: clipmap terrain for larger maps, plus roads, woods,
  villages and farms (Hougoumont!) as LOS blockers and strongpoints.

---

## 9. Milestones

| | Goal | Proves |
|---|---|---|
| **M0: Stress test** *(this prototype)* | ~190k men, two armies, procedural terrain, LOD ladder, LOS culling, stateless smoke, corpses, first-person rider, minimal courier orders, benchmark mode | The rendering and sim architecture holds at 1:1 scale |
| **M1: Command loop** | Real order intents, staff delay, ADC reports back, a "believed" map for your own troops, lost and late couriers, time compression UX | The core fantasy is fun |
| **M2: Combat depth** | Artillery (real roundshot), cavalry, squares, charges, skirmishers, morale cascades, smoke blocking LOS | Tactical texture |
| **M3: Opponent** | Enemy C-in-C AI that uses the same courier system and sees with the same knowledge model | Fair, legible opposition |
| **M4: A real battle** | Hand-built Waterloo-like map, OOB, timeline, weather (mud!) | Content pipeline |
| **M5: Presentation** | Audio with distance delay, VAT animations, officers, colour parties, hero zone | Spectacle |

---

## 9a. M0 results (GTX 1080, i7-8700K, 1920×1080, 192,000 men)

| Scenario | FPS | GPU ms | Script ms | Draw calls | Tris (M) |
|---|---|---|---|---|---|
| Saddle, behind own lines (auto LOD, LOS on) | 142 | 3.0 | 2.6 | 101 | 1.5 |
| Saddle, in the firing line | 141 | 5.3 | 2.1 | 123 | 4.7 |
| Overview at 400 m, auto LOD (every man in view) | 128 | 4.2 | 2.8 | 112 | 1.2 |
| Overview, **force NEAR** (192k full men, worst case) | 33 | 27.9 | 2.8 | 265 | 24.1 |
| Overview, force MID | 65 | 13.4 | 2.4 | 252 | 9.4 |
| Overview, force FAR | 131 | 4.4 | 2.4 | 256 | 1.3 |
| Overview, force RIBBON | 147 | 3.1 | 2.4 | 45 | 0.6 |
| ×16 time compression | 94 | 4.1 | 5.8 | 118 | 1.2 |

Findings:
- **The LOD ladder is the whole game.** Full-detail men everywhere costs 24M
  triangles and 33 fps. The auto ladder draws the same army for about 1.2M
  triangles and 4 ms GPU, a 20× reduction, with no visible loss at range.
- **Draw calls are a non-issue.** Each battalion is about one draw at any tier.
- **We're CPU-bound, not GPU-bound.** About 7 ms per frame with about 3 ms GPU.
  Script is about 2.5 ms (render sync 2 ms + sim 0.5 ms); the rest is engine
  scene overhead for about 1,000 nodes.
- **Sim cost**: 1.5 ms per 10 Hz tick for 320 battalions in GDScript, down from
  4.2 ms after caching footprints, moving broad-phase work to 1–2 Hz, and adding
  a fast path for idle battalions. That's fine at 1×, about 4 ms per frame at
  16×. A C++ GDExtension port of `battle_sim.gd` is the obvious 10–30× win when
  we need 600+ battalions or 64× compression.
- **LOS culling** hides 75–90% of the army from a man on a horse on rolling
  terrain. That's a large GPU saving and *also* the fog-of-war mechanic. Rolling
  ±40 m terrain makes the reverse-slope idea work naturally.
- **Next GPU risks**: smoke overdraw at the moment you ride *into* a firefight
  (the near-camera fade helps), and FAR-card shimmer (MSAA 2× is acceptable;
  consider switching to RIBBON earlier).

---

## 10. Open design questions

1. **Time compression versus embodiment.** If you gallop at 16×, you're a missile.
   Options: compression only when you're stationary, or "ride to…" auto-travel
   that compresses time, or the player always moves at 1× while the world moves
   at N×. (The prototype does the last of these for now.)
2. **Who do you command?** Corps commanders only (Napoleon), or division and
   brigade too (Wellington, a hands-on micro-manager)? This could be a
   per-scenario setting.
3. **Your own death and capture.** Riding to the front gives you information and
   a morale bonus, but risks the whole army. Is that game over, or does a
   successor take command?
4. **How honest is the map?** Do you draw it yourself (pencil marks), or is it
   auto-annotated from reports with timestamps?
5. **Era.** Napoleonic for launch? The engine is agnostic.
