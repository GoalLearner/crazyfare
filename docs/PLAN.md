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
- [x] Jump block at 120 pad speed: leaves the crest at ~94, 16 studs up, ~72 studs and ~0.9 s of air, clears the warehouse and the landing ramp and lands on the road; the radio tower's base was ~48 studs straight ahead of the landing, so (owner ask) a runout lane now runs on through its block with the tower moved 28 studs east (`Features.Runout`); tested: a 106-stud flight landed inside that block, ran past the tower and stopped before the outer road
- [ ] Not seen yet: the south hump (same code as the park hump); Beach has no set pieces

## Phase E — modes and meta
- [x] E1 License plate: every match ends with a grade from your three-round total (`Config.License.Race`: D $0, C $90, B $160, A $230, S $300, LEGEND $380) on a plate beside the podium in the grade's color; your best is saved (`BestLicense`) and a better one says NEW BEST! (not on your very first plate). People only; bots get none
- [x] E2 First-match coach (`CoachController`, `Config.Coach`): one prompt at a time in a small pill under the timer, words per input (keyboard / touch / gamepad): stop next to a $, follow the arrow and stop in the ring, drift (14 s), boost (12 s, waits for half a tank), use your item (12 s, waits for an item). Each goes when done or when its time is up; then the account is marked (`CoachDone`) and it never shows again
- [x] E3 Solo Arcade (`Config.Arcade`): ARCADE button in the side stack between matches. Live: a reserved server of your own (`TeleportToPrivateServer` with `{ mode = "Arcade" }`); that server runs Arcade for good, RACE teleports you back. Studio: the server you're in switches. A run: no bots, no quota, no Pit Stop, the City; the clock starts at 50 s, a pickup adds 6/9/12 s by tier, an arrival adds 5 (SPEEDY) or 2 (ON TIME) s, never past 99 s from now; "+6 SEC" flashes beside the clock; red under 10 s. TIME'S UP podium with an Arcade grade (`Config.License.Arcade`: C $40, B $90, A $150, S $220, LEGEND $300), best run saved (`ArcadeBest`, `ArcadeBestLicense`) and shown as BEST $x where the quota was, a BEST ARCADE RUN board (`CF_ArcadeBest`), PLAY AGAIN or the next run by itself after 12 s
- [x] E4 Music and stings: 4 APM tracks in turn from a random start (`Config.Sounds.Playlist`: Keep on Moving, Skater Punk, Rock'n'Rolla Surf, Wild Cat Scratch); stings with the music dipping under them (`Config.Sounds.Stings`): brass stab at chain 5 and 10, chime on a Golden Fare, whistle ta-da on a NEW BEST plate, crowd roar when you win a match; the countdown beep ticks through the last 5 s of any clock. All picked by Creator Store search (APM / Pro Sound Effects), not listened to yet
- [x] Studio-tested 2026-10-27 (solo): coach pill under the timer; music = Skater Punk playing, all four stings loaded; a full match ended at $260 with an A plate beside the podium; ARCADE switched the server (0:50, ARCADE · BEAT YOUR BEST, no bots, quota bar gone); a Yellow pickup flashed +9 SEC and moved the coach to its second prompt; TIME'S UP with a D plate, PLAY AGAIN, next run by itself; RACE back to round 1 with bots; the PROGRESS panel holds five boards in its 440 height (rows 16 px apart, the trail note beside BEST ARCADE RUN)
- [ ] Not seen yet: the live Arcade teleport (needs a published place), two people in a Studio Arcade run (both race the one clock), the board filling in a live server, a NEW BEST plate (Studio saves nothing, so every session is a first plate), what the tracks and stings sound like

