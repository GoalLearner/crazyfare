# CrazyFare — Design (living document)

_Last revised 2026-10-25. Numbers quoted here are the Config defaults; `src/shared/Config.luau` is the source of truth._

## 1. Pitch

CrazyFare is a multiplayer, shared-map, free-for-all taxi game for up to 6 players. Everyone races to earn the most money delivering NPC passengers, and sabotages everyone else with Mario-Kart-style items that make rivals' passengers rage-quit the car. It is Crazy Taxi's loop (short fares, loud payouts, "one more run") with Mario Kart's item chaos and one PvP twist: **every passenger has an HP bar.** Hit a rival and their passenger's HP drains; at zero the passenger bails and becomes stealable.

**Core feel:** fast arcade driving with drifts, screen-punch payouts, and constant readable information about who is carrying what. Clean, funny, clippable.

## 2. The loop

### Match and rounds
- A match is **3 rounds**.
- Round start: all players spawn on the **StartGrid**. NPCs are already standing across the map so players can read the board during the **3-2-1 countdown** (a short "read the board" beat precedes it). Then free-for-all.
- Round end: first player to earn the **quota this round** (round 1 $75, round 2 $100, round 3 $125) or a **3-minute cap** (highest earnings that round win). The match winner is whoever earned the most over all three rounds. Money is shown with cents.
- Between rounds: a **30 s Pit Stop** (section 7).
- Match end: podium, placements, Gem payout, rematch vote.

### AI rival taxis (bots)
- With too few people, **bots fill the match to 4 drivers** (`Config.Bots.FillTo`). They give their seats up as real players join, at the next round. A live server starts a match with one person when bots are on; with nobody left the bots go home.
- Each bot is a stand-in driver (`Racers`) with a real car entry, so every rule applies to it: it claims a passenger by stopping beside them (rivals see TAKEN like any claim), delivers by stopping at the drop-off, picks up item boxes and uses items (Tomato at a loaded rival when it's empty, traps when someone's behind, Nitro on long straights, Shield and Seatbelt when loaded), gets hit, races for the Golden Fare, and shows up in the standings and on the podium. Its passenger rides on its roof and talks like any other.
- Always tagged **BOT** (name tag, podium). No gems, XP, quests or leaderboard entries. Losing to bots still counts as last place for the Pit Stop discount.
- Balance (tuned 2026-10-27 so a good driver wins): bots cruise at 36 studs/s (the cab tops out at 90), rest 3-6 s between fares, choose among their best few passengers with fare value softened (`Greed`), earn half tips, earn no stunt cash, and their own driving never hurts their passenger. Each bot has a skill (0.8 / 0.9 / 1.0) on speed and thinking.
- Driving: server-steered like traffic, on the road center line over the grid, keeping right when another bot comes the other way, slowing for cars and people ahead and waiting for crossing traffic at junctions, then pulling over to the road edge to stop. They ghost through traffic (no collisions) and bump player cars.

### Passengers (NPCs)
- NPCs stand at curb **PickupPoints** with an icon colored by tier:
  - **Green**: short trip, small fare, 60 HP
  - **Yellow**: medium trip, medium fare, 80 HP
  - **Red**: long trip, big fare, 100 HP
- Spawn weighting by distance from the start: greens near the start, reds at the edges.
- About **2 available NPCs per player** (min 4, max = number of PickupPoints). One respawns whenever a fare is delivered or bails.
- **Pickup contest:** the first taxi to drop below 5 studs/s within 12 studs claims the NPC. The server resolves ties on its own tick (closest wins). Others nearby see **TAKEN**.
- A taxi carries one passenger at a time.
- **Personalities** (`Config.PassengerTypes`): each passenger rolls one, shown by the badge over their head and the shape of their minimap dot.
  - **Regular** ($ badge, round dot).
  - **Thrill Seeker** (lightning badge, diamond dot): stunt cash pays double (and the per-fare stunt cap doubles); no stunt all ride halves the tip.
  - **Nervous** (grimace badge, square dot): crashes hurt 1.5x; arriving without a scratch doubles the tip ("SMOOTH RIDE").
