# CrazyFare — Design (living document)

_Last revised 2026-10-25. Numbers quoted here are the Config defaults; `src/shared/Config.luau` is the source of truth._

## 1. Pitch

CrazyFare is a multiplayer, shared-map, free-for-all taxi game for up to 6 players. Everyone races to earn the most money delivering NPC passengers, and sabotages everyone else with Mario-Kart-style items that make rivals' passengers rage-quit the car. It is Crazy Taxi's loop (short fares, loud payouts, "one more run") with Mario Kart's item chaos and one PvP twist: **every passenger has an HP bar.** Hit a rival and their passenger's HP drains; at zero the passenger bails and becomes stealable.

**Core feel:** fast arcade driving with drifts, screen-punch payouts, and constant readable information about who is carrying what. Clean, funny, clippable.

## 2. The loop

### Match and rounds
- A match is **3 rounds**.
- Round start: all players spawn on the **StartGrid**. NPCs are already standing across the map so players can read the board during the **3-2-1 countdown** (a short "read the board" beat precedes it). Then free-for-all.
- Round end: first player to hit the **quota** (round 1 $30, round 2 $45, round 3 $60) or a **4-minute cap** (highest cash wins).
- Between rounds: a **30 s Pit Stop** (section 7).
- Match end: podium, placements, Gem payout, rematch vote.

### Passengers (NPCs)
- NPCs stand at curb **PickupPoints** with an icon colored by tier:
  - **Green**: short trip, small fare, 60 HP
  - **Yellow**: medium trip, medium fare, 80 HP
  - **Red**: long trip, big fare, 100 HP
- Spawn weighting by distance from the start: greens near the start, reds at the edges.
- About **2 available NPCs per player** (min 4, max = number of PickupPoints). One respawns whenever a fare is delivered or bails.
- **Pickup contest:** the first taxi to drop below 5 studs/s within 12 studs claims the NPC. The server resolves ties on its own tick (closest wins). Others nearby see **TAKEN**.
- A taxi carries one passenger at a time.

