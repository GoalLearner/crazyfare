# CrazyFare — engineering conventions

CrazyFare is a 6-player, shared-map, free-for-all Roblox taxi game: deliver NPC passengers for cash, sabotage rivals with Mario-Kart-style items so their passengers rage-quit, hit the round quota first. Design lives in `docs/DESIGN.md`, the phased plan in `docs/PLAN.md`. This file is how we build it.

## Repo layout

```
default.project.json   Rojo tree (see below)
rokit.toml             toolchain pins: rojo, wally, selene, luau-lsp
wally.toml             packages: ProfileStore, Promise  → Packages/ (gitignored)
selene.toml / .luaurc  lint + strict typing config
scripts/check.ps1      sourcemap + luau-lsp analyze + selene + rojo build
src/
  shared/              → ReplicatedStorage.Shared
    Config.luau        EVERY tunable. Nothing numeric lives anywhere else.
    Remotes.luau       every RemoteEvent, defined once, fetched by name
    Types.luau         shared type aliases (tiers, snapshot shapes, events)
    Signal.luau        tiny typed signal (service-to-service events)
    RateLimiter.luau   per-player token buckets for remotes
    VehicleBuilder.luau parts-built vehicle models (Yellow Cab)
    Prizes.luau        what a prize is called (drop reveal, level rewards, streak calendar)
    DailyShop.luau     the daily rotating shop's items for a UTC day (same on server and client)
  server/              → ServerScriptService.Server
    Main.server.luau   boots services in a fixed order: Init() all, then Start() all
    Services/*.luau    one module per concern (Map, Session, Vehicle, Passenger, Fare, Combo, Item, Store, Drop, Walker, Depot, Match, Round, Replication, Debug...)
    Studio/DevBlockout.luau  Studio-only city generator (parts, CollectionService-tagged)
  client/              → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau   boots controllers the same way
    Controllers/*.luau Input, Vehicle (raycast chassis), Camera, Hud, Minimap, WorldTags, Effects, Walker, Depot, Title, Options, Credits, DebugPanel...
  first/               → ReplicatedFirst.First
    Loading.client.luau the loading screen (replaces Roblox's), hands over to the title screen
docs/                  DESIGN.md, PLAN.md, GETTING-STARTED.html, OWNER-STEPS.html, LAUNCH.html (+ launch/ thumbnails, icon)
```

## Toolchain / how to run

```
rokit install            # once per machine: installs the pinned rojo, wally, selene, luau-lsp
wally install            # pulls Packages/ (ProfileStore, Promise)
rojo plugin install      # once: installs the Rojo plugin into Roblox Studio
rojo serve               # keep running; in Studio: Plugins > Rojo > Connect
```

Studio test: open any Baseplate place, connect Rojo, then **Test > Clients and Servers > Players: 2 > Start**. In Studio the server generates the blockout city on boot if `workspace.Map` is missing (`DevBlockout`), so no place file is required.

Before saying anything is done, run `.\scripts\check.ps1` (PowerShell). It regenerates the sourcemap, runs `luau-lsp analyze` with the Roblox API definitions, runs `selene`, and does a `rojo build`. All four must be clean. There is no automated gameplay test; the gate for a phase is a real multi-client Studio run.

## Language and style

- Every file starts with `--!strict`. No `any` escapes except at the Roblox-API seams (`Instance.new(className)` with a dynamic name, remote argument unpacking), and each one is cast explicitly with `::`.
- Modules return a plain table. No classes/metatables for services. No Knit, no frameworks.
- Naming: PascalCase for modules, functions on modules and types; camelCase for locals and fields; UPPER_SNAKE for file-local constants that are *not* tunables (tunables go in Config).
- One module per concern. If a module needs another, require it directly by static path (`script.Parent.MapService`). No require cycles: when two services must talk both ways, the lower one exposes a `Signal` and the higher one subscribes in `Start()`.
- Time: `workspace:GetServerTimeNow()` for anything shown to clients (deadlines, phase ends). `os.clock()` only for local dt math.
- Integers for money. Round once, at payout.

