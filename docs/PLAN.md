# CrazyFare — Plan

Phases are gates, not sprints. Phase 1's gate is a question: **is it fun with 4 players?** Nothing in Phase 2+ starts until that is a yes.

## Decisions made instead of asking (2026-10-25)

Defaults chosen so Phase 1 could ship without a round-trip. Each is one Config knob or one small module away from being changed.

1. **Project lives at `C:\dev\crazyfare`** as its own repo (git initialised, nothing committed yet).
2. **No player characters.** `Players.CharacterAutoLoads = false`; the taxi is the player. Avoids humanoid mass, jump-out-of-seat and camera fights. A seated avatar can come back for cosmetics in Phase 4.
3. **Controls:** W/S throttle and brake/reverse, A/D steer, **Space = drift** (the Horse's hop will replace drift on Space), **Left Shift = boost tank**, **Q = item**, **H = honk**, **R = reset car**. Basic gamepad mapped; mobile is Phase 6.
4. **Boost tank** (the `BoostTank` vehicle stat): fills from drift time and near-misses, spent by holding Shift. LemonNitro is an instant 3 s burst independent of the tank.
5. **Fare timer expiry = the passenger bails** (owner call 2026-10-26 after playing both versions; `Config.Fares.TimeoutBails = false` keeps them aboard with no tip).
6. **Self-cost for attacking while loaded applies to Tomato only.** Banana/OilSlick are traps (`Config.Items.SelfCostItems`).
7. **Item boxes:** cannot pick up while holding an item; box respawns 10 s after pickup.
8. **Combo:** replaced 2026-10-26 by the stunt chain (DESIGN.md "Stunts and the chain", `Config.Stunts`). Clients still report drift/airtime/near-miss events; the server rate-limits and speed-checks them.
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
- [x] Tomato: server homing projectile, loses lock on drifting target, one hit bails the passenger (was −30 HP), client splat overlay with wipers (3 s) and honk shortening
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
- [x] 3 rounds per match with quotas $30/$45/$60 from Config (RoundEnd 5 s between a round and its Pit Stop)
- [x] Pit Stop (30 s): 5 cards from the pool of 6, prices scale by round (x1, x1.4), last-place 30% pity discount; boosts ride as `Pit_<Card>` player attributes for one round
- [x] Unspent cash carries forward as quota progress (cash resets only at match start)
- [x] Match end: podium with gems (placement 12/8/5/3/2/1 + 1 per fare), 20 s rematch vote that starts early when everyone is in; GemService holds session totals until Phase 4
- [ ] Gate: the spend-vs-bank decision is real

## Phase 4 — Persistence + economy
- [x] ProfileStore profile (DataService): gems, level/xp, ownedVehicles, selectedVehicle, paint, upgrades, quests, streak, stats; mock store in Studio
- [x] Garage UI: vehicles with stat bars, locked ones priced in Gems, upgrades with pips, paint swatches; opens whenever a round is not running
- [x] Vehicles + gimmicks: Horse (hop on Space, trotting legs), ShoppingCart (Banana-immune, wobbly), NightCab (−20% passenger damage), IceCreamTruck (+20 HP on board), GoKart (drift grip); parts-built in VehicleBuilder
- [x] Global permanent upgrades (Speed +3%, Handling +4%, Boost +8% per level, 5 levels) as Up_<Name> player attributes
- [x] Paint (6 colours, 50 Gems); horn and trail wait for Phase 6 audio/VFX
- [ ] Gate: nothing purchasable touches a live match except Pit Stop cards

## Phase 5 — Retention
- [x] Level/XP per match (50 + 10/fare + placement), level badge on world tags and under cash
- [x] Daily quests (3 of 7), weekly quest (1 of 3), login streak (5 Gems x days, cap 7), all paying Gems on completion
- [x] Leaderboards on OrderedDataStores (memory fallback in Studio): weekly Gems (Monday reset), friends, Biggest Tip Ever, Most Passengers Knocked Out; weekly top-10 gold trail
- [ ] Gate: a second-day session has a reason to exist

## Phase 6 — Monetization + Beach + polish
- [x] Gem packs (dev products) + one-time Starter Pack in the first 2 sessions; `ProcessReceipt` idempotency by receipt id (ids pasted by the owner, see docs/OWNER-STEPS.html)
- [x] VIP gamepass (2× Gems, badge, horn hook), Pit Stop Plus (6 cards), premium vehicles (Robux product or Gem price); private servers and Premium Payouts are dashboard switches
- [x] Beach map (sand cells slow to 70%, boardwalk ring at 110%, water, palms) as a Config map entry; maps rotate per match; UnlockGems recorded for private-server choice later
- [x] City decoration pass: streetlights, traffic lights, storefront signs with invented names, hotel / arena / antenna landmarks
- [x] Ambient traffic: 10 civilian cars (24 sedans, vans and buses since A5) at spread-out speeds (18-50) in right-hand lanes, following slower cars, random turns; one direction through an intersection at a time; brakes for player cars in its lane (a curb-parked cab is in the lane) and respawns elsewhere after 8 s held up; a hit is a crash (at least a small one), a near miss feeds the stunt chain and boost
- [x] Pedestrians: 16 walkers on the block sidewalks, crossing at corners when clear (run if a car bears down); traffic stops for them and for walking-back passengers; a player car that clips one makes its passenger walk out (cartoon hop + yell, mild violence)
- [ ] Real meshes (cab first, then the six items: the parts banana is a placeholder, owner's words 2026-10-26)
- [x] Layout pass v1: landmarks on three corners, two alley shortcuts through blocks (more loops when real art lands)
- [x] Sound hooks for every moment (ids 0 until the owner uploads audio), camera shake on splat / spinout / crash, passenger voice line hooks, music loop
- [x] Mobile touch controls (steer left, pedals right, drift/boost/item/honk)
- [x] Gate: store never sells HP, damage, speed or quota (checked: Gems, passes, vehicles, paint only)

## Phase A — the Crazy feel (fun pass approved 2026-10-26)
Plan of record: the approved fun-pass plan (Crazy Taxi gap list + the owner's 10-item prompt). Owner calls: quota race stays and a solo Arcade clock mode comes later; AI rival taxis fill matches (Phase C); the Crazy feel goes first.
- [x] A1 Economy: money in integer cents (`Money` helper), fares 5/10/18, quotas 75/100/125 counted per round, 25% of unspent cash carries into the next round, 3-minute rounds, match winner = total over three rounds
- [x] A2 Live stunt tips: DRIFT! / BIG AIR! / NEAR MISS! pay into the fare at once, chain x1-x10 (+10% per step), 4 s idle / hurting crash / bail ends it, held until delivery, capped at 2x base, popups above the cab, COMBO xN counter, coin ding (Pro Sound Effects 9126073001) pitched up the chain
- [x] A3 Money you can hear: slot-machine TOTAL and FARE counters (a reel per digit, odometer roll, tick 9114069409), FARE meter rolls up from $0 on boarding and with stunt cash, coin burst from the cab into the TOTAL on delivery, SPEEDY / ON TIME / SLOW stamp (`Config.Grades`, stamp 9114025921)
- [x] A4 Where to (Studio-tested 2026-10-26, owner played a full match): 12 named drop-offs per map (`Config.Destinations`, landmark blocks lend their names), rooftop name signs, "TAKE ME TO ...!" bubble over the cab, name on the fare card and beam, drop-zone ring on the ground, countdown beside the cab, arrival banner. Signs hang from an attachment straight above each drop-off (the markers are discs on their side, and a billboard's "world space" offset follows the part's axes). Pit Stop: tap a BOUGHT card to undo it for a full refund until the round starts (owner ask)
- [x] A5 Speed and traffic (Studio-tested 2026-10-26; drift smoke not seen, it needs two keys at once): Dash (brake then gas from a stop, `Config.Chassis.Dash*`), boost whoosh + rocket roar loop + exhaust flames and glow, speed streaks, landing dust puffs + thump, drift smoke puffs (new `SpeedFxController`, `Config.SpeedFx`); traffic 24 per map from `Config.Traffic.Kinds` (14 sedans, 6 vans, 4 buses), each with its own size so following gaps, junction stop lines and holds scale with length

## Phase B — passengers with personality
- [x] Passenger kinds (Studio-tested 2026-10-27; `Config.PassengerTypes`): Regular, Thrill Seeker (stunt cash x2, cap x2, no stunts = tip halved), Nervous (crash damage x1.5, unhurt = tip x2); badge over the head ($ / bolt / grimace), minimap dot shape (round / diamond / square), kind on the fare card, the tip rule named with the payout
- [x] Golden Fare (`Config.Golden`): 6% per spawn while none is in play, x3 pay, gold star badge + ring + 90-stud pillar, big gold minimap dot, "GOLDEN FARE! TRIPLE PAY" to everyone with a coin shimmer, gold beacon/ring/sign for the driver, pillar dropped on delivery; Debug "Golden" button
- [x] Visible rider (`RiderService` writes RiderKind/Pose/Line attributes on the car, `RiderController` draws it on every client): sunroof-style figure in the kind's shirt (golden: black suit + gold crown), arms up on stunts, flung out on crashes. Server-welded parts were tried first and handed the cab's physics to the server (driver froze after every pickup), hence the attributes
- [x] Reaction lines (`Config.Rider.Lines`): stunt cheers/screams by kind, crash and item-hit yelps by kind, HURRY UP at 10 s, Thrill Seeker BORING at 45% with no stunt, Golden brag, "TAKE ME TO ...!" for rivals (hidden from the driver, who has the HUD shout); the HUD crash message now shows only the HP lost
- [ ] Not seen in Studio yet: rivals seeing your rider (needs 2 players), the BORING line, the halved tip, Nervous crash damage x1.5

## Phase C — AI rival taxis
- [x] Driver identity (`src/server/Racers.luau`): a bot is a Player stand-in (UserId < 0, GetAttribute/SetAttribute) used wherever services key by driver; `Racers.IsBot` guards every FireClient and every reward/persistence path (FareService/ItemService events, GemService/ProgressionService podium rewards, QuestService, LeaderboardService); standings, NPC count, carry and Pit Stop "last place" use `Racers.All()`
- [x] Bot cars (`VehicleService.SpawnBot`): the parts-built cab painted per bot, same grid, server-owned physics in the Bots collision group (bumps players and bots, ghosts through traffic, floats over the map), no crash watch or speed sanity
- [x] `BotService` (Studio-tested 2026-10-27, owner raced 3 bots): grid route planning (Dijkstra over the junctions), rabbit + AlignPosition driving, corner and stop braking, cars/people ahead, junction yield to crossing traffic, keep-right passing (fixed a head-on deadlock), pull over beside the passenger, stuck recovery; brain: best-few passenger choice with `Greed`, Golden bias, rest between fares, re-target when taken, deliver; items by situation
- [x] Fill to 4 / leave as players join (`BotService.Rebalance` at every round setup, `RemoveAll` on Waiting), live match starts with 1 person, BOT tags on world tags and podium
- [x] Balance pass: at 52 studs/s the best bot made the $75 quota in 1:50; now 36 studs/s, half tips, rest 3-6 s, Greed 0.5, top-3 choice: the best bot ends round 1 around $70 at the 3:00 cap
- [x] Owner playtest 2026-10-27 (full 3-round match vs 3 bots: bots 1-3, owner 4th with $101, gems only for the owner). His notes, fixed: one small bubble over your cab (your passenger's lines reuse the HUD shout, 1.5 s), rivals' passengers talk only within 90 studs and once per 4 s, fewer stunt lines; Dash only on a deliberate brake tap (0.2-0.8 s under 8 studs/s, gas within 0.3 s) after it fired "randomly" at pickups and when backing off walls
- [x] Owner note 2026-10-27, "all the words blocking the screen at once, hit pedestrians and cars": driving messages moved from a huge center label to a small strip under the timer (~1 s), payout drops the TIP/STUNTS words, grade stamp smaller and above the cab (0.8 s), arrival banner smaller (1.1 s); big center text only before GO
- [ ] Not done: bots overtaking a car parked in the middle of the road (they wait behind it), bots don't use the Pit Stop, Beach map not driven yet in Studio

## Phase D — a city worth jumping (City only)
- [x] One spec for the set pieces (`Config.Map.City.Blockout.Features`, typed `MapFeatures`): DevBlockout builds them, the minimap draws them
- [x] Jump block (Studio-tested 2026-10-27): road-wide lane through the block north of the plaza, straight off the grid; launch ramp 8 high, warehouse roof 6, landing ramp; the first build (12-stud climb, no pad) bled 68 studs/s to 39 and only hopped onto the roof
- [x] Boost pads before every big jump (tag `BoostPad`, plates above the surface that the wheels' rays see, no collision): launch to `Config.Chassis.PadSpeed` (120) and run as a Dash with "BOOST!"
- [x] Hill on the road beside the plaza (x = 60), diagonal park path with a big hump, a big hump on the south road, the tunnel on x = -180 (roof CanQuery off; traffic's ground probe now starts 8 studs up)
- [x] Arcade air: `Config.Chassis.AirGravityMult` 0.45 while airborne (client chassis)
- [x] Alleys, park path, jump lane, humps, hill, tunnel and pads on the minimap
- [ ] Not seen yet: the south hump and the jump block at 120 pad speed (same code as the tested pieces); Beach has no set pieces