### Fares, timers, payout
- Every fare has a destination (a DropoffPoint in the tier's distance band) and a timer (`TimeBase + distance / TimeSpeed`).
- Delivery: stop (below 5 studs/s) within 14 studs of the destination.
- **Payout = base(tier) × tipCurve × combo**, rounded to whole dollars.
- **Tips are the edge.** The tip depends on how **speedy** (time remaining at delivery) and how **chill** (passenger HP at delivery) the ride was. A perfect, fast, clean ride on a red fare pays close to double the base and can swing a round.
- If the timer runs out, the passenger bails (same rules as a 0-HP bail, no attacker).

### Crazy Combo
- A multiplier that builds from **drifts, near-misses and airtime** and **decays after 3 s** without a new event (then loses a step every 0.5 s).
- Steps of +0.1, capped at ×1.5. The combo is applied at payout. A bail resets it.

### Boost tank
- Drifting and near-misses also fill a small **boost tank** (capacity = the vehicle's `BoostTank` stat). Hold Shift to spend it for speed. LemonNitro is separate: an instant 3 s burst.

## 3. Passenger HP and PvP

- Passengers board with HP by tier (60/80/100).
- **Damage:** item hits and wall crashes. Crashes are measured server-side from the replicated velocity delta (over 30 studs/s in a tick hurts; the harder the hit, the more it costs, capped).
- **Regen:** clean driving (no damage for 3 s, car moving) regens slowly.
- Using an **attack** item (Tomato) while loaded costs your own passenger 15 HP.
- **At 0 HP the passenger bails:** door tween, angry text bubble, walks to the nearest PickupPoint and becomes available again with the **same destination**. The victim loses the fare and the combo. The attacker gets a **Hunter Bonus = 40% of the lost fare's value** (Phase 2).

### Information layer (what makes targets readable)
- **Minimap** (whole map): NPC dots by tier; every rival taxi with its current fare $ value and a mini HP bar (empty taxis grey); your own arrow; your destination.
- **In world:** loaded taxis show a `$value` tag with an HP bar over the roof within 150 studs, and a passenger silhouette in the rear window.
- The leader carrying a red fare is the natural target. That is the catch-up mechanic; there is no rubber-banding.

## 4. Items (exactly 6, one slot per player)

Picked up from **item boxes** (respawn 10 s; you cannot pick up while holding one). The roll is weighted by quota rank: the leader rolls defense/boost heavy, last place rolls Tomato heavy, traps are flat.

| Item | Kind | Effect |
|---|---|---|
| **Tomato** | attack | Server-side homing projectile to the nearest loaded rival. Loses lock if the target is drifting. On hit: windshield splat overlay (~70% coverage; wipers clear it in 3 s; honking shortens it), −30 HP. |
| **Banana** | trap | Dropped behind. Spinout 1.5 s, −25 HP. |
| **OilSlick** | trap | Dropped behind. Lose steering 2 s, −10 HP, low-visibility decal. |
| **LemonNitro** | boost | 3 s speed burst. |
| **Shield** | defense | Blocks one hit, then breaks. |
| **Seatbelt** | defense | Passenger immune 8 s, glowing door VFX. |

Projectiles can also knock tagged Traffic/Prop parts into the road (Phase 2).

## 5. Currencies

- **Cash ($):** earned from fares, spent only at the Pit Stop, resets at match end. Never persisted.
- **Gems:** awarded at match end (placement + fares delivered) and from quests. Persisted. Buys vehicles, cosmetics, map unlocks, permanent upgrades. Never spendable mid-match.
- Nothing purchasable affects a match in progress except Pit Stop boosts bought with round cash.

## 6. Vehicles

- Default **Yellow Cab**, owned by all.
- Every other vehicle is a **sidegrade** with a roughly equal stat budget (`TopSpeed, Accel, Handling, DriftGrip, BoostTank`) and **one gimmick**:
  - **Horse**: hop on Space (replaces drift), high accel/handling, low top speed
  - **ShoppingCart**: immune to Banana, wobbly, cheap
  - **NightCab**: passengers take 20% less HP damage
  - **IceCreamTruck**: passengers board with +20 HP
  - **GoKart**: highest drift grip
- One raycast chassis drives every vehicle, parameterized from Config. Models only define wheel/leg attachments and `WheelType` (`wheels|legs`) for animation.
- All designs are original. No licensed vehicles or characters, ever.
- Mid-tier vehicles cost Gems; premium ones cost Robux but are also buyable with a large Gem price.
- Permanent car upgrades (speed/handling/boost) are global across vehicles in v1.

## 7. Pit Stop (between rounds, 30 s)

- Players spend **round cash** on temporary, this-round-only boost cards. 4–5 randomized from the pool: **SpeedTune, BigTank, StartItem, ArmoredSeats, TipJar, ExtraWiper**.
- Prices scale by round. Last place gets a **30% pity discount**.
- **Unspent cash carries forward as quota progress**, so spend-vs-bank is a real decision.

## 8. Maps

- **City** first (MVP; blocked out from Parts: ~600×600 road grid, blocks, ramps, StartGrid, 12 pickups, 12 dropoffs, 6 item boxes).
- Later: **Beach** (sand slows, boardwalk shortcut), **Neon City** (night), **Snow Mountain** (ice drift), **Space Station**.
- Unlock by cumulative Gems. Each map is a data-driven Config entry; map gimmicks live in Config.

## 9. Retention layer

- Player level (XP per match), badge by name.
- Garage shows locked vehicles greyed with prices: goals always visible.
- Daily quests (3) + weekly quest (1) + login streak, all paying Gems.
- Leaderboards: weekly (resets Monday), friends, Biggest Tip Ever, Most Passengers Knocked Out. Weekly top 10 gets an exclusive trail.
- Seasons later (new map + pass + limited event every 6–8 weeks). No ranked MMR.

## 10. Monetization

- Gem packs (dev products) with a one-time Starter Pack offered in the first 2 sessions.
- VIP gamepass (2× Gems, badge, horn). Pit Stop Plus (6 cards instead of 5). Premium vehicles. Cosmetics. Private servers. Premium Payouts via engagement.
- **Never sell anything that affects passenger HP, item damage, speed, or quota.**

## 11. Controls (v1, keyboard + basic gamepad)

| Action | Key | Gamepad |
|---|---|---|
| Throttle / brake-reverse | W / S | R2 / L2 |
| Steer | A / D | Left stick |
| Drift (handbrake) / vehicle special (Horse hop) | Space | A |
| Boost (tank) | Left Shift | B |
| Use item | Q | X |
| Honk (also clears splat faster) | H | Y |
| Reset car | R | Back |

Mobile touch controls are Phase 6 polish.

## 12. Tech architecture (summary; conventions in CLAUDE.md)

- Rojo project; Luau `--!strict`; rokit (rojo, wally, selene, luau-lsp); wally (ProfileStore, Promise). No Knit.
- `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts, `src/shared` → ReplicatedStorage/Shared.
- Services and controllers with `Init()`/`Start()` booted by `Main`.
- `Config.luau` holds every tunable; `Remotes.luau` defines every remote.
- Server owns money, fares, HP, items, hit detection, round/match state, data. Client owns car physics (network ownership) and VFX. Server validates delivery distance, speed sanity, item ownership; rate-limits remotes.
- Minimap/HP data replicated via one batched RemoteEvent at 10 Hz.
- Players have **no character** (`CharacterAutoLoads = false`); the taxi is the player. A seated avatar can return later for cosmetics.
- Data via ProfileStore (Phase 4). MarketplaceService `ProcessReceipt` with idempotency (Phase 6).
- Studio-only `DevBlockout` (city from Parts, CollectionService-tagged) and `DebugPanel`.

## 13. Target look (set 2026-10-26)

Stylized low-poly city with a bold palette: lit window strips, crosswalks, streetlights and traffic lights, storefront signs with invented names, a few landmark buildings you can see from anywhere. The blockout generator grows into this (decoration passes first, real meshes for landmarks and the cab last). Layout gets the same treatment in Phase 6: landmarks, loops instead of dead ends, shortcuts that reward map knowledge.

## 14. Open questions (not blocking Phase 1)

- Vehicle art: stay parts-built through Phase 4, or commission meshes? (Parts until the loop is proven fun.)
- Robux price points for premium vehicles / Pit Stop Plus / VIP (Phase 6).
- Exact Pit Stop card prices and the pity discount curve (Phase 3 playtest).
- Resolved 2026-10-26: timer expiry pays base with no tip (`Config.Fares.TimeoutBails = false`).