### Luau old-solver gotchas (seen 2026-10-25, luau-lsp 1.36.0)
- Table literals are invariant in field types: `{ part = Instance.new("Part") }` will not convert to `{ part: BasePart }`. Declare the field as the concrete class, or annotate the local (`local x: T = {...}`) before inserting.
- Singleton string unions (`"Green" | "Red"`) misbehave inside table fields and across module boundaries. Use `string` for tier/kind fields; the union types in `Types.luau` are documentation.
- `local x = map[id]; if not x then x = make() end; use(x)` keeps `x` refined to `nil` after the assignment. Write `local existing = map[id]; if existing then return existing end` and build below.
- Indexing `{ [K]: V }` yields `V`, not `V?`; annotate `local v: V? = map[k]` when you will assign nil to it.
- selene's parser rejects empty generics: write `Signal.Signal<nil>` for a no-argument signal, never `Signal<>`.
- The API definitions file for `luau-lsp analyze` must match the pinned luau-lsp tag; the `main` branch file uses newer syntax and fails to parse.

## Service / controller pattern

Server service module shape:

```lua
--!strict
local Service = {}
function Service.Init() end   -- create state, wire remotes, subscribe to other services' signals
function Service.Start() end  -- start loops (Heartbeat), spawn things
return Service
```

`Main.server.luau` holds an ordered list; it calls every `Init()` first, then every `Start()`. Order matters only for `Start()` (Round starts last). Client controllers are identical (`Main.client.luau`). Nothing else starts loops on its own.

## Player states (lobby flow)

Every person is Title, Driver, Passenger, Queued or Depot (`SessionService`, mirrored to the `SessionState` attribute). Every join starts on the title screen (Title: no seat, counted nowhere, so `SeatOrder`, `MatchStart`, `AllToDepot` and `CountReady` skip it); the `Play` remote runs the normal join rules. Teleports from our own servers, and Studio's `SkipTitle` workspace attribute, skip it. While Title, `TitleController` hides every other `CrazyFare*` ScreenGui each frame: give a screen the `Config.Title.KeepAttribute` attribute to stay up over the title (a panel its buttons open), or `SelfManagedAttribute` if it decides its own visibility by state (the title won't switch it back on). Only `MatchController` changes it; services react to `SessionService.OnStateChanged` (grid car, depot car, walking character). `Racers.All()` is the people driving plus bots, so per-match systems never see walkers or the depot. Depot cars live in their own VehicleService table and never appear in `GetAll()`.

## Ownership rules (non-negotiable)

**Server owns:** money, fares (claim resolution, timers, delivery, payout), passenger HP and bails, item inventory, item hit detection (projectiles, traps, item boxes), round/match state, rank, player data. The server resolves every contest (pickup, item box) on its own tick; the client never decides it won anything.

**Client owns:** vehicle physics for its own taxi (network ownership), camera, input, all VFX/UI. The client *reports* drift/airtime/near-miss events and its drifting flag; the server rate-limits and sanity-checks them (speed from the replicated velocity) before they touch combo.

Server validation on every remote: rate limit via `RateLimiter`, argument types, item ownership, delivery distance, speed sanity. Remotes that fail validation are dropped silently (warn in Studio).

Known v1 limitation: physics is client-authoritative, so positions are trusted. Anti-cheat hardening is a listed task, not a Phase 1 blocker.

## Networking

- One batched `Snapshot` RemoteEvent at `Config.Net.SnapshotHz` (10 Hz) carries every taxi's position/heading/cash/fare value/HP/combo and every NPC's position/tier/state. Minimap, world tags and rival HP bars read only from it.
- Discrete things (claimed, delivered, bailed, item granted/used/hit, round phase change) go through `FareEvent` / `ItemEvent` / `RoundState` events, fired to the player they concern (or all).
- Add a remote only in `src/shared/Remotes.luau`. Add its rate limit in `Config.Net.RateLimits` at the same time.

## Everything in Config

`src/shared/Config.luau` is the only place numbers live: fares, tips, combo, HP, items, vehicles, chassis, camera, pit stop, quotas, maps, HUD distances, rate limits, key bindings. Code reads `Config.X.Y`; never a literal. If you are about to type a number into a service, stop and add a knob. The blockout map spec (`Config.Map.City.Blockout`) is shared by `DevBlockout` and the minimap so both always agree.

## Studio-only tooling