- **Golden Fare** (`Config.Golden`): about 1 spawn in 16 while none is in play. Gold star badge, gold ring and a tall gold pillar over the curb, a big gold minimap dot, and everyone gets "GOLDEN FARE! TRIPLE PAY". Pays 3x the base (so the tip and stunt cap triple too). First to stop for it wins, like any pickup.
- **The rider:** your passenger rides in the cab sunroof-style, head and shoulders out of the roof, dressed by kind (the Golden passenger in a black suit and a gold crown). Arms go up on stunts and fly out on crashes. They shout in a speech bubble everyone sees: where they're headed (for rivals), cheers or screams on stunts, yelps on crashes and hits, "HURRY UP!" at 10 s, a Thrill Seeker's "BORING!" when nothing happens. Drawn on each client from attributes on the car, so it never touches the car's physics.

### Fares, timers, payout
- Every fare has a destination (a DropoffPoint in the tier's distance band) and a timer (`TimeBase + distance / TimeSpeed`).
- Delivery: stop (below 5 studs/s) within 14 studs of the destination.
- **Payout = base(tier) + tip + stunt cash**, in cents.
- **Tips are the edge.** The tip depends on how **speedy** (time remaining at delivery) and how **chill** (passenger HP at delivery) the ride was. A perfect, fast, clean ride on a red fare pays close to double the base and can swing a round.
- If the timer runs out, the passenger bails (same rules as a 0-HP bail, no attacker).

### Stunts and the chain (live stunt tips)
- **DRIFT!** pays $1 per half second, **BIG AIR!** $2 per half second of hang time, **NEAR MISS!** $1 each. The names are our own, not Crazy Taxi's.
- Every stunt adds one to the **chain** (x1 to x10; a long drift adds one per second). Each step past the first pays 10% more, so x10 pays +90%.
- The chain ends after **4 s without a stunt**, on a **crash big enough to hurt a passenger**, on a bail, and at a new round. A crash or bail shows **COMBO LOST**.
- Stunt cash lands in the current fare at once and **rides until delivery**: lost on a bail or a timeout. With no passenger the popup still names the stunt but pays nothing.
- Stunt cash per fare is capped at **2x the fare's base**, because stunts are reported by the client. The Tip Jar card boosts stunt cash too.
- On screen: a popup just above the cab ("BIG AIR! +$6.24") that punches in, climbs and fades; the same stunt again tops up its popup; a COMBO xN counter with a bar for the time left; a coin ding whose pitch climbs with the chain.

### Keep the road clear (owner rule, 2026-10-27)
- While driving, words never sit over the road ahead: messages (payout, crash HP, item hits, quests, Golden Fare) go in a small strip under the timer for about a second; the payout says only the amount plus a special note (GOLDEN x3, SMOOTH RIDE...), since the counters and coins show tip and stunt cash. The grade stamp is small and above the cab; the arrival banner is small and quick; one speech bubble over your cab at most.
- Big center text only for the pre-round beats when every car is parked: READ THE BOARD, 3-2-1, GO!, the round winner.

### Money you can hear
- **TOTAL** (top-left) and the **FARE** meter (fare card) are slot-machine counters: every digit is a reel that rolls up like an odometer, cents always showing, with a mechanical tick as they roll. Going down (a new round) snaps.
- The FARE meter starts at $0.00 when a passenger boards, rolls up to the base fare, and keeps rolling as stunt cash lands.
- On delivery: the payout punches in, coins burst out of the cab and fly into the TOTAL, the TOTAL waits for them and rolls up, then lands with a bump.
- A beat later a **grade stamp** slams on: **SPEEDY!** (60%+ of the timer left), **ON TIME** (25%+), **SLOW** (less, or late). The tip already pays for speed; the stamp says it out loud.

### Where to
- Every drop-off has a **name**, given out when the map is built: a drop-off on a landmark or park block takes its name (THE STADIUM, HOTEL ZEPHYR, RADIO TOWER, CITY PARK), the rest take the map's list in order (City: THE BURGER JOINT, THE MALL, THE HOSPITAL... Beach: THE PIER, THE SURF SHOP...). Storefront decoration never reuses a destination's name.
- **Rooftop signs** float over every drop-off; the current destination's sign grows and lights up in the fare's tier color.
- On boarding the passenger shouts **"TAKE ME TO THE STADIUM!"** in a small speech bubble over the cab (1.5 s). Their later lines use the same bubble, so there is only ever one over your cab; rivals' passengers talk only when you're within 90 studs, at most once every 4 s. The fare card leads with the destination name; the tall beam carries it too.
- A **glowing ring** on the ground marks the zone you must stop inside (the delivery radius), with a pulsing disc.
- The fare's **countdown** floats big beside the cab: white, then yellow at 10 s, then red with a tick every second at 5 s.
- Pulling up within 70 studs slides the destination's **name banner** across the screen.

### Boost tank
- Drifting and near-misses also fill a small **boost tank** (capacity = the vehicle's `BoostTank` stat). Hold Shift to spend it for speed. LemonNitro is separate: an instant 3 s burst.

### Dash and speed feel
- **Dash:** from a near-standstill (under 8 studs/s), tap the brake (0.2-0.8 s) and hit the gas within 0.3 s: the cab launches (an instant kick to 35, then x1.4 top speed and x2.5 acceleration for 1.2 s, 1 s cooldown). "DASH!" pops over the cab. A deliberate trick for leaving a pickup fast, not a paid stunt; holding the brake longer is reversing and never dashes (it used to fire by accident when stopping at pickups or backing off walls). It does not stack with Lemon Nitro (the bigger push wins).
- Any boost (Shift, Lemon Nitro, Dash) lights **exhaust flames** with an orange glow, a whoosh as it lights and a rocket roar while it lasts; the camera widens.
- Near top speed (and while boosting) **speed streaks** race out from the middle of the screen.
- Landing after airtime throws a **ring of dust puffs** and a thump; drifting coughs **tire smoke** puffs from the rear wheels. Dust and smoke are cartoon puffs (balls that swell and fade) so they read on pale roads and match the blocky city.
- All of it is local to your own cab (rivals don't see your flames yet).

## 3. Passenger HP and PvP

- Passengers board with HP by tier (60/80/100).
- **Damage:** item hits and wall crashes. Crashes are measured server-side as the share of the car's top speed lost in a fraction of a second: a third gone costs a third of the trip's HP (3 small crashes to bail), past about half costs more than half (2 to bail), and 85% or more (full speed into a wall) bails the passenger. Hitting a traffic car counts as at least a small crash, scaled by how fast you closed on it.
- **No regen:** HP only goes down during a ride, so every crash and hit sticks.
- **Pedestrians:** walkers on the sidewalks cross at the corners when no car is coming (traffic stops for them). Clip one at speed and your passenger walks out (fare lost). The walker only hops, spins and yells: no knockdown or injury, so the game stays in Roblox's mild-violence band.
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
| **Tomato** | attack | Server-side homing projectile to the nearest loaded rival. Loses lock if the target is drifting. On hit: windshield splat overlay (~70% coverage; wipers clear it in 3 s; honking shortens it), and the passenger bails: one hit, only Shield or Seatbelt saves them. |
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
- Prices are a share of the next round's quota (about 22-44%), so two picks cost roughly a round of banked cash. Last place gets a **30% pity discount**.
- Changed your mind? Tap a **BOUGHT** card to hand it back for a full refund, any time before the round starts (boosts only apply at the start).
- Cash you bank is spendable at the Pit Stop. The quota counts only this round's earnings, but **25% of your unspent cash carries into the next round as a head start**, so spend-vs-bank is still a real decision and a big early lead can't snowball.

## 8. Maps

### The City's set pieces (Phase D, `Config.Map.City.Blockout.Features`, built by DevBlockout and drawn on the minimap from the same spec)
- **The jump block**, straight ahead of the start grid: a road-wide lane through the block north of the plaza. A boost pad at the plaza's edge, a launch ramp, a low warehouse to fly over (come up short and you land on its roof), a landing ramp to the next road. It works backwards as a smaller jump.
- **The hill** on the road beside the plaza: a crest across the road; at speed the top throws you.
- **The diagonal park**: a path corner to corner through the park block, from the junction at (-60, 60) to the one at (-180, 180), with a big hump halfway.
- **A big hump** on the long south road.
- **The tunnel**: the road at x = -180 runs under a lit, covered stretch. Its walls count for near misses; the roof is invisible to ground probes, so traffic, walkers, bots and passengers never end up on top.
- **Alleys** (two blocks with a lane cut through) are on the minimap now, with the park path, the jump lane, the humps, the hill, the tunnel and the boost pads.
- **Boost pads** (glowing plates) before every big jump launch you to 120 studs/s and run like a Dash ("BOOST!").
- **Arcade air**: your cab feels 45% gravity while all four wheels are off the ground, so jumps hang (Roblox's 196 studs/s^2 cuts them short). Bots and traffic drive over the hill, humps and tunnel and ignore the lanes and pads.

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
| Throttle / brake-reverse (brake then gas from a stop = Dash) | W / S | R2 / L2 |
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
- Resolved 2026-10-26: timer expiry = bail (`Config.Fares.TimeoutBails = true`), decided after playing both.
