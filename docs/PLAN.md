# CrazyFare — Plan

Phases are gates, not sprints. Phase 1's gate is a question: **is it fun with 4 players?** Nothing in Phase 2+ starts until that is a yes.

## Decisions made instead of asking (2026-10-25)

Defaults chosen so Phase 1 could ship without a round-trip. Each is one Config knob or one small module away from being changed.

1. **Project lives at `C:\dev\crazyfare`** as its own repo (git initialised, nothing committed yet).
2. **No player characters.** `Players.CharacterAutoLoads = false`; the taxi is the player. Avoids humanoid mass, jump-out-of-seat and camera fights. A seated avatar can come back for cosmetics in Phase 4.
3. **Controls:** W/S throttle and brake/reverse, A/D steer, **Space = drift** (the Horse's hop will replace drift on Space), **Left Shift = boost tank**, **Q = item**, **H = honk**, **R = reset car**. Basic gamepad mapped; mobile is Phase 6.
4. **Boost tank** (the `BoostTank` vehicle stat): fills from drift time and near-misses, spent by holding Shift. LemonNitro is an instant 3 s burst independent of the tank.
5. **Fare timer expiry pays base with no tip** (owner call 2026-10-26 after the first playtest; the harsher bail is one flag away: `Config.Fares.TimeoutBails`).
6. **Self-cost for attacking while loaded applies to Tomato only.** Banana/OilSlick are traps (`Config.Items.SelfCostItems`).
7. **Item boxes:** cannot pick up while holding an item; box respawns 10 s after pickup.
8. **Combo:** +0.1 per step, cap ×1.5; idle 3 s then lose a step every 0.5 s. Clients report drift/airtime/near-miss events; the server rate-limits and speed-checks them.
9. **Crash damage:** server reads the replicated velocity each tick; a delta above 30 studs/s does `(delta−30)×0.6` HP, capped at 35, with a 1 s cooldown.
10. **Solo testing allowed:** `MinPlayers = 1`, auto-start 4 s after. Phase 1 loops single rounds forever (podium 10 s, then a fresh round).
11. **Blockout spec is data** in `Config.Map.City.Blockout`; `DevBlockout` and the minimap both read it.
12. **Tomato** locks the nearest loaded rival within 250 studs at launch; with no target it flies straight.
13. **Wheel steer/spin visuals are local-only** in v1 (other clients see wheels, not their rotation).
14. **Client-authoritative physics is trusted** in v1 (speed sanity only logs). Anti-cheat hardening is a Phase 2 task.
15. **Yellow Cab budget:** TopSpeed 90, Accel 45, Handling 6, DriftGrip 0.25, BoostTank 4 s. The first five knobs to tune are listed in `docs/GETTING-STARTED.html`.

Questions that remain are in `docs/DESIGN.md` §13; none block Phase 1.

## Phase 1 — MVP (gate: fun with 4 players?)

Foundations
- [x] CLAUDE.md, DESIGN.md, PLAN.md
- [x] Rojo project, rokit/wally/selene/luau-lsp pins, `scripts/check.ps1`
- [x] `Config.luau` with every Phase 1 tunable; `Remotes.luau`; `Types.luau`; `Signal`; `RateLimiter`

World
- [x] `DevBlockout`: ground, 6×6 road grid (~600×600), sidewalks, buildings, ramps, walls, 6 StartPads, 12 PickupPoints, 12 DropoffPoints, 6 ItemBoxes, Yellow Cab template, all CollectionService-tagged
- [x] `MapService`: discover tagged instances, nearest-point queries, tier bands by distance
- [x] `VehicleBuilder`: parts-built Yellow Cab (chassis, cabin, windows, silhouette, 4 wheels + attachments, DropPoint, Muzzle)

Driving (client)
- [x] `VehicleController`: raycast suspension, tire grip, drive/brake/reverse, steering with speed falloff, handbrake drift, boost tank, LemonNitro burst, spinout, airtime, near-miss, flip auto-reset, wheel visuals
- [x] `CameraController`: chase cam with speed FOV
- [x] `InputController`: keyboard + basic gamepad, honk, reset

Fare loop (server)
- [x] `PassengerService`: NPC spawn by tier weighting, pickup contest, board, HP, regen, crash damage, bail (walk to nearest PickupPoint, same destination), despawn/respawn
- [x] `FareService`: destinations by tier band, timers, delivery check, tips (speedy + chill), combo multiplier at payout, cash, quota
- [x] `ComboService`: steps, cap, decay, rate-limited client events

Items (server + client)
- [x] `ItemService`: item boxes (proximity, respawn), rank-weighted roll, one slot
- [x] Tomato: server homing projectile, loses lock on drifting target, −30 HP, client splat overlay with wipers (3 s) and honk shortening
- [x] Banana: drop behind, spinout 1.5 s, −25 HP, owner immunity window
- [x] LemonNitro: 3 s burst
- [x] Attack-while-loaded self cost (−15)

Round
- [x] `RoundService`: Waiting → PreCountdown (read the board) → Countdown 3-2-1 → Playing (quota or 4-min cap) → Podium → repeat
- [x] Cars frozen on the grid until GO; mid-round joiners spawn at the grid

HUD + replication
- [x] `ReplicationService`: one 10 Hz `Snapshot` (taxis + NPCs)
- [x] `HudController`: cash + quota bar, round timer, fare card (tier, $, timer bar, passenger HP), combo meter, boost tank, item slot, speed, center messages (countdown, TAKEN, payout punch, bail), destination arrow + beacon
- [x] `MinimapController`: roads from the blockout spec, NPC dots by tier, rivals with $ + mini HP (grey when empty), self arrow, destination
- [x] `WorldTagController`: `$value` + HP bar over loaded rivals within 150 studs; rear-window silhouette
- [x] `EffectsController`: splat overlay + wipers, bail bubble, spinout/boost feedback
- [x] `DebugPanel` + `DebugService` (Studio only): give item, set HP, add cash, force round end, spawn NPC

Verification
- [x] 2-player Studio run (2026-10-26): booted clean, drove, claimed, delivered; owner: "looks good"
- [ ] 4-player session: is it fun? Tune the five car-feel knobs first, then fares/tips
- [ ] Fix whatever that run exposes

## Phase 2 — Full items + hunting
- [x] OilSlick (lose steering 2 s, −10 HP, low-vis decal)
- [x] Shield (blocks one hit, breaks): consumed before Tomato and trap effects, glow on the car
- [x] Seatbelt (passenger immune 8 s, glow on the car)
- [x] Hunter Bonus: attacker gets 40% of the lost fare on a bail they caused
- [x] Hittable props (hydrants, cones, bins on sidewalk corners): cars push them, tomatoes launch them, reset each round
- [x] Rank-weighted roll table for all 6 items
- [x] Anti-cheat v1: per-frame distance sanity with a server correction after repeated strikes (`Config.Net.SpeedSanity`)
- [x] Playtest batch (2026-10-26): ramps are humps, lighting + atmosphere + materials pass, window bands, crosswalks, invisible edge barrier with a skyline ring
- [ ] Gate: items feel fair and funny in a 4–6 player room

## Phase 3 — Match structure
- [ ] 3 rounds per match with quotas $30/$45/$60 from Config
- [ ] Pit Stop (30 s): 4–5 cards from the pool (SpeedTune, BigTank, StartItem, ArmoredSeats, TipJar, ExtraWiper), prices scale by round, last-place 30% pity discount
- [ ] Unspent cash carries forward as quota progress
- [ ] Match end: podium, placements, Gem payout formula (placement + fares delivered), rematch vote
- [ ] Gate: the spend-vs-bank decision is real

## Phase 4 — Persistence + economy
- [ ] ProfileStore profile: gems, level/xp, ownedVehicles, selectedVehicle, cosmetics, upgrades, quests, streak, stats
- [ ] Garage UI: locked vehicles greyed with prices
- [ ] Vehicles + gimmicks: Horse (hop), ShoppingCart (Banana-immune, wobbly), NightCab (−20% passenger damage), IceCreamTruck (+20 HP on board), GoKart (drift grip); `WheelType = legs` animation path
- [ ] Global permanent upgrades (speed/handling/boost)
- [ ] Cosmetics (paint, horn, trail)
- [ ] Gate: nothing purchasable touches a live match except Pit Stop cards

## Phase 5 — Retention
- [ ] Level/XP per match, badge by name
- [ ] Daily quests (3), weekly quest (1), login streak, all paying Gems
- [ ] Leaderboards: weekly (Monday reset), friends, Biggest Tip Ever, Most Passengers Knocked Out; weekly top-10 trail
- [ ] Gate: a second-day session has a reason to exist

## Phase 6 — Monetization + Beach + polish
- [ ] Gem packs (dev products) + one-time Starter Pack in the first 2 sessions; `ProcessReceipt` idempotency
- [ ] VIP gamepass (2× Gems, badge, horn), Pit Stop Plus (6 cards), premium vehicles (Robux or large Gem price), private servers, Premium Payouts
- [ ] Beach map (sand slows, boardwalk shortcut) via Config map entry + unlock by cumulative Gems
- [ ] City decoration pass in the generator: streetlights, traffic lights, storefront signs, landmark buildings; then real meshes (cab first)
- [ ] Layout pass: landmarks, loops, shortcuts (see DESIGN §13)
- [ ] Sound, camera shake, passenger voice lines, music
- [ ] Mobile touch controls
- [ ] Gate: store never sells HP, damage, speed or quota