- `DevBlockout.Generate()` builds the City from Parts: ground, road grid, sidewalks, buildings, ramps, walls, 6 StartPads, 12 PickupPoints, 12 DropoffPoints, 6 ItemBoxes, a parts-built Yellow Cab template in `ReplicatedStorage.VehicleTemplates`. All tagged via CollectionService (tag names in `Config.Tags`). Runs automatically on server boot in Studio when `workspace.Map` is absent; run it from the command bar to bake the map into a place: `require(game.ServerScriptService.Server.Studio.DevBlockout).Generate()`.
- `DebugPanel` (client, Studio only) sends `Debug` remote commands; `DebugService` refuses them outside Studio.

## Recipes

### Add an item
1. `Config.Items.Pool.<Name>` with `Kind` (`attack|trap|boost|defense`), display name, color, and its own numbers block (`Config.Items.<Name>`).
2. Weight it in every bucket of `Config.Items.RankWeights` (Leader/Mid/Last) or it never rolls.
3. Server: handle `Kind`/name in `ItemService.Use` (spawn projectile/trap, apply boost, set defense flag). Damage goes through `PassengerService.ApplyDamage(player, amount, source)`; never edit HP elsewhere.
4. Client: `EffectsController` reacts to the `ItemEvent` types you emit (splat, spinout, boost…). `VehicleController` consumes movement effects (spin/oil/boost) from the same event.
5. HUD slot shows `Config.Items.Pool.<Name>.DisplayName` automatically.

### Add a vehicle
1. `Config.Vehicles.<Id>` with the stat budget (`TopSpeed, Accel, Handling, DriftGrip, BoostTank, SteerMax`), `WheelType` (`wheels|legs`), `Gimmick` id, price fields.
2. Model: `VehicleBuilder.Build(id)` for a parts build, or a Studio model in `ReplicatedStorage.VehicleTemplates.<Id>` with attributes `VehicleId`, `WheelType`, a `Chassis` PrimaryPart, attachments `WheelFL/FR/RL/RR`, `DropPoint`, `Muzzle`, and a `Silhouette` part. The chassis is the only part with mass.
3. Gimmicks are flags read by the systems they touch (e.g. `ImmuneTo = {Banana=true}` checked in `ItemService`; `PassengerHpBonus` in `PassengerService.Board`). Never branch on vehicle id in gameplay code; branch on the gimmick field.
4. Price: `GemPrice` (0 = everyone owns it), or `RobuxOnly = true` plus `Config.Monetization.VehicleProducts.<Id>` and `VehicleRobux.<Id>` for a Robux car (MonetizationService grants it).

### Add a map
1. `Config.Map.<Name>` with `Bounds`, spawn/tier distance bands, `Gimmicks` (e.g. `SandSlowMult`), unlock cost.
2. Build it tagged exactly like the City (`Config.Tags`): StartPad, PickupPoint, DropoffPoint, ItemBox, Road, Building, Wall, Prop. `MapService` discovers everything by tag; nothing is looked up by name.
3. Set `Config.Map.Current` (or the map rotation once Phase 6 lands) and the minimap draws from the map's own blockout/road spec.

## Product rules every change must respect

- All art, names and vehicles are original. No licensed vehicles, characters or music, ever.
- Pay-to-win is the monetization strategy (owner decision 2026-10-27: "100% pay to win"). Passes are `MonetizationService.HasPass(player, key)` on the server and `Pass_<Key>` player attributes on the client; Robux upgrades (Max Upgrades) are handled in `StoreService`. Passes, cars and upgrades may sell speed, boost, passenger HP, items, cash and upgrade levels. Everything sold is permanent: no temporary, in-match boosts (owner decision 2026-10-28). Free post-match drops (`DropService`, `Config.Drops`) may include one-match item tokens; nothing may ever buy, reroll or improve a drop (that would make it a paid random item). The Phantom (mythic ghost horse) is sold only inside `Config.Monetization.PhantomOffer`; systems read its `Mythic` / `BuiltInShield` flags, never its id. Every purchase is applied on the server by the service that owns that stat (ProcessReceipt idempotent by receipt id); the client never grants itself anything. Paid random items show their odds first and are hidden where `PolicyService` restricts them.
- Copy is short and funny; the HUD shows only what a player acts on. No tutorial text for things that are self-explanatory.
- Tune by Config, then playtest. Playtest beats theory.