## Phase F — launch readiness
- [x] F1 Sessions that chain (`Config.Session`, SessionService): every match in a row after the first adds +2 Gems (up to +10), a Roblox friend in the server adds +3; your podium says what you got under MATCH OVER ("STREAK x2 +2 · FRIEND +3"); the streak rides along to Arcade and back. RACE from Arcade returns you to the server you came from (`TeleportOptions.ServerInstanceId`), or any server if that one is gone or full. INVITE in the side stack between matches (SocialService's own friend prompt; hidden where invites can't be sent and in Arcade). Someone new who joins through an invite gets 50 Gems and the inviter 100, once (Roblox's referral system, `ReferredByPlayerId`; up to 10 paid invites per account; an inviter who isn't in the server collects on their next join from the `CF_Referrals` DataStore)
- [x] F2 Weekly live events (`Config.Events`, `src/shared/Events.luau`, the same schedule on server and clients): GOLDEN HOUR Saturdays 18:00-19:00 UTC (10 AM PST; Golden Fares roll 4x as often), DOUBLE GEMS Sundays 18:00-21:00 UTC (match Gems x2). A line under the Gems shows a live event with its time left, and between matches the next one within 48 h in the player's own time ("GOLDEN HOUR SAT 10:00 AM"). Studio: the Debug panel's "Next event" pretends one is live
- [x] F3 Phones: every HUD and panel scales to fit the space under Roblox's top bar (`Config.Hud.FitSize` 900 x 580, never below 0.5; a UIScale on each ScreenGui keeps every piece in its corner); touch pads and full-screen effects keep full size; the money block and the centered panels stay below the top bar
- [x] Studio-tested 2026-10-27 (solo): DOUBLE GEMS 1:00:00 LEFT under the Gems; the first match paid +24 Gems (12 x2, no streak), the second MATCH OVER read "STREAK x2 +2 · DOUBLE GEMS x2"; INVITE (purple) under ARCADE between matches; iPhone XR simulator: the HUD scaled with TOTAL clear of Roblox's buttons, BOOST / DRIFT / BRK / GAS at full size, the round podium, the Pit Stop and the GARAGE panel all fit with their titles below the bar
- [x] F4 Thumbnails and icon (`docs/launch/`): four 1920 x 1080 shots taken in the game (BIG AIR landing over a rival, jumping a rival taxi, the cab with passengers waiting, the city from above) with the CRAZYFARE logo and a short line each, and a 512 x 512 icon; for the owner to upload and compare
- [x] F5 `docs/LAUNCH.html`: the owner's checklist: friends test on v5, uploading thumbnails and icon, page text, the under-16 unlock (ID + 2-step, 250 engaged plays, refundable 1,000 Robux fee or Premium: his call), the invite rewards banner, the weekly rhythm (Friday update day, the weekend events), what's still open. VIP suggested at 299 Robux in OWNER-STEPS (market 299-499)
- [x] Fixed while shooting: bot UserIds started at -1, the same as Studio's test players (Player1 = -1), so in a multi-client Studio test Player1 shared an id with BOT REX and its client never found its own cab (camera stuck on the overview). Bots now count down from `Config.Bots.IdBase` (-1000). Live servers were never affected (real ids are positive)
- [x] F6 Phone controls (`Config.Touch`, InputController): the cab drives forward by itself on touch (one thumb was holding GAS and DRIFT / BOOST at once); BRAKE stops, holds still 0.7 s (fares claim under 5 studs/s), then reverses; a short BRAKE tap at a standstill still Dashes (`InputController.IsBraking`). Analog steering strip replaces the < > buttons. ITEM shows the held item's name in its color; the HUD item box (and its keyboard "Q") hides on touch and names X on a gamepad. Coach words for touch say "HOLD BRAKE". A finger that lifts is caught three ways (over the button, anywhere, or the touch reading as ended next frame), because the simulator reports the lift on a different input object and BRAKE stuck down
- [x] Studio-tested 2026-10-27 (iPhone XR simulator): at GO the cab drove off by itself; BRAKE held it (0 for 0.7 s), reversed to -22 studs/s, and on release drove forward again (7, 19, 28, 35, 41); the steering strip turned it steadily right (0 to 162 degrees in about a second); a Tomato showed TOMATO on the ITEM button and a tap threw it; a short BRAKE tap at a standstill lit the Dash flames
- [ ] Not seen yet: real thumbs on a real phone (two fingers at once: steer + DRIFT)
- [ ] Not seen yet: the invite prompt and a referral payout (Studio can't send invites), the friend bonus (needs a friend in the server), the return teleport to your friends' server, a real Saturday / Sunday window

## Rule changes
- [x] Pedestrians dodge (owner rule 2026-10-27, `Config.Pedestrians` Dive* + PassengerDamage): no more instant bail on a pedestrian hit. A walker in a racer's path, at most 10 studs ahead and closing faster than 6 studs/s, rolls once (75% falling to 50% at the car's top speed) for a cartoon dive-roll sideways out of the path (away from the centre line, the other way if a wall is close) with a yell. A failed dive that the car still hits is a clip: 20 HP off the passenger through `ApplyDamage` (Seatbelt, armor, Night Cab, the 1 s damage cooldown), a raised Shield takes it instead (`ItemService.AbsorbHit`), the combo ends (`ComboService.Reset` "pedestrian"), the rider yells a crash line, the HUD says WATCH THE ROAD! -20 HP, and the walker does the old hop and spin. A rival whose Banana or Oil Slick has the car spinning or unsteerable (`entry.lockedBy` / `lockedUntil`, set in ItemService) gets the credit (bail credit + Hunter Bonus). Bots follow the same rules (VehicleService entries). Pedestrians were never near-miss targets (buildings, walls, props and traffic only); the client now says so
- [x] Studio-tested 2026-10-27 (solo, Debug buttons Runway / Board / Ped ahead / Ped clip / Rival spin): bots set off dives on their own ("Bot_REX at 17 studs/s: dived clear (chance 0.72)"); a forced clip at 39 studs/s took a Nervous passenger 100 to 80 ("WE'RE GONNA DIE!"), credit nobody; with a pretend Bot_REX spin the same clip read "-20 HP, credit Bot_REX"; a roll at 39 studs/s dived clear (chance 0.65) with NOPE! and no clip; with a Shield up the clip read "-0 HP, shield true"
- [ ] Not seen yet: a clip that bails the passenger paying a real rival's Hunter Bonus in a 2-player test, how the dive-roll looks up close

## Phase X — chaos (owner spec 2026-10-27; build in order, playtest after each, all knobs in `Config.Chaos`)
- [x] X1 Ramming (`RamService`, `Config.Chaos.Ram`): every frame the server checks each pair of racers' cars (players and bots): padded footprints overlapping (separating axes on the flat rectangles, height gap under 4) and a closing speed over MinSpeed 35, using each car's fastest moment in the last 0.25 s (by the time the server sees contact the bump has already slowed them). The faster car is the attacker; the hit car's passenger takes DamageMin 15 to DamageMax 40 by closing speed (35 to 90) through `ApplyDamage` (Seatbelt, armor, Night Cab, damage cooldown; a raised Shield takes it instead), the hit car's combo ends, it gets a shove (28 studs/s at full, half at MinSpeed; bots get it as a server impulse) and both drivers get RAMMED! over their cab, a camera shake and the crash sound. Both cars' crash watch is cancelled for 0.6 s so the bump isn't also a crash. Same pair can't ram again for 1.5 s. A ram bail pays the attacker the Hunter Bonus
- [x] Bug found on the way (since Phase 2, cdc247e): `PassengerService.Bail` unloaded the passenger before reading who last hit them, and unloading clears it, so no bail ever credited an attacker: no Hunter Bonus for Tomato, Banana, Oil Slick or the new ram and pedestrian rules, and no knockout stat. Bail now reads the attacker first
- [x] Studio-tested 2026-10-27 (solo, new Debug buttons Bot park / Bot charge, plus a BotHp command): rammed a parked Bot_REX at 42 studs/s, -18 HP to its passenger; Bot_REX charged me at 54 studs/s: -24 HP (60 to 36), RAMMED! over my cab, -24 HP, the rider's crash line, and no extra crash damage; a ram on a 10 HP bot passenger bailed it with "credit fitxvert" and "+$7.20 HUNTER BONUS · REX"; bots rammed each other on their own (Bot_DOT and Bot_ZIPPY into Bot_REX)
- [ ] Not seen yet: two players ramming each other (the shove on a player's own car arrives through the client), how hard the shove feels
- [x] X2 Bounty (`Config.Chaos.Bounty`; leader kept in FareService, which owns the cash and the Hunter Bonus): this round's earnings leader (the snapshot's rank 1 metric, carry-over included) wears the crown once they have MinCash $1 (none in a race of one); it changes hands only when someone passes them outright; the snapshot carries `bounty` (the leader's UserId). BountyController hangs a 👑 billboard over the leader's cab for everyone else (AlwaysOnTop, same size at any distance, 8 studs up; never over your own cab); the minimap puts a 👑 on the leader's marker or your own arrow. A bail of the leader's passenger pays Hunter Bonus x Mult 2 and the payout line reads BOUNTY x2 in gold. FareEvent "NewLeader" to everyone: 👑 NEW LEADER: <NAME> (BOT REX, or YOU) in the strip under the timer, at most one per BannerCooldown 3 s, and a swap inside the cooldown is announced when it ends if they still lead
- [x] Studio-tested 2026-10-27 (solo; new Debug BotCash): $20 to Bot_REX put the 👑 over its cab and on the minimap; ramming its 10 HP passenger paid "+$8 BOUNTY x2 · REX" (40% of a $10 fare, doubled); round 2 from carry-over: $10 to me showed 👑 NEW LEADER: YOU, $20 to the bot a second later showed 👑 NEW LEADER: BOT REX three seconds after mine; with me leading my own cab had no crown
- [ ] Not seen yet: a crown on a real player seen by another player
- [x] X3 Frenzy (`Config.Chaos.Frenzy`): RoundService starts it when a race round's clock reaches the last Seconds 30 (Arcade excluded: its clock moves all the time and it has its own best-run board) and ends it with the phase; RoundState carries `frenzy`. Server: `FareService.SetPayMult(2)` doubles the whole delivery payout (fare + tip + stunt cash, bots too; the payout line adds FRENZY x2; stacks with a Golden Fare), `ItemService.SetBoxRespawn(1)` (boxes already waiting come back that soon), `PassengerService.SpawnGolden()` once (none if one is out). Client: FRENZY! with PAYOUTS x2 · GOLDEN FARE! in the strip under the timer (the Golden Fare's own announcement lands in the same frame), FRENZY · PAYOUTS x2 under the red timer while it lasts, Lighting's ColorCorrection tint tweens to red and back, the music plays at 1.12x with the brass stab. Fixed on the way: the timer and phase colors now reset outside play (PIT STOP stayed red after a round that ended in its last 30 s)
- [x] Studio-tested 2026-10-27 (solo; new Debug Frenzy soon / Clock and To drop-off): a normal delivery paid $9; Clock to 33 s: at 0:29 FRENZY!, the red tint, FRENZY · PAYOUTS x2 under the red timer; a Frenzy delivery of the nearest passenger (the Golden Fare) jumped cash $9.00 to $59.40; at round end the tint went back and the Pit Stop header was white
- [ ] Not seen yet: how the faster music and the tint feel over a whole 30 s, item boxes popping back every second in a busy round
- [x] X4 World events (`WorldEventService`, `Config.Chaos.Events`): RoundService schedules one at GO of every race round (StartMin 60 to StartMax 120 s later, Seconds 30), cancels it whenever the round stops playing; picked by Weight among those the map allows (Maps); RoundState carries `event`, `eventEndsAt`, `eventAt`. Client: banner (name + a short line) in the strip under the timer with the Golden chime, NAME 0:21 under the timer while it runs, minimap overlays. RushHour: `TrafficService.Surge(24)` / `EndSurge` (24 to 48 cars and back). Drawbridge: new City piece (`Features.Drawbridge`, x = 180 mid-block, two 22-stud diamond-plate leaves tagged Drawbridge with brick towers; drawn on the minimap), the leaves turn about their outer ends to 20 degrees over 10 s and back over the last 4 s. Parade: six parts-built floats (balloons, a neon star) roll along the road at z = 60 at 9 studs/s, solid to players; `TrafficService.SetBlockers` / `BotService.SetBlockers` make traffic and bots stop for them (and for the money truck). HydrantBurst: twelve new curb hydrants (`Features.Hydrants`, tagged Hydrant) jet water 7 studs into their lane; a car in a jet is thrown up at 72 studs/s (ItemEvent "Launched" through the same push as a ram shove; bots through `BotService.Launch`, an air arc on their ride height), 1.5 s per car. MoneyTruck: a truck in a random inner junction, ten coins worth $2-5 scattered 8-16 studs around it; a racer within 4.5 studs banks it (FareEvent "Cash": CASH +$3.00 over the cab and a coin)
- [x] Studio-tested 2026-10-27 (solo; Debug buttons Rush hour / Drawbridge / Parade / Hydrants / Money truck / To event): RUSH HOUR! with traffic 24 to 48, back to 24 when it ended; MONEY TRUCK! with the $$$ truck, $5 / $3 / $2 coins and the minimap $, a jump onto the coins banked $12; DRAWBRIDGE! leaves up with their yellow tips between the towers, a run from the north hit the leaf at 67 studs/s and flew the peak; HYDRANTS! threw the cab high into BIG AIR (a car parked in a jet gets thrown again every 1.5 s); PARADE! floats with balloons rolling down z = 60, the road purple on the minimap
- [x] By itself: round 2 started a Parade 66 s after GO ("[WorldEventService] Parade for 30 s")
- [ ] Not seen yet: a player car crashing into a float, bots and traffic queuing behind the parade, a bot grabbing coins
- [ ] X5 Passenger requests; then carpool, ticking fare, fruit stands, Crazy Hop, weather

## Traffic jams (owner note 2026-10-27, "make sure NPC drivers don't crash and cause these traffic jams")
- [x] Cause: when a round ended every racer's car froze where it stood, often in a lane, for the podium and the 30 s Pit Stop, while traffic kept driving into the queue behind it; each queued car waited its own 8 s before giving up, and a traffic van shoved into a frozen cab ended up across both lanes
- [x] Racers go back to their grid pads on the plaza the moment play stops (round end, match end, Arcade end, waiting), so nothing sits in a lane between rounds (`VehicleService.ResetAllToGrid` instead of freezing in place)
- [x] A car queued behind a held-up car counts the same wait, so the whole line respawns elsewhere together; `Config.Traffic.BlockedRespawn` 8 to 5 s
- [x] Traffic waits at the stop line while any racer's car (or an event obstacle) is inside the intersection (`JunctionOccupiedHalf` 13), and when turning it looks past the corner for a car parked just around it
- [x] Studio-tested 2026-10-27: my cab parked across a lane on the runway for 24 s never had more than 2 traffic cars near it and never more than 1 stopped; at round end all four cars (mine and three bots) were on their grid pads, frozen, during the podium
