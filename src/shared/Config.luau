--!strict
-- Every tunable in CrazyFare lives here. Code reads Config.X.Y; no gameplay number lives anywhere else.
-- Units: studs, seconds, studs/s, studs/s^2, whole dollars.

export type TierDef = {
	Base: number, -- dollars before tip and combo
	Hp: number, -- passenger HP on boarding
	Color: Color3,
	MinTrip: number, -- destination distance band (studs, straight line from the pickup)
	MaxTrip: number,
	Label: string,
}

export type ItemDef = {
	Kind: string, -- "attack" | "trap" | "boost" | "defense"
	DisplayName: string,
	Color: Color3,
}

export type VehicleStats = {
	DisplayName: string,
	Description: string, -- the gimmick in plain words, shown in the garage
	WheelType: string, -- "wheels" | "legs" (animation only)
	TopSpeed: number, -- studs/s
	Accel: number, -- studs/s^2 at standstill
	Handling: number, -- lateral grip rate (1/s); higher = sticks harder
	DriftGrip: number, -- fraction of Handling kept on the rear axle while drifting
	BoostTank: number, -- seconds of boost at full tank
	SteerMax: number, -- degrees at standstill
	Gimmick: string,
	Color: Color3,
	TintMesh: boolean?, -- imported mesh body takes Color and garage paint (VehicleRig marks it Paintable; wheels stay as imported)
	PaintSkin: string?, -- imported mesh with a palette texture: Shared.PaintSkins.<name> goes on its body so paint shows
	GemPrice: number, -- 0 = everyone owns it (unless RobuxOnly)
	RobuxOnly: boolean?, -- sold only for Robux (Config.Monetization.VehicleProducts); never free, never for Gems
	-- Gimmick flags; systems branch on these, never on the vehicle id.
	Hop: boolean?, -- Space hops instead of drifting
	HopPower: number?, -- studs/s of upward velocity per hop
	ImmuneTo: { [string]: boolean }?, -- trap kinds that do nothing to this vehicle
	PassengerDamageMult: number?, -- scales every hit the passenger takes
	PassengerHpBonus: number?, -- extra HP on boarding
	Wobble: number?, -- random steering noise (0..1)
	BuiltInShield: boolean?, -- blocks one Tomato or ram hit, recharging (Config.Vehicles.Phantom.ShieldRecharge)
	Mythic: boolean?, -- a target: triple Hunter Bonus on its passenger, a minimap marker, a round banner, a serial number
	FlameColor: Color3?, -- boost flames in this color instead of fire
	EngineSound: number?, -- its own engine loop (0 / nil = the shared one)
}

export type TierWeightBand = { MaxDistance: number, Green: number, Yellow: number, Red: number }

-- Per-round weather (Config.Chaos.Weather.List). -1 on ClockTime / FogDensity / Haze keeps the map's own sky.
export type WeatherDef = {
	Id: string,
	Name: string, -- the banner at the round's start ("" for Clear: no banner)
	Sub: string,
	Weight: number,
	Maps: { [string]: boolean }?, -- nil = any map
	Color: Color3, -- the banner's color
	CloudCover: number, -- 0..1 sky covered by clouds (-1 = Config.Sky.CloudCover)
	Particle: string, -- Config.Chaos.Weather.Particles key ("" = nothing falls)
	ClockTime: number,
	Brightness: number, -- times the place's own
	FogDensity: number, -- Atmosphere.Density
	Haze: number,
	Tint: Color3, -- the WeatherTint color correction
	Saturation: number,
	GripMult: number, -- your cab's tire grip (Handling) on these roads
	TopSpeedMult: number,
	DriftBoostMult: number, -- boost tank filled per second of drifting
	PayMult: number, -- every delivery's payout
	PayLine: string, -- under the payout when PayMult isn't 1
	TrafficSpeedMult: number,
	BotSpeedMult: number,
}

-- What falls in a weather (rain, snow): a particle box riding above the camera (WeatherController).
export type WeatherParticles = {
	Texture: string,
	Color: Color3,
	Transparency: number,
	Size: number,
	Squash: number, -- below 0 stretches each particle along its fall
	Rate: number, -- per second (kept low: most players are on phones)
	Lifetime: number,
	SpeedMin: number,
	SpeedMax: number,
	Drift: Vector3, -- acceleration: wind
	Spin: number, -- degrees/s
	Streaks: boolean, -- turned along the fall (rain) instead of facing the camera (snow)
	Area: number, -- studs across the box they fall from
	Height: number, -- studs above the camera
	Ahead: number, -- studs ahead of the camera, where you're looking
}

-- A city's set pieces (Phase D): DevBlockout builds them and the minimap draws them from this one spec, so both agree.
-- Offsets inside a block are from the block's center; +Z is south.
export type HumpSpec = { X: number, Z: number, Yaw: number, Height: number, Length: number, Crest: number, Width: number } -- Yaw in degrees: the hump's axis
export type MapFeatures = {
	Alleys: { { X: number, Z: number } }, -- blocks with a north-south lane cut straight through
	AlleyWidth: number,
	Hill: { X: number, ZFrom: number, ZTo: number, Height: number, Flat: number }, -- a crest on a north-south road
	JumpBlock: { -- a lane through a block: launch ramp, a low warehouse to fly over, landing ramp
		X: number,
		Z: number,
		Dir: number, -- the way you jump: 1 = south (+Z), -1 = north (-Z); the offsets below run along it from the center
		Width: number,
		LaunchStart: number,
		Crest: number,
		RoofStart: number,
		RoofEnd: number,
		LandEnd: number,
		CrestHeight: number,
		RoofHeight: number,
	},
	DiagonalPark: { X: number, Z: number, Width: number }, -- a park block with a path corner to corner (north-east to south-west)
	BigHumps: { HumpSpec },
	Runout: { X: number, Z: number, Width: number, LandmarkShift: number }, -- a clear lane through the block a jump lands you facing; its landmark moves this far east
	BoostPads: { { X: number, Z: number, Yaw: number, Length: number, Width: number } }, -- before each big jump
	Tunnel: { X: number, ZFrom: number, ZTo: number, Height: number }, -- a covered stretch of a north-south road
	Drawbridge: { X: number, Z: number, LeafLength: number, Width: number, Thickness: number }, -- two leaves on a north-south road meeting at Z; they rise in the Drawbridge event
	Hydrants: { { X: number, Z: number, DX: number, DZ: number } }, -- curb hydrants; (DX, DZ) points into the road where the jet lands
	HydrantSpray: number, -- studs from a hydrant to its jet
	FruitStands: { { X: number, Z: number, DX: number, DZ: number } }, -- market stalls straddling the curb; (DX, DZ) points into the road
}

-- A passenger personality (Config.PassengerTypes.Kinds). Multipliers of 1 change nothing.
export type PassengerKindDef = {
	Weight: number, -- spawn odds against the other kinds
	Label: string, -- fare card ("THRILL SEEKER 80/80")
	Icon: string, -- badge over the NPC's head
	Shirt: Color3, -- the rider's shirt in the cab
	StuntMult: number, -- stunt cash (and the per-fare stunt cap) x this
	CrashMult: number, -- crash damage x this
	NoStuntTipMult: number, -- tip x this when the ride had no stunt at all
	SmoothTipMult: number, -- tip x this when the passenger arrives without a scratch
	TipLine: string, -- shown with the payout when one of the tip rules kicked in
}

export type PitStopCardDef = { Name: string, Effect: string, Share: number, Value: number } -- Share: price as a fraction of the next round's quota
export type QuestDef = { Id: string, Text: string, Goal: number, Reward: number }
export type ProductDef = { Id: number, Gems: number, Label: string, Robux: number, Vehicle: string?, UpgradeLevel: number? }
export type GamePassDef = { Id: number, Label: string, Effect: string, Robux: number }
-- A Robux upgrade (Config.Monetization.Boosts); FallbackGems are paid when it can't apply (already maxed).
export type BoostDef = { Id: number, Label: string, Effect: string, Robux: number, FallbackGems: number, Color: Color3 }
export type EventKindDef = { Name: string, Color: Color3, GoldenChanceMult: number, GemMult: number }
-- One prize in the post-match drop pool (Config.Drops.Pool). Kind: "Gems" (Amount), "Paint" | "Vehicle" (Ref: a
-- Config.Paint / Config.Vehicles id), "Boost" (Ref: a Config.Items.Pool id: you start next match holding it).
export type DropEntry = { Id: string, Kind: string, Rarity: string, Weight: number, Amount: number?, Ref: string? }
-- Anything handed over like a drop prize (a DropEntry or a LevelReward): same kinds, same Ref/Amount rules.
export type Prize = { Id: string, Kind: string, Rarity: string, Amount: number?, Ref: string? }
-- Reaching Level hands over this prize once per account (Config.Levels.Rewards). Rarity colors its chip.
export type LevelReward = { Level: number, Id: string, Kind: string, Rarity: string, Amount: number?, Ref: string? }
export type TrailDef = { Name: string, Rarity: string, Weight: number, Colors: { Color3 } }
export type HornDef = { Name: string, Rarity: string, Weight: number, Sound: number, Pitch: number? }
export type CardDef = { Name: string, Rarity: string, Weight: number, Shirt: Color3, Hat: Color3, Icon: string }
export type EventWindow = { Kind: string, Day: number, HourUtc: number, Hours: number } -- Day: 1 = Sunday ... 7 = Saturday

local Config = {}

-- CollectionService tags. MapService discovers everything by tag; nothing is looked up by name.
Config.Tags = {
	Ground = "Ground",
	Road = "Road",
	Sidewalk = "Sidewalk",
	Building = "Building",
	Wall = "Wall",
	Prop = "Prop",
	Ramp = "Ramp",
	StartPad = "StartPad",
	PickupPoint = "PickupPoint",
	DropoffPoint = "DropoffPoint",
	ItemBox = "ItemBox",
	Vehicle = "Vehicle",
	VehicleTemplate = "VehicleTemplate",
	Npc = "Npc",
	Projectile = "Projectile",
	Trap = "Trap",
	Sand = "Sand", -- slows cars (Beach)
	Boardwalk = "Boardwalk", -- speeds cars (Beach)
	Water = "Water",
	Traffic = "Traffic", -- ambient NPC cars (near-miss targets)
	BoostPad = "BoostPad", -- a glowing strip that launches your cab (VehicleController)
	Drawbridge = "Drawbridge", -- a drawbridge leaf (attribute Side: -1 north, 1 south)
	Hydrant = "Hydrant",
	FruitStand = "FruitStand", -- a fruit stall Model (attributes Index, Active, SmashDir)
}

-- Pedestrians (PedestrianService): walk the sidewalk around each block and cross the street at the corners when no
-- car is coming. A car bearing down usually gets a cartoon dive-roll out of its path; a failed dive is a clip that hurts
-- your passenger and ends your combo (owner rule 2026-10-27; it used to make them walk out). The reactions are a roll,
-- a hop, a spin and a yell, never a knockdown or injury, which keeps the game in Roblox's "mild violence" band. Never a
-- near-miss stunt: we never reward aiming at people.
Config.Pedestrians = {
	Count = 16, -- per map
	WalkSpeed = 5, -- studs/s
	RunMult = 2.4, -- crossing with a car bearing down
	RingInset = 5.5, -- walking line in from the block edge (inside the waiting passengers, clear of the buildings)
	WalkWeight = 1, -- odds at a corner: keep walking around the block vs cross the street
	CrossWeight = 1.5,
	SafeDistance = 60, -- a car closer than this and heading for the crosswalk: wait at the curb
	ClearDistance = 14, -- any car this close to the middle of the crosswalk: wait
	PanicDistance = 28, -- mid-crossing, a car this close heading at them: run
	MaxWait = 12, -- seconds at a curb before walking on around the block instead
	SpawnSpacing = 10,
	SpawnTries = 30,
	HitRadius = 1.2, -- body half-width added to the car's box
	HitMinSpeed = 6, -- a car slower than this just nudges past
	HitImmuneSeconds = 2,
	HopHeight = 5,
	HopSeconds = 0.7,
	BubbleSeconds = 1.8,
	BillboardDistance = 160,
	HitLines = { "HEY!!", "WATCH IT!", "EYES ON THE ROAD!", "I HAD THE WALK SIGN!", "NOT COOL!" },
	-- Dodging: a walker in a car's path, at most DiveDistance ahead of its front bumper and closing faster than HitMinSpeed,
	-- rolls once for a dive. The chance falls from DiveChance at low speed to DiveChanceAtTop at the car's top speed.
	DiveDistance = 10, -- studs ahead of the front bumper
	DiveMargin = 1.5, -- studs either side of the car's path that still count as in its way
	DiveChance = 0.75,
	DiveChanceAtTop = 0.5,
	DiveSeconds = 0.55, -- the dive-roll
	DiveHop = 1, -- studs: how high the roll arcs
	DiveClear = 1.5, -- studs past the car's side where the walker lands
	DiveMin = 3, -- studs: shortest and longest dive
	DiveMax = 9,
	DecideSeconds = 1.2, -- one roll per car approach; a walker who stayed put gets clipped if the car keeps coming
	DiveLines = { "WHOA!", "NOPE!", "YIKES!", "NOT TODAY!", "MY SHOES!" },
	PassengerDamage = 20, -- a clip; Shield, Seatbelt, Armored Seats and the Night Cab still count
	SkinColors = {
		Color3.fromRGB(240, 205, 175),
		Color3.fromRGB(210, 160, 120),
		Color3.fromRGB(160, 110, 75),
		Color3.fromRGB(105, 70, 50),
	},
	ShirtColors = {
		Color3.fromRGB(220, 90, 90),
		Color3.fromRGB(90, 140, 220),
		Color3.fromRGB(240, 240, 240),
		Color3.fromRGB(150, 100, 200),
		Color3.fromRGB(240, 160, 60),
		Color3.fromRGB(70, 160, 140),
	},
	PantsColors = {
		Color3.fromRGB(50, 60, 90),
		Color3.fromRGB(40, 40, 45),
		Color3.fromRGB(120, 100, 80),
	},
}

-- Physics collision groups. Traffic hits player cars only: not the map, not other traffic.
Config.CollisionGroups = {
	Default = "Default", -- Roblox's built-in group (the map)
	Vehicles = "Vehicles", -- player cars
	Traffic = "Traffic",
	Bots = "Bots", -- AI rival taxis: bump player cars and each other, float over the map and ghost through traffic
	Walkers = "Walkers", -- people on foot (passenger mode): the map only, never cars, traffic or bots
}

Config.Keys = {
	Throttle = Enum.KeyCode.W,
	Brake = Enum.KeyCode.S,
	Left = Enum.KeyCode.A,
	Right = Enum.KeyCode.D,
	Drift = Enum.KeyCode.Space,
	Boost = Enum.KeyCode.LeftShift,
	Item = Enum.KeyCode.Q,
	Honk = Enum.KeyCode.H,
	Reset = Enum.KeyCode.R,
	Hop = Enum.KeyCode.E,
	PadThrottle = Enum.KeyCode.ButtonR2,
	PadBrake = Enum.KeyCode.ButtonL2,
	PadSteer = Enum.KeyCode.Thumbstick1,
	PadDrift = Enum.KeyCode.ButtonA,
	PadBoost = Enum.KeyCode.ButtonB,
	PadItem = Enum.KeyCode.ButtonX,
	PadHonk = Enum.KeyCode.ButtonY,
	PadReset = Enum.KeyCode.ButtonSelect,
	PadHop = Enum.KeyCode.ButtonR1,
}

Config.Round = {
	MinPlayers = 2, -- live servers wait for this many before a match starts
	StudioMinPlayers = 1, -- so a solo Studio run plays
	-- More drivers than grid pads (Config.Server caps them at the pad count, so only a debug cap gets here): each extra
	-- lap of drivers parks this many studs farther out to the side instead of on top of a car.
	ExtraSlotOffset = 20,
	AutoStartDelay = 10, -- seconds the depot's NEXT MATCH countdown runs once MinPlayers want to play
	PreCountdownSeconds = 3, -- "read the board": NPCs visible, cars frozen
	CountdownSeconds = 3, -- 3-2-1
	CapSeconds = 180, -- round time cap; highest earnings this round win at the cap
	Quotas = { 75, 100, 125 }, -- dollars earned THIS round (round 1, 2, 3); paced for 6-9 fares by a good player
	RoundsPerMatch = 3,
	RoundEndSeconds = 5, -- placements shown between a round and its Pit Stop
	MatchEndSeconds = 12, -- final podium; with PreCountdown and Countdown the gap to the next match stays under 20 s
	PodiumSeconds = 10, -- unused since Phase 3; kept for the solo loop
}

-- Server and lobby flow (owner spec 2026-10-27). One place, up to MaxPlayers people per server: MaxDrivers race, the
-- rest walk the city as passengers and hail cabs. Bots fill the grid to BotFillTo drivers, people always first.
-- The place's Max Players (Creator Hub > Configure > Places) must equal MaxPlayers.
Config.Server = {
	MaxPlayers = 10,
	MaxDrivers = 6, -- one per grid pad
	BotFillTo = 4, -- drivers per match, people + bots
}

-- Who drives when (MatchController). Priority for a free seat: a pre-assigned roster (TeleportData), then someone who
-- followed or was invited by a friend here, then whoever sat out the last match, then whoever has waited longest.
Config.Join = {
	LateJoinPenalty = 10, -- dollars: a late driver starts this far behind last place's round earnings (never below $0)
	PadClearance = 10, -- studs: a late driver's start pad has no car this close
	Driver = "YOU'RE IN! CATCH UP!",
	Rider = "RIDE ALONG UNTIL A SEAT OPENS",
	Queued = "YOU DRIVE NEXT ROUND. HAIL A CAB MEANWHILE",
	SeatOpened = "A SEAT OPENED. YOU'RE DRIVING!",
	NextRound = "YOUR SEAT IS READY",
}

-- People on foot (Passenger and Queued): a Roblox character on the sidewalk that cars pass straight through.
Config.Walkers = {
	SpawnOffset = 7, -- studs along the sidewalk from a pickup point, so a walker never stands on a waiting passenger
	CheckSeconds = 0.25, -- how often the server checks lanes and hail leashes
	RespawnSeconds = 3, -- after falling off the world
	LanePushSeconds = 2, -- this long in a traffic lane and you're put back on the sidewalk
	SidewalkInset = 3, -- studs in from the curb where you're put back
	DodgeDistance = 1.5, -- studs beside a car's path that still count as in its way...
	DodgeAhead = 10, -- ...within this far ahead of its front bumper: you dive out of the way
	DodgeMinSpeed = 8, -- only cars faster than this
	DodgeJump = 40, -- studs/s up...
	DodgeShove = 32, -- ...and away from the car
	DodgeCooldown = 1.2,
	DodgeLines = { "WHOA!", "YIKES!", "MISSED ME!", "HEY!" },
}

-- Player fares (owner spec 2026-10-27): someone on foot taps HAIL CAB at a curb and becomes a fare any cab can claim,
-- bots included. The ride pays the normal tier rules times PayMult; the rider rates the trip, which scales the tip.
Config.PlayerFare = {
	PayMult = 1.5,
	MaxOnBoard = 2, -- player fares waiting or riding at once, server-wide
	HailCooldown = 6, -- seconds between hails per person (a cancelled hail counts)
	HailCurbDistance = 6, -- studs from the road edge (on the sidewalk) where HAIL CAB shows
	HailLeash = 10, -- walk this far from where you hailed and the hail is off
	CurbInset = 1.5, -- the fare's spot: this far in from the curb, facing the road
	RatingSeconds = 8,
	RatingDefault = 4, -- stars when the rider doesn't tap
	RatingTipRange = { 0.8, 1.3 }, -- 1 star .. 5 stars: the tip times this
	RiderGems = 3, -- per ride delivered
	Color = Color3.fromRGB(255, 205, 50), -- the gold ring and minimap marker
	RingRadius = 3.5,
	Label = "TAXI!",
	HailButton = "HAIL CAB",
	CancelButton = "CANCEL",
	Busy = "CABS ARE BUSY. TRY AGAIN IN A BIT",
	SeatOffset = Vector3.new(1.1, 1.9, 0.9), -- the rider's root part from the cab's chassis (right, up, back)
	EjectSide = 7, -- studs beside the cab where a rider steps out
	DebugCurbDistance = 8, -- Studio "To curb" with a person hailing: the cab parks this far out, inside PickupRadius
	EjectHop = 30, -- studs/s up when a passenger bails (the cartoon toss)...
	EjectShove = 18, -- ...and sideways
	EjectSpin = 14, -- radians/s while tossed
	RideOverLines = { -- what a rider is told when the trip ends early (nothing when they called it off)
		hp = "THROWN OUT!",
		timeout = "TOO SLOW! YOU HOPPED OUT",
		released = "RIDE OVER",
		roundover = "RIDE OVER",
		cleared = "ROUND OVER",
	} :: { [string]: string },
	Thanks = "THANKS FOR THE RIDE! +%d GEMS",
	RatePrompt = "RATE YOUR DRIVER",
	TipLine = "%s RATED %d★  TIP x%.2f",
}

-- The Taxi Depot (owner spec 2026-10-27): free-roam yard beside the City (outside its walls and skyline, off the
-- minimap) where people drive their own car between matches: a drift loop, two ramps, a cone slalom, and a board with
-- this server's longest jump and best drift. No items, no passengers.
Config.Depot = {
	Center = Vector3.new(0, 0, -800), -- both maps; past the skyline ring (Config.Map.*.Blockout.SkylineOuter)
	Size = Vector2.new(260, 200), -- studs: X, Z
	WallHeight = 6,
	FenceHeight = 60, -- an invisible fence above the walls: nothing flies out of the yard
	FloorColor = Color3.fromRGB(70, 74, 82),
	LineColor = Color3.fromRGB(240, 200, 60),
	WallColor = Color3.fromRGB(230, 120, 40),
	ConeColor = Color3.fromRGB(255, 130, 30),
	Spawns = 10, -- parking bays, one per possible player, along the south wall facing north
	SpawnSpacing = 16,
	SpawnInset = 20, -- studs in from the south wall
	SpawnLift = 3.2, -- a parked car's center above the floor (as on the grid pads)
	FallDepth = 30, -- a depot car this far below the floor goes back to its bay
	-- Offsets from Center (+Z is south): a cone ring to drift around its island, two kickers launching north (Yaw 0)
	-- with the whole yard to land in, and a slalom down the east side.
	DriftLoop = { X = -75, Z = -25, Radius = 26, Island = 8, ConeGap = 4, Cones = 14 },
	Ramps = {
		{ X = 10, Z = 25, Yaw = 0, Height = 5, Length = 22, Width = 16 },
		{ X = 45, Z = 25, Yaw = 0, Height = 8, Length = 30, Width = 16 },
	},
	Slalom = { X = 105, ZFrom = 60, Count = 7, Spacing = 14, Offset = 5 }, -- cones alternating either side of X, northward
	ConeSize = Vector3.new(1.6, 3, 1.6),
	ConeResetSeconds = 20, -- knocked cones go back this often...
	ConeMoved = 1, -- ...when they've moved more than this many studs
	Board = { Width = 44, Height = 18, Lift = 2 }, -- over the north wall, facing the yard
	BoardTitle = "TAXI DEPOT",
	JumpLabel = "LONGEST JUMP",
	DriftLabel = "BEST DRIFT",
	NoRecord = "-",
	DriftGap = 0.8, -- seconds between drift reports that still count as one drift
	NextMatch = "NEXT MATCH IN %d:%02d",
	WaitingFor = "WAITING FOR DRIVERS",
	MatchRunning = "MATCH IN PROGRESS",
	SlotOpen = "OPEN",
	StayButton = "STAY IN DEPOT",
	JoinButton = "JOIN THE MATCH",
	Staying = "STAYING IN DEPOT",
	SlotBot = "BOT",
}

-- The COLLECTION panel (side stack): what you've unlocked and done, from your profile.
-- Map voting (checklist move 4, 2026-10-28): on a race's match-end podium everyone taps the next map
-- (Config.Map.Rotation); most votes wins, a tie with the rotation's own pick or no votes keeps that pick.
Config.MapVote = {
	Title = "NEXT MAP",
	Hint = "Tap to vote",
	Width = 200, -- px, the card right of the podium
	RowHeight = 44,
}

-- Roblox badges (checklist move 4, 2026-10-28), awarded by BadgesService. All five created in Creator Hub on
-- 2026-10-28 (the experience > Engagement > Badges, art from docs/badges). A new badge: create it there and paste its
-- id here; Id 0 = not created yet, nothing is awarded.
Config.Badges = {
	Level = 10, -- "Level10" badge at this level
	Order = { "FirstFare", "FirstWin", "Level10", "LegendLicense", "PhantomOwner" },
	List = {
		FirstFare = { Id = 3267473249403012, Name = "First Fare", Description = "Delivered your first passenger. The meter is running!" },
		FirstWin = { Id = 2467740453657469, Name = "Top Cab", Description = "Won a match in CrazyFare. Honk if you're winning!" },
		Level10 = { Id = 3831939711209788, Name = "Road Regular", Description = "Reached level 10 in CrazyFare." },
		LegendLicense = { Id = 779093546565712, Name = "Legend License", Description = "Earned a LEGEND license in a match." },
		PhantomOwner = { Id = 594834536870125, Name = "Phantom Rider", Description = "Owns the mythic Phantom horse." },
	} :: { [string]: { Id: number, Name: string, Description: string } },
}

-- Analytics (Creator Hub > Analytics), logged through src/server/Metrics.luau. The onboarding funnel is one step each,
-- once per account, in this order; Gems flows use Roblox's transaction types (IAP, Shop, Gameplay, TimedReward).
Config.Metrics = {
	Currency = "Gems",
	Onboarding = { "Joined", "PressedPlay", "Drove", "FirstPickup", "FirstDelivery", "FinishedMatch" },
	LevelPath = "Level",
	Events = {
		MatchFinished = "MatchFinished", -- value = place
		DropOpened = "DropOpened", -- value = rarity (1 Common .. 5 Mythic)
		PhantomOwned = "PhantomOwned", -- value = serial number
	},
	StudioLog = true, -- print each event in Studio (nothing is sent from Studio tests)
}

Config.Collection = {
	Button = "COLLECTION",
	Title = "COLLECTION",
	Cars = "CARS %d/%d",
	Cards = "WEIRDO CARDS %d/%d",
	BestLicense = "BEST LICENSE",
	Stats = { -- lifetime stats shown, in order (DataService Stats keys)
		{ Key = "Matches", Label = "MATCHES" },
		{ Key = "Wins", Label = "WINS" },
		{ Key = "Fares", Label = "FARES" },
		{ Key = "Knockouts", Label = "KNOCKOUTS" },
		{ Key = "Rides", Label = "RIDES TAKEN" },
	},
}

-- Title screen (owner ask 2026-10-27, after a creator's Minecraft-style menu): every join opens on a slow drone shot over
-- the live map (bots and players racing underneath) with the logo, a splash line and four buttons. PLAY places you
-- (MatchController). Arrivals by teleport from our own servers skip it, and so does Studio with the workspace attribute
-- SkipTitle = true. A loading screen (ReplicatedFirst) covers the join until the title is ready.
Config.Title = {
	-- the drone circles the map's center this far out and this high, looking at a point this high, once per period;
	-- high enough to clear the City's radio mast (153 studs, 241 out) and the hotel
	Drone = { Radius = 290, Height = 168, LookHeight = 10, PeriodSeconds = 110, Bob = 6, BobSeconds = 9 },
	SwoopSeconds = 1.3, -- PLAY: from the drone shot down behind your car (or your character)
	SwoopWaitSeconds = 4, -- ...which may take a moment to arrive; after this the camera goes without it
	Grade = { Tint = Color3.fromRGB(255, 224, 186), Saturation = 0.18, Contrast = 0.06, Brightness = 0.02, FadeSeconds = 1 },
	Logo = {
		Text = "CRAZYFARE",
		Font = Enum.Font.LuckiestGuy,
		Size = 104, -- px tall at full scale
		Width = 640, -- px: the letters shrink to fit this
		TopGap = 6, -- px below Roblox's top bar
		Top = Color3.fromRGB(255, 230, 70),
		Bottom = Color3.fromRGB(255, 136, 20),
		Outline = Color3.fromRGB(24, 18, 10),
		OutlineThickness = 6,
		Tilt = -3, -- degrees
		BobPixels = 6,
		BobSeconds = 2.8,
		Checks = 22, -- squares in the taxi stripe under it
		CheckSize = 14, -- px
	},
	Splash = {
		Color = Color3.fromRGB(255, 244, 60),
		Outline = Color3.fromRGB(60, 44, 0),
		Size = 26, -- px
		Tilt = -16, -- degrees
		Pulse = 0.08, -- grows and shrinks by this share
		PulseSeconds = 0.55, -- one beat
		Lines = {
			"TIP YOUR DRIVER!",
			"NOW 40% MORE BANANAS!",
			"SEATBELTS OPTIONAL!",
			"THE METER IS RUNNING!",
			"HONK IF YOU'RE WINNING!",
			"NO REFUNDS!",
			"KEEP THE CHANGE!",
			"TOMATO-PROOF. MOSTLY!",
			"WHERE TO, BOSS?",
			"FIVE STARS OR BUST!",
			"THE HORSE IS ALSO A TAXI!",
			"SHOPPING CART APPROVED!",
			"BRAKES SOLD SEPARATELY!",
			"DRIFT RESPONSIBLY!",
			"EST. THIS MORNING!",
			"MIND THE PASSENGER!",
			"ICE CREAM FOR THE ROAD!",
			"100% LICENSED. PROBABLY!",
			"LEFT AT THE PIZZA!",
			"THEY WILL RAGE-QUIT!",
		},
	},
	Buttons = { Play = "PLAY", Garage = "GARAGE", Options = "OPTIONS", Credits = "CREDITS" },
	ButtonWidth = 300, -- px
	PlayHeight = 58,
	ButtonHeight = 44,
	ButtonGap = 10,
	PlayColor = Color3.fromRGB(255, 196, 30),
	ButtonColor = Color3.fromRGB(28, 28, 36),
	-- the live line under the buttons, from the round state everyone gets
	LiveRound = "ROUND %d  \u{00B7}  %d DRIVING",
	LiveCountdown = "NEXT MATCH IN %d:%02d",
	LiveWaiting = "THE DEPOT IS OPEN",
	LivePitStop = "PIT STOP  \u{00B7}  %d DRIVING",
	FadeSeconds = 0.5, -- the menu fades away on PLAY
	PlayRetrySeconds = 3, -- PLAY works again after this if the server never answered
	-- the loading screen (ReplicatedFirst) before the title: up until the client has booted and the server placed you
	Loading = {
		Text = "LOADING THE CITY...",
		Background = Color3.fromRGB(16, 14, 22),
		SpinSeconds = 1.2, -- one turn of the tire
		MinSeconds = 1, -- stays at least this long (no flash)
		MaxSeconds = 30, -- gives up waiting after this
		PollSeconds = 0.1,
	},
	KeepAttribute = "TitleKeep", -- a ScreenGui with this attribute stays up over the title (its panels, the loading screen)
	SelfManagedAttribute = "ManagesOwnVisibility", -- a ScreenGui that shows and hides itself by state (left alone after)
	BootedAttribute = "ClientBooted", -- set on your own Player by the client once every controller has started
	CreatorFallback = "THE CRAZYFARE CREW", -- CREDITS when Roblox can't say who made the game (an unpublished Studio place)
	-- CREDITS: { heading, line }; "%s" in a line is the game's creator (from Roblox)
	CreditsTitle = "CREDITS",
	Credits = {
		{ "A GAME BY", "%s" },
		{ "CITY, HOUSES, CARS AND PROPS", "Kenney (kenney.nl)" },
		{ "MUSIC", "APM Music, via the Roblox Creator Store" },
		{ "SOUND EFFECTS", "Pro Sound Effects, via the Roblox Creator Store" },
		{ "THANKS FOR RIDING!", "" },
	} :: { { string } },
}

-- OPTIONS (title screen, and the side stack between matches): saved to your profile (Config.Data.Template.Settings).
Config.Options = {
	Title = "OPTIONS",
	Button = "OPTIONS", -- in the side stack
	VolumeSteps = { 0, 0.25, 0.5, 0.75, 1 }, -- times Config.Sounds.Volume / MusicVolume; a setting is an index here
	Labels = { Music = "MUSIC", Sfx = "SOUND", Shake = "CAMERA SHAKE", SpeedFx = "SPEED EFFECTS" },
	On = "ON",
	Off = "OFF",
	SaveDelay = 0.6, -- seconds after the last change before it's sent to the server
	MusicGroup = "CrazyFareMusic", -- SoundGroups in SoundService (client): the music, and every other sound
	SfxGroup = "CrazyFareSfx",
}

Config.Fares = {
	NpcsPerPlayer = 2,
	MinNpcs = 4,
	MaxNpcs = 12, -- never more than PickupPoints
	PickupRadius = 12, -- claim: inside this and slower than StopSpeed
	DebugCurbDistance = 14, -- Studio "To curb": the cab parks this far in front of the passenger, facing them
	DeliverRadius = 14,
	StopSpeed = 5,
	TakenNoticeRadius = 40, -- rivals inside this see "TAKEN"
	TierOrder = { "Green", "Yellow", "Red" },
	Tiers = {
		Green = { Base = 5, Hp = 60, Color = Color3.fromRGB(80, 220, 100), MinTrip = 60, MaxTrip = 190, Label = "SHORT" },
		Yellow = { Base = 10, Hp = 80, Color = Color3.fromRGB(250, 210, 60), MinTrip = 190, MaxTrip = 330, Label = "MEDIUM" },
		Red = { Base = 18, Hp = 100, Color = Color3.fromRGB(240, 70, 70), MinTrip = 330, MaxTrip = 9999, Label = "LONG" },
	} :: { [string]: TierDef },
	-- Spawn weighting by the PickupPoint's distance from the StartGrid center: greens near, reds far.
	TierWeightsByDistance = {
		{ MaxDistance = 150, Green = 70, Yellow = 25, Red = 5 },
		{ MaxDistance = 250, Green = 25, Yellow = 50, Red = 25 },
		{ MaxDistance = 9999, Green = 5, Yellow = 30, Red = 65 },
	} :: { TierWeightBand },
	TimeBase = 8, -- fare seconds = TimeBase + distance / TimeSpeed
	TimeSpeed = 30,
	TimeoutBails = true, -- timer at 0 = passenger bails, fare lost (owner call 2026-10-26 after playing both). false = passenger stays, tip gone, base paid on delivery
	ThanksSeconds = 2, -- delivered NPC lingers, then despawns
	RespawnDelay = 1, -- before a replacement NPC appears
	GuaranteeEachTier = true, -- a board of 3+ always holds at least one green, one yellow and one red
}

-- Passenger personalities. Every NPC rolls one when it spawns: its badge and minimap dot show it, the rider in the cab
-- acts it out, and its rules bend the fare.
Config.PassengerTypes = {
	Order = { "Regular", "ThrillSeeker", "Nervous" },
	Kinds = {
		Regular = { Weight = 60, Label = "PASSENGER", Icon = "$", Shirt = Color3.fromRGB(70, 130, 220), StuntMult = 1, CrashMult = 1, NoStuntTipMult = 1, SmoothTipMult = 1, TipLine = "" },
		ThrillSeeker = { Weight = 20, Label = "THRILL SEEKER", Icon = "\u{26A1}", Shirt = Color3.fromRGB(255, 120, 30), StuntMult = 2, CrashMult = 1, NoStuntTipMult = 0.5, SmoothTipMult = 1, TipLine = "NO THRILLS  TIP HALVED" },
		Nervous = { Weight = 20, Label = "NERVOUS", Icon = "\u{1F62C}", Shirt = Color3.fromRGB(150, 200, 230), StuntMult = 1, CrashMult = 1.5, NoStuntTipMult = 1, SmoothTipMult = 2, TipLine = "SMOOTH RIDE  TIP x2" },
	} :: { [string]: PassengerKindDef },
}

-- The Golden Fare: a rare passenger anyone on the map can race for. A gold beam marks the curb, everyone is told, and
-- it pays triple (base, and so the tip and the stunt cap). Only one is in play at a time.
Config.Golden = {
	Chance = 0.06, -- per NPC spawn while none is in play
	PayMult = 3,
	Color = Color3.fromRGB(255, 200, 40),
	Icon = "\u{2605}",
	Label = "GOLDEN",
	PayLine = "GOLDEN x3",
	Announce = "GOLDEN FARE!",
	AnnounceSub = "TRIPLE PAY",
	AnnounceSeconds = 1.6,
	BeamHeight = 90, -- studs: the gold pillar over the curb, seen from across the map
	BeamWidth = 3,
	RingRadius = 5,
	RiderSuit = Color3.fromRGB(28, 28, 34), -- the golden passenger rides in a black suit with a gold crown (gold on a yellow cab vanishes)
}

-- The rider: the passenger sits in your cab sunroof-style (head and shoulders out of the roof), dressed by their kind,
-- and reacts out loud. Everyone sees it, so rivals can read who you are carrying.
Config.Rider = {
	TorsoSize = Vector3.new(1.6, 1.6, 1),
	HeadSize = 1.3,
	ArmSize = Vector3.new(0.5, 1.4, 0.5),
	Sink = 0.35, -- torso center this far below the top of the car (roof sign included): chest and head ride above the roof
	BubbleDistance = 90, -- studs: a rival's passenger farther away than this says nothing on your screen
	LineSeconds = 1.2,
	LineCooldown = 4, -- a rider says at most one line per this many seconds (owner 2026-10-27: too many words at once)
	StuntLineChance = 0.3, -- chance a stunt gets a line (cheers, screams)
	PoseSeconds = 1.1, -- arms stay up this long after a stunt or a crash
	HurryAt = 10, -- seconds left on the fare: one "HURRY UP!" per ride
	BoredAt = 0.45, -- share of the fare timer gone with no stunt yet: a Thrill Seeker complains once
	Lines = {
		Stunt = {
			Regular = { "WHOA!", "NICE ONE!", "DO THAT AGAIN!", "OKAY, THAT WAS COOL", "YOU'RE NUTS!" },
			ThrillSeeker = { "WOOOO!", "FASTER!!", "AGAIN! AGAIN!", "BEST. RIDE. EVER.", "YEEHAW!", "SEND IT!" },
			Nervous = { "AAAAH!", "SLOW DOWN!", "I'M GONNA BE SICK", "HANDS ON THE WHEEL!", "MY LIFE IS FLASHING!" },
		},
		Crash = {
			Regular = { "OW!", "MY NECK!", "EYES ON THE ROAD!", "WAS THAT A WALL?!", "I SPILLED MY COFFEE!" },
			ThrillSeeker = { "HA! AGAIN!", "THAT'S GONNA BRUISE", "OOF! WORTH IT", "OW!" },
			Nervous = { "WE'RE GONNA DIE!", "I WANT MY MOM!", "THAT'S IT, NO TIP", "MY NECK!!" },
		},
		Hit = {
			Regular = { "GROSS!", "WHAT WAS THAT?!", "IS THAT A TOMATO?!", "HEY!" },
			ThrillSeeker = { "GET THEM BACK!", "WE'RE UNDER ATTACK!", "HA! MISSED ME" },
			Nervous = { "THEY'RE SHOOTING AT US!", "DUCK!!", "WHY ME?!" },
		},
		Hurry = { "HURRY UP!", "I'M LATE!", "STEP ON IT!", "TICK TOCK!", "IS THIS THE SCENIC ROUTE?" },
		Bored = { "BOOORING!", "IS THIS A TAXI OR A HEARSE?", "DO A FLIP OR SOMETHING", "MY GRANDMA DRIVES FASTER" },
		Golden = { "DRIVE! I'M LOADED!", "THERE'S A BIG TIP IN IT", "FIRST CLASS, PLEASE" },
	} :: { [string]: any },
}

-- AI rival taxis. With too few people, bots fill the match to Config.Server.BotFillTo drivers, and give their seats up
-- as real players join (a late driver takes a bot's seat at once). They follow every rule a player does (stop to claim, stop to deliver, items, standings) but
-- earn no stunt cash, gems or XP, and are always named with a BOT tag. Server-steered over the road grid.
Config.Bots = {
	Enabled = true,
	DebugChargeSpeed = 55, -- Studio "Bot charge": studs/s straight at you
	DebugStageSeconds = 6, -- how long a staged bot stays parked or charging
	IdBase = -1000, -- bot UserIds count down from here (Studio's test players are -1, -2...)
	MinHumans = 1, -- a live match starts with this many people when bots fill the rest
	Names = { "REX", "DOT", "ZIPPY", "MAMA CAB", "BOLT", "PICKLE" },
	Colors = {
		Color3.fromRGB(150, 80, 220),
		Color3.fromRGB(110, 200, 70),
		Color3.fromRGB(230, 70, 70),
		Color3.fromRGB(40, 170, 170),
		Color3.fromRGB(245, 140, 30),
		Color3.fromRGB(240, 100, 170),
	},
	Skills = { 0.8, 0.9, 1 }, -- one per bot in turn: scales cruise speed and how quickly it thinks
	VehicleId = "YellowCab",
	-- Driving (studs, studs/s, studs/s^2). The Yellow Cab tops out at 90, so a good driver outruns them.
	-- tuned 2026-10-27: at 52 the best bot made the $75 quota in 1:50, faster than the owner. 2026-10-28: shortcuts made
	-- bots ~30% quicker to the quota at 36 (6-bot soak: 136 s -> 94 s a round), so 30 brings the pace back
	CruiseSpeed = 30,
	CornerSpeed = 16,
	Accel = 30,
	Brake = 55, -- gentler than the crash watch's line, so a bot braking never reads as a crash
	RideHeight = 1.35, -- chassis center above the road
	MaxForce = 1000000,
	Responsiveness = 30,
	PassShift = 3.3, -- studs right of the center line when another bot comes the other way
	PassLook = 100, -- how far ahead it watches for that
	StopReach = 7, -- stops this far (sideways) from its passenger or drop-off
	MaxCurbOffset = 7.5, -- but never farther off the center line than this (the car's side stays on the road, off the sidewalk)
	FollowDistance = 32, -- cars and people in the road this far ahead slow it down
	CarClearance = 5.6, -- a car whose center is closer than this to the bot's line counts as in the way
	PlayerCarClearance = 7.5, -- wider for a person's car (two half-widths and a corner): a bot pushes hard, so it never brushes one
	PersonClearance = 7, -- the same for people crossing
	FollowGap = 13, -- stops this far behind what's in the way
	JunctionLook = 34, -- watches the next junction from this far out
	JunctionBox = 13, -- traffic crossing inside this half-size box around the junction makes it wait
	StuckLag = 10, -- the car this far behind its target (something in the way): the target waits
	StuckSeconds = 5, -- held up this long: the car is put back on its route
	SpinRate = 7, -- radians/s while a Banana spins it
	-- Shortcuts (owner 2026-10-28: "when I play I drive off the streets to reach destinations faster"): every so often a
	-- bot looks for the farthest point of its route (the stop at the end first) it can reach in a straight line, with
	-- nothing solid in the way at car height and ground all along (no big step, no water, no slow sand), and cuts straight there:
	-- corners, open lots, parks and the plaza. Better drivers look more often (ShortcutSeconds / skill^2).
	ShortcutSeconds = 0.7,
	ShortcutMax = 260, -- studs: the longest straight cut it considers
	ShortcutLift = 2.5, -- studs above the ground where the clearance box flies (over curbs, sidewalks and humps)
	ShortcutHalfHeight = 1,
	ShortcutHalfWidth = 3.2, -- half the car's width, plus a little
	ShortcutStep = 10, -- studs between ground checks along a cut
	ShortcutMaxRise = 3, -- studs the ground may rise or fall along a cut (ramps and roofs are not shortcuts)
	OnRoadReach = 12, -- within this of a road's center line it's on the road (crossing traffic at junctions matters)
	-- A car stopped in its way (another bot nose to nose after a shortcut, a parked player) for BlockedSeconds: it swings
	-- DodgeShift studs to one side for DodgeSeconds and goes around (the other side next time, if that didn't work).
	BlockedSeconds = 2,
	DodgeSeconds = 3,
	DodgeShift = 8.5, -- clear of PlayerCarClearance
	-- Brain
	ThinkSeconds = 0.8, -- base time between decisions (divided by skill)
	RouteFactor = 1.35, -- straight-line distance x this ~ the drive on the grid
	PickupOverhead = 4, -- seconds added to every pickup's drive when comparing them (stopping, boarding)
	Greed = 0.5, -- how much a passenger's fare counts when choosing (fare ^ Greed): 1 = always the long red trips, lower = nearer short ones
	GoldenBias = 1.5, -- a Golden Fare looks this much better again, on top of its pay
	Jitter = 0.15, -- +/- randomness on how good each passenger looks, so bots don't all pick the same
	ClaimWait = 3, -- seconds stopped at a curb without boarding: try another passenger
	RestMin = 1, -- seconds a bot sits after a delivery or a bail before picking its next passenger (players don't wait long)
	RestMax = 2.5,
	Choices = 3, -- picks one of its best few passengers (better ones likelier), not always the very best
	TipMult = 0.5, -- passengers tip bots half (they see the whole map and never crash; humans earn stunt cash instead)
	ItemUseChance = 0.5, -- chance per decision to use an item when there's a reason to
	ItemHoldMax = 12, -- seconds holding a trap before it gets dropped anyway
	TrapBehind = 45, -- a rival this close behind: drop the trap
	NitroStraight = 120, -- studs of straight road ahead before using a Lemon Nitro
}

-- Pit Stop: between rounds, spend this round's cash on next-round-only boosts. Unspent cash carries forward.
Config.PitStop = {
	Seconds = 30,
	ReadySeconds = 3, -- once every player taps READY, the Pit Stop ends this soon (owner 2026-10-27)
	CardsOffered = 5, -- Pit Stop Plus (Phase 6) makes this 6
	MaxBuys = 2, -- cards one player can buy per Pit Stop; the rich still have to choose
	-- Price = Share x the NEXT round's quota (round 2 = $100, round 3 = $125), so cards keep pace with the money and
	-- two picks cost about a whole round of banked cash. Unspent cash is quota progress, so buying is a real trade.
	PityDiscount = 0.3, -- last place pays this much less
	CarryFrac = 0.25, -- each new round starts with this share of your unspent cash as a head start toward the quota
	Cards = {
		SpeedTune = { Name = "Speed Tune", Effect = "+8% top speed", Share = 0.38, Value = 1.08 },
		BigTank = { Name = "Big Tank", Effect = "+50% boost tank", Share = 0.32, Value = 1.5 },
		StartItem = { Name = "Start Item", Effect = "Start the round holding an item", Share = 0.26, Value = 1 },
		ArmoredSeats = { Name = "Armored Seats", Effect = "Passengers take 25% less damage", Share = 0.38, Value = 0.75 },
		TipJar = { Name = "Tip Jar", Effect = "Tips +25%", Share = 0.44, Value = 1.25 },
		ExtraWiper = { Name = "Extra Wiper", Effect = "Splats clear twice as fast", Share = 0.22, Value = 0.5 },
	} :: { [string]: PitStopCardDef },
}

-- Gems: paid at match end (Phase 4 persists them). Never spendable mid-match.
Config.Gems = {
	Placement = { 12, 8, 5, 3, 2, 1 }, -- by final placement; beyond the list pays the last entry
	PerFare = 1,
}

Config.Tips = {
	MaxFrac = 0.8, -- a perfect ride tips 80% of base
	TimeWeight = 0.5, -- speedy share
	ChillWeight = 0.5, -- chill share
	TimeFloor = 0.15, -- fraction of timer remaining where the speedy tip starts
	TimeCeil = 0.85, -- fraction where it maxes
	HpFloor = 0.4, -- passenger HP fraction where the chill tip starts
}

-- Live stunt tips (ComboService validates, FareService pays). Every stunt the server accepts adds one to the chain and
-- pays cash into the current fare at once; each chain step past the first pays ChainBonus more. A crash that hurts the
-- passenger (Config.Passenger.CrashMinIntensity), a bail, a new round or ChainIdleSeconds without a stunt breaks it.
Config.Stunts = {
	Names = { Drift = "DRIFT!", Airtime = "BIG AIR!", NearMiss = "NEAR MISS!" } :: { [string]: string },
	Pay = { Drift = 1, Airtime = 2, NearMiss = 1 } :: { [string]: number }, -- dollars: Drift and Airtime per UnitSeconds, NearMiss per miss
	UnitSeconds = 0.5, -- the client reports drift in ticks this long; air pays per this much hang time
	DriftChainSeconds = 1, -- a long drift adds one to the chain per this much drifting
	MaxDriftReport = 1, -- seconds the server accepts in one drift report
	MaxAirSeconds = 3, -- seconds the server accepts in one airtime report
	ChainBonus = 0.1, -- x1 pays the base; x10 pays +90%
	ChainMax = 10,
	ChainIdleSeconds = 4, -- no stunt for this long ends the chain
	HoldUntilDelivery = true, -- true: stunt cash rides in the fare, paid on delivery, lost on a bail. false: banked at once
	MaxPerFareFrac = 2, -- stunt cash per fare tops out at this many times the fare's base (stunts are client-reported)
	NearMissMinSpeed = 45,
	MinSpeedForEvents = 20, -- server rejects stunt reports while slower than this
	MaxEventsPerSecond = 8,
	-- HUD
	PopupSeconds = 0.9, -- a popup rises and fades over this
	PopupMergeSeconds = 0.7, -- the same stunt again inside this tops up its popup instead of stacking a new one
	PopupRise = 70, -- pixels a popup climbs over its life
	PopupStack = 34, -- pixels between stacked popups
	LostSeconds = 1.1, -- "COMBO LOST" shows this long
	HotChain = 5, -- from this chain the counter turns orange
	BlazingChain = 8, -- and from this, red
	CoinPitchPerChain = 0.05, -- the coin sound climbs this much per chain step
}

-- Ambient traffic (TrafficService): server cars cruising the road grid in right-hand lanes, turning at intersections.
-- Hitting one is a crash like any wall; slipping past one at speed counts as a near miss.
Config.Traffic = {
	Count = 24, -- vehicles per map, split across Kinds by Weight
	SpeedMin = 18, -- cruise speeds are spread evenly across this range so no two cars match (studs/s; the Yellow Cab tops out at 90)
	SpeedMax = 50,
	Accel = 12, -- studs/s^2 back up to cruise
	Brake = 40, -- studs/s^2 when closing on a slower car ahead
	FollowSlack = 12.5, -- clear road between bumpers where a car starts matching the car ahead; bumper to bumper it stops
	MinImpactSpeed = 15, -- closing speed into a traffic car that counts as a crash (at least a small one); below is a nudge
	JunctionApproach = 60, -- inside this distance of the next intersection's center a car claims it, or stops to wait its turn
	JunctionClear = 24, -- a car holds the intersection until its lane point is this far past the center
	StopLine = 25, -- a waiting car stops with its lane point this far from the center: clear of the crossing lanes and behind the crosswalk
	PedestrianStopDistance = 45, -- someone crossing this far ahead: the car stops for them (a car at full cruise needs ~31 to stop)
	PedestrianLaneHalf = 13, -- either side of the lane line that counts: the whole crossing, not just the car's own lane
	PlayerStopDistance = 50, -- a player car in its lane this far ahead: the car brakes for it (or follows it if it pulls away)
	PlayerLaneHalf = 8, -- either side of the lane line where a player car would be hit (a curb-parked cab is in the lane)
	PlayerStopGap = 16, -- lane point to player car center when stopped behind it
	LaneOffset = 6, -- lane center from the road center line
	StraightWeight = 2, -- odds at an intersection: straight vs each possible turn
	TurnWeight = 1,
	SpawnClearance = 70, -- no car spawns this close to a start pad
	SpawnSpacing = 45, -- nor this close to another traffic car
	SpawnTries = 30,
	-- What drives around. Sizes are the collider; longer vehicles stop farther back at junctions and hold them longer.
	Kinds = {
		Sedan = { Size = Vector3.new(6, 2.4, 11.5), Weight = 14, Density = 3, MaxSpeed = 50 },
		Van = { Size = Vector3.new(6.4, 4.6, 13), Weight = 6, Density = 2.2, MaxSpeed = 44 },
		Bus = { Size = Vector3.new(7.6, 6, 26), Weight = 4, Density = 1.2, MaxSpeed = 34 },
	} :: { [string]: { Size: Vector3, Weight: number, Density: number, MaxSpeed: number } },
	KindOrder = { "Sedan", "Van", "Bus" },
	BusColors = { Color3.fromRGB(245, 190, 40), Color3.fromRGB(40, 150, 140), Color3.fromRGB(215, 60, 55) },
	RideHeight = 0.85, -- gap under the body (the wheels fill it)
	MaxForce = 1000000, -- AlignPosition / AlignOrientation strength that keeps it in its lane
	Responsiveness = 25,
	ResetDistance = 40, -- knocked this far from its lane point, it snaps back
	BlockedLag = 6, -- body this far behind its lane point (a player car in the way): the car waits, and so does the queue behind it
	BlockedRespawn = 5, -- seconds blocked (or queued behind a blocked car) before it respawns elsewhere so the lane clears
	JunctionOccupiedHalf = 13, -- a racer's car within this of an intersection's center: traffic waits at the line
	Colors = {
		Color3.fromRGB(235, 235, 235),
		Color3.fromRGB(170, 175, 185),
		Color3.fromRGB(45, 60, 110),
		Color3.fromRGB(120, 35, 40),
		Color3.fromRGB(50, 95, 60),
		Color3.fromRGB(60, 62, 68),
		Color3.fromRGB(110, 150, 200),
		Color3.fromRGB(200, 180, 140),
	},
}

Config.Passenger = {
	-- No regen: passenger HP only goes down during a ride, so every crash and hit sticks (owner, 2026-10-26).
	CrashDeltaThreshold = 24, -- horizontal speed (studs/s) lost inside CrashWindow that starts an impact (under every car's hurt line; braking cannot reach it)
	CrashWindow = 0.12, -- seconds of speed history the crash watch looks back over: a wall stops the car inside ~0.05 s on the server, while full braking (BrakeAccel) loses under 10 studs/s here even with bursty replication (0.25 s let a hard brake read as a crash)
	CrashSettle = 0.1, -- seconds the watch keeps measuring once a hit starts, so the whole stop counts (the server sees it over ~3 frames)
	-- Crash damage is a share of the trip's base HP (Fares.Tiers.Hp), set by how much of the car's top speed the hit took:
	CrashMinIntensity = 0.33, -- share of top speed lost that starts to hurt; a crash this size takes CrashMinShare (3 to bail)
	CrashFullIntensity = 0.85, -- share of top speed lost that bails the passenger outright (full speed into a wall)
	CrashMinShare = 0.34, -- share of base HP the smallest hurting crash takes; harder crashes scale up to all of it (2 to bail past ~half)
	DamageCooldown = 1, -- no second damage inside this window (any source)
	BoostEndGrace = 0.5, -- crash watch ignores the speed bleed right after a nitro ends
	SelfHitCost = 15, -- using an attack item while loaded
	BailWalkSpeed = 12,
	BailBubbleSeconds = 3,
	AngryLines = {
		"I'M WALKING!",
		"WORST. RIDE. EVER.",
		"ONE STAR.",
		"LET ME OUT!!",
		"MY LAWYER WILL HEAR ABOUT THIS",
		"I'VE HAD SMOOTHER EARTHQUAKES",
		"TIME'S UP, I'M OUT",
	},
	ThanksLines = { "THANKS!", "FIVE STARS", "YOU'RE A LEGEND", "SMOOTH." },
}

Config.Items = {
	BoxRespawnSeconds = 10,
	BoxRadius = 7, -- pickup distance from the box center
	BoxSpinSpeed = 2, -- radians/s, cosmetic
	Pool = {
		Tomato = { Kind = "attack", DisplayName = "Tomato", Color = Color3.fromRGB(230, 60, 50) },
		Banana = { Kind = "trap", DisplayName = "Banana", Color = Color3.fromRGB(250, 220, 70) },
		LemonNitro = { Kind = "boost", DisplayName = "Lemon Nitro", Color = Color3.fromRGB(240, 250, 90) },
		OilSlick = { Kind = "trap", DisplayName = "Oil Slick", Color = Color3.fromRGB(40, 36, 48) },
		Shield = { Kind = "defense", DisplayName = "Shield", Color = Color3.fromRGB(90, 200, 255) },
		Seatbelt = { Kind = "defense", DisplayName = "Seatbelt", Color = Color3.fromRGB(120, 240, 150) },
	} :: { [string]: ItemDef },
	-- Roll weights by quota rank bucket. Every pool item must appear in every bucket.
	RankWeights = {
		Leader = { Tomato = 8, Banana = 20, OilSlick = 17, LemonNitro = 25, Shield = 18, Seatbelt = 12 },
		Mid = { Tomato = 17, Banana = 17, OilSlick = 16, LemonNitro = 17, Shield = 17, Seatbelt = 16 },
		Last = { Tomato = 40, Banana = 15, OilSlick = 10, LemonNitro = 15, Shield = 10, Seatbelt = 10 },
	} :: { [string]: { [string]: number } },
	SelfCostItems = { Tomato = true } :: { [string]: boolean },
	Tomato = {
		Speed = 130,
		TurnRate = 5, -- radians/s of homing
		LockRange = 400, -- nearest rival inside this at launch (loaded rivals preferred)
		HitRadius = 7,
		Lifetime = 4,
		Damage = 1000, -- always bails: more than any passenger's HP even through armor (Shield blocks it, Seatbelt ignores it)
		SplatCoverage = 0.7,
		WipeSeconds = 3,
		HonkWipeBonus = 0.6, -- each honk removes this many seconds of splat
		LaunchHeight = 2,
	},
	Banana = {
		Damage = 25,
		SpinSeconds = 1.5,
		TriggerRadius = 4.5,
		Lifetime = 45,
		OwnerImmunity = 1.5,
		DropBack = 8, -- studs behind the rear bumper
	},
	LemonNitro = {
		Seconds = 3,
		SpeedMult = 1.35,
		AccelMult = 1.6,
	},
	OilSlick = {
		Damage = 10,
		Seconds = 2, -- no steering
		TriggerRadius = 5,
		Lifetime = 45,
		OwnerImmunity = 1.5,
		DropBack = 8,
		Transparency = 0.35, -- low visibility on the road
	},
	Shield = {
		Blocks = 1, -- hits absorbed before it breaks
	},
	Seatbelt = {
		Seconds = 8, -- passenger immune to all damage
	},
	HunterBonusFrac = 0.4, -- attacker gets this share of a fare they made bail
	Prop = {
		KnockSpeed = 70, -- studs/s given to a tagged prop hit by a projectile
		KnockLift = 0.35, -- fraction of that speed added upward
	},
}

Config.Vehicles = {
	Default = "YellowCab",
	-- Sidegrades: roughly equal budgets, one gimmick each. Order here is the garage order.
	Order = { "YellowCab", "GoKart", "ShoppingCart", "Horse", "NightCab", "IceCreamTruck", "RocketCab", "ArmoredLimo", "Phantom" },
	Stats = {
		YellowCab = {
			DisplayName = "Yellow Cab",
			Description = "The classic. No tricks.",
			WheelType = "wheels",
			TopSpeed = 90,
			Accel = 45,
			Handling = 6,
			DriftGrip = 0.25,
			BoostTank = 4,
			SteerMax = 32,
			Gimmick = "none",
			Color = Color3.fromRGB(255, 182, 72), -- the Kenney cab's own yellow (what shows with no paint)
			-- the imported cab's palette with its yellow swatch see-through (assets/paint/taxi-colormap-paintable.png,
			-- uploaded as image 85199325967163), so garage and drop paints color the body and nothing else
			PaintSkin = "YellowCab",
			GemPrice = 0,
		},
		GoKart = {
			DisplayName = "Go-Kart",
			Description = "Grips like glue in a drift.",
			WheelType = "wheels",
			TopSpeed = 88,
			Accel = 50,
			Handling = 6.5,
			DriftGrip = 0.45,
			BoostTank = 3.5,
			SteerMax = 34,
			Gimmick = "driftgrip",
			Color = Color3.fromRGB(230, 60, 60),
			GemPrice = 300,
		},
		ShoppingCart = {
			DisplayName = "Shopping Cart",
			Description = "Bananas can't touch it. Wobbles.",
			WheelType = "wheels",
			TopSpeed = 84,
			Accel = 48,
			Handling = 5,
			DriftGrip = 0.3,
			BoostTank = 4,
			SteerMax = 34,
			Gimmick = "bananaimmune",
			Color = Color3.fromRGB(170, 175, 185),
			GemPrice = 150,
			ImmuneTo = { Banana = true },
			Wobble = 0.18,
		},
		Horse = {
			DisplayName = "Horse",
			Description = "Space hops. Quick off the line, slow on the straight.",
			WheelType = "legs",
			TopSpeed = 76,
			Accel = 62,
			Handling = 8,
			DriftGrip = 0.25,
			BoostTank = 4,
			SteerMax = 36,
			Gimmick = "hop",
			Color = Color3.fromRGB(120, 80, 50),
			GemPrice = 350,
			Hop = true,
			HopPower = 42,
		},
		NightCab = {
			DisplayName = "Night Cab",
			Description = "Passengers take 20% less damage.",
			WheelType = "wheels",
			TopSpeed = 90,
			Accel = 45,
			Handling = 6,
			DriftGrip = 0.25,
			BoostTank = 4,
			SteerMax = 32,
			Gimmick = "armor",
			Color = Color3.fromRGB(30, 32, 44),
			TintMesh = true,
			GemPrice = 400,
			PassengerDamageMult = 0.8,
		},
		IceCreamTruck = {
			DisplayName = "Ice Cream Truck",
			Description = "Passengers board with +20 HP.",
			WheelType = "wheels",
			TopSpeed = 86,
			Accel = 42,
			Handling = 5.5,
			DriftGrip = 0.3,
			BoostTank = 5,
			SteerMax = 30,
			Gimmick = "hpbonus",
			Color = Color3.fromRGB(240, 235, 225),
			GemPrice = 400,
			PassengerHpBonus = 20,
		},
		-- Robux only (pay-to-win): faster and tougher than anything Gems buy
		RocketCab = {
			DisplayName = "Rocket Cab",
			Description = "Fastest car in the city. Huge boost tank.",
			WheelType = "wheels",
			TopSpeed = 105,
			Accel = 55,
			Handling = 6.5,
			DriftGrip = 0.3,
			BoostTank = 6,
			SteerMax = 32,
			Gimmick = "rocket",
			Color = Color3.fromRGB(235, 70, 40),
			GemPrice = 0,
			RobuxOnly = true,
		},
		ArmoredLimo = {
			DisplayName = "Armored Limo",
			Description = "Passengers board with +40 HP and take 30% less damage.",
			WheelType = "wheels",
			TopSpeed = 92,
			Accel = 46,
			Handling = 6,
			DriftGrip = 0.25,
			BoostTank = 4.5,
			SteerMax = 30,
			Gimmick = "armor",
			Color = Color3.fromRGB(28, 28, 34),
			GemPrice = 0,
			RobuxOnly = true,
			PassengerDamageMult = 0.7,
			PassengerHpBonus = 40,
		},
		-- The mythic ghost horse (owner 2026-10-28: "a horse to be a top OP pick ... kids will easily recognize that it
		-- is valuable"). About 1 in 10,000 drops, or Robux during an offer window. Strong, and painted as a target.
		Phantom = {
			DisplayName = "The Phantom",
			Description = "Mythic. Fastest thing in town. Passengers +60 HP, 60% less damage. Bananas and Oil? Never heard of them.",
			WheelType = "legs",
			TopSpeed = 115,
			Accel = 66,
			Handling = 8.5,
			DriftGrip = 0.3,
			BoostTank = 8,
			SteerMax = 36,
			Gimmick = "phantom",
			Color = Color3.fromRGB(22, 20, 30),
			GemPrice = 0,
			RobuxOnly = true,
			Hop = true,
			HopPower = 48,
			ImmuneTo = { Banana = true, OilSlick = true },
			PassengerDamageMult = 0.4,
			PassengerHpBonus = 60,
			BuiltInShield = true,
			Mythic = true,
			FlameColor = Color3.fromRGB(170, 80, 255),
			EngineSound = 0, -- slot: its own engine loop
		},
	} :: { [string]: VehicleStats },
	-- The Phantom's rules and looks (its stats are Stats.Phantom; systems read the Mythic / BuiltInShield flags)
	Phantom = {
		ShieldRecharge = 20, -- seconds after the shield blocks a hit
		HunterMult = 3, -- Hunter Bonus times this when a Phantom's passenger bails (on top of the leader bounty)
		Glow = Color3.fromRGB(170, 80, 255), -- eyes, mane, tail, hooves, underglow
		GlowRange = 14, -- studs: the underglow light
		SparkRate = 14, -- hoof sparks per second
		BubbleColor = Color3.fromRGB(190, 120, 255),
		BubbleTransparency = 0.72,
		BubblePadding = 2.5, -- studs around the body
		MarkerColor = Color3.fromRGB(200, 100, 255), -- the pulsing ring on every minimap
		MarkerSize = 24, -- px
		MarkerStroke = 2, -- px
		MarkerPulseGrow = 0.6, -- the ring grows by this fraction as it fades
		MarkerPulseSeconds = 1.2,
		EnteredBanner = "A PHANTOM HAS ENTERED THE MATCH",
		OwnersLine = "ONLY %d OWN THE PHANTOM",
		OneOwnerLine = "ONLY 1 OWNS THE PHANTOM",
		NoOwnersLine = "NOBODY OWNS ONE YET",
		DropOnlyLine = "MYTHIC DROP ONLY",
		DropOnlyButton = "DROP ONLY", -- the buy button outside the offer window
		OfferLine = "R$ OFFER: %s LEFT",
		OpenOfferLine = "ON SALE NOW", -- an offer with no end date
		YoursLine = "YOURS IS #%d", -- the Garage row once you own it
		SerialLine = "#%d",
		BoardTitle = "PHANTOM OWNERS",
		OwnersStore = "CF_PhantomOwners", -- OrderedDataStore: UserId -> serial
		SerialStore = "CF_PhantomSerial", -- DataStore: the last serial handed out (= owners so far; reread with the boards)
		CountAttribute = "PhantomOwners", -- workspace attribute every client reads
		ShieldAttribute = "PhantomShieldAt", -- player attribute: server time the shield is charged again (0 = now)
	},
}

-- Permanent upgrades (Gems), global across vehicles in v1. Applied as player attributes Up_<Name> = 1 + Per * level.
Config.Upgrades = {
	Order = { "Speed", "Handling", "Boost" },
	-- 10 levels (pay-to-win: Gem packs and Max Upgrades are the fast way up); the server's speed check follows Per * Max
	Speed = { Per = 0.025, Max = 10, Costs = { 60, 90, 130, 180, 240, 320, 420, 540, 680, 850 } },
	Handling = { Per = 0.03, Max = 10, Costs = { 60, 90, 130, 180, 240, 320, 420, 540, 680, 850 } }, -- +30% at 10 (more grip rolls the car in hard turns)
	Boost = { Per = 0.08, Max = 10, Costs = { 50, 80, 120, 170, 230, 300, 390, 500, 630, 800 } },
} :: { Order: { string }, [string]: any }

-- Cosmetics v1: paint. One price, pick any colour; "" = the vehicle's own colour.
Config.Paint = {
	Price = 50,
	Colors = {
		{ Name = "Cherry", Color = Color3.fromRGB(220, 50, 60) },
		{ Name = "Mint", Color = Color3.fromRGB(110, 230, 170) },
		{ Name = "Sky", Color = Color3.fromRGB(90, 170, 250) },
		{ Name = "Grape", Color = Color3.fromRGB(150, 80, 220) },
		{ Name = "Snow", Color = Color3.fromRGB(245, 245, 245) },
		{ Name = "Midnight", Color = Color3.fromRGB(25, 25, 35) },
		-- drop-only (Config.Drops): not in the Garage's paint shop (the daily shop may rotate them in), free once owned
		{ Name = "Sunset", Color = Color3.fromRGB(255, 120, 60), DropOnly = true },
		{ Name = "Lime", Color = Color3.fromRGB(170, 240, 60), DropOnly = true },
		{ Name = "Bubblegum", Color = Color3.fromRGB(255, 130, 210), DropOnly = true },
		{ Name = "Teal", Color = Color3.fromRGB(30, 190, 180), DropOnly = true },
		-- drop-only with a material of their own (D2)
		{ Name = "Frost", Color = Color3.fromRGB(170, 220, 255), DropOnly = true, Material = Enum.Material.Ice },
		{ Name = "Chrome", Color = Color3.fromRGB(205, 210, 220), DropOnly = true, Material = Enum.Material.Metal },
		{ Name = "Laser", Color = Color3.fromRGB(255, 60, 200), DropOnly = true, Material = Enum.Material.Neon },
		{ Name = "Gold", Color = Color3.fromRGB(255, 200, 60), DropOnly = true, Material = Enum.Material.Foil },
		-- level rewards (Config.Levels): never for sale and never in drops; the Garage teases the next one
		{ Name = "Bronze", Color = Color3.fromRGB(205, 127, 50), DropOnly = true, Material = Enum.Material.Metal },
		{ Name = "Silver", Color = Color3.fromRGB(190, 196, 206), DropOnly = true, Material = Enum.Material.Foil },
		{ Name = "Platinum", Color = Color3.fromRGB(229, 228, 226), DropOnly = true, Material = Enum.Material.DiamondPlate },
		{ Name = "Diamond", Color = Color3.fromRGB(150, 230, 255), DropOnly = true, Material = Enum.Material.Glass },
	} ::{ { Name: string, Color: Color3, DropOnly: boolean?, Material: Enum.Material? } },
	MaterialMark = "\u{2726}", -- on a material paint's swatch in the Garage
}

-- Cosmetics won in drops (Config.Drops, owner spec 2026-10-28, D2): trails behind your car, horns for your honk, and
-- Weirdo cards. Trails and horns are equipped from the Garage (owned only); cards fill COLLECTION, and a card you didn't
-- have queues its weirdo as a bonus fare in your next round (Cards.Bonus). All names and looks are original.
Config.Cosmetics = {
	-- the weekly leaderboard trail (Config.Leaderboards.WeeklyTrailTop) wins over an equipped one
	WeeklyTrail = { Color3.fromRGB(255, 215, 80), Color3.fromRGB(255, 120, 30) } :: { Color3 },
	TrailLook = { Transparency = 0.2, Lifetime = 0.6, LightEmission = 0.8, MinLength = 0.2 },
	TrailOrder = { "Mint", "HotSauce", "Galaxy", "Toxic", "Rainbow" },
	Trails = {
		Mint = { Name = "MINT BREEZE", Rarity = "Rare", Weight = 8, Colors = { Color3.fromRGB(110, 230, 170), Color3.fromRGB(230, 255, 245) } },
		HotSauce = { Name = "HOT SAUCE", Rarity = "Rare", Weight = 8, Colors = { Color3.fromRGB(255, 60, 40), Color3.fromRGB(255, 170, 40) } },
		Galaxy = { Name = "GALAXY", Rarity = "Epic", Weight = 8, Colors = { Color3.fromRGB(120, 60, 255), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 90, 200) } },
		Toxic = { Name = "TOXIC", Rarity = "Epic", Weight = 8, Colors = { Color3.fromRGB(150, 255, 60), Color3.fromRGB(40, 120, 20) } },
		Rainbow = {
			Name = "RAINBOW",
			Rarity = "Legendary",
			Weight = 20,
			Colors = {
				Color3.fromRGB(255, 60, 60),
				Color3.fromRGB(255, 160, 40),
				Color3.fromRGB(255, 230, 60),
				Color3.fromRGB(80, 220, 100),
				Color3.fromRGB(60, 140, 255),
				Color3.fromRGB(170, 80, 255),
			},
		},
		-- won by playing, never in drops (they're not in TrailOrder): DAY 7 of the streak, then level rewards
		OnFire = { Name = "ON FIRE", Rarity = "Epic", Weight = 0, Colors = { Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 150, 30), Color3.fromRGB(200, 30, 20), Color3.fromRGB(60, 10, 10) } },
		Checkered = { Name = "CHECKERED", Rarity = "Epic", Weight = 0, Colors = { Color3.fromRGB(245, 245, 245), Color3.fromRGB(20, 20, 24), Color3.fromRGB(245, 245, 245), Color3.fromRGB(20, 20, 24) } },
		Afterburner = { Name = "AFTERBURNER", Rarity = "Legendary", Weight = 0, Colors = { Color3.fromRGB(230, 245, 255), Color3.fromRGB(60, 140, 255), Color3.fromRGB(30, 40, 160) } },
		HallOfFame = { Name = "HALL OF FAME", Rarity = "Legendary", Weight = 0, Colors = { Color3.fromRGB(255, 215, 80), Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 80, 255) } },
		MaxedOut = { Name = "MAXED OUT", Rarity = "Mythic", Weight = 0, Colors = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(255, 215, 80), Color3.fromRGB(60, 220, 255) } },
	} :: { [string]: TrailDef },
	EarnedTrailOrder = { "OnFire", "Checkered", "Afterburner", "HallOfFame", "MaxedOut" }, -- after TrailOrder in the Garage
	-- Roblox-licensed Pro Sound Effects clips from the Creator Store (picked 2026-10-28); only you hear your horn
	HornOrder = { "Squeaky", "EuroBeep", "Bus", "BigRig", "Kazoo", "ChooChoo", "Ferry" },
	Horns = {
		Squeaky = { Name = "SQUEAKY", Rarity = "Common", Weight = 4, Sound = 9113438364 }, -- Bike Horn Squeeze 1
		EuroBeep = { Name = "EURO BEEP", Rarity = "Common", Weight = 4, Sound = 9120383448 }, -- Vehicle Horn Honk European Buzzing Whine 1
		Bus = { Name = "BIG BUS", Rarity = "Common", Weight = 4, Sound = 9114661198 }, -- Greyhound Bus Horn Honks Short Long 1
		BigRig = { Name = "BIG RIG", Rarity = "Rare", Weight = 6, Sound = 9114075901 }, -- Diesel Truck Horn Air Horn Exterior 3
		Kazoo = { Name = "KAZOO", Rarity = "Rare", Weight = 6, Sound = 9114898328 }, -- Kazoo Fanfare 2
		ChooChoo = { Name = "CHOO CHOO", Rarity = "Epic", Weight = 6, Sound = 9120250368 }, -- Train Horn 2
		Ferry = { Name = "FERRY", Rarity = "Epic", Weight = 6, Sound = 9114406881 }, -- Ferry Boat Horn Medium Cu Clean Twice 2
	} :: { [string]: HornDef },
	CardOrder = {
		"PirateCaptain",
		"Ghost",
		"Mime",
		"Chef",
		"RollerGrandma",
		"TeamMascot",
		"Knight",
		"OperaSinger",
		"AlienTourist",
		"WeddingParty",
		"Magician",
		"Astronaut",
	},
	Cards = {
		PirateCaptain = { Name = "PIRATE CAPTAIN", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(150, 30, 40), Hat = Color3.fromRGB(25, 25, 30), Icon = "\u{2620}" },
		Ghost = { Name = "GHOST", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(235, 240, 255), Hat = Color3.fromRGB(235, 240, 255), Icon = "\u{1F47B}" },
		Mime = { Name = "MIME", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(245, 245, 245), Hat = Color3.fromRGB(20, 20, 24), Icon = "\u{1F3AD}" },
		Chef = { Name = "CHEF", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(250, 250, 250), Hat = Color3.fromRGB(255, 255, 255), Icon = "\u{1F373}" },
		RollerGrandma = { Name = "ROLLER GRANDMA", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(255, 140, 200), Hat = Color3.fromRGB(190, 160, 255), Icon = "\u{1F475}" },
		TeamMascot = { Name = "TEAM MASCOT", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(255, 200, 40), Hat = Color3.fromRGB(40, 90, 220), Icon = "\u{1F4E3}" },
		Knight = { Name = "KNIGHT", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(170, 175, 185), Hat = Color3.fromRGB(140, 145, 155), Icon = "\u{1F6E1}" },
		OperaSinger = { Name = "OPERA SINGER", Rarity = "Rare", Weight = 5, Shirt = Color3.fromRGB(150, 30, 90), Hat = Color3.fromRGB(255, 215, 80), Icon = "\u{1F3A4}" },
		AlienTourist = { Name = "ALIEN TOURIST", Rarity = "Epic", Weight = 6, Shirt = Color3.fromRGB(120, 230, 90), Hat = Color3.fromRGB(255, 120, 200), Icon = "\u{1F47D}" },
		WeddingParty = { Name = "WEDDING PARTY", Rarity = "Epic", Weight = 6, Shirt = Color3.fromRGB(255, 255, 255), Hat = Color3.fromRGB(255, 230, 240), Icon = "\u{1F48D}" },
		Magician = { Name = "MAGICIAN", Rarity = "Epic", Weight = 6, Shirt = Color3.fromRGB(60, 30, 90), Hat = Color3.fromRGB(20, 20, 24), Icon = "\u{1F3A9}" },
		Astronaut = { Name = "ASTRONAUT", Rarity = "Epic", Weight = 6, Shirt = Color3.fromRGB(235, 235, 240), Hat = Color3.fromRGB(60, 140, 255), Icon = "\u{1F680}" },
	} :: { [string]: CardDef },
	-- A new card's weirdo: once, a few seconds into your next round, at a free curb. Only you see their badge and dot,
	-- and only you can pick them up, for HeadStartSeconds; then everyone can.
	Bonus = {
		Tier = "Red",
		PayMult = 2, -- times the tier's base pay
		SpawnDelay = 6, -- seconds after GO
		HeadStartSeconds = 20,
		HatSize = Vector3.new(1.3, 0.6, 1.3),
		PayLine = "WEIRDO BONUS",
		Notice = "YOUR %s IS WAITING!",
		BannerLighten = 0.45, -- the notice is the card's shirt color this far toward white (dark costumes stay readable)
		IconSize = 56, -- px, the badge (a normal one is 46)
	},
	TrailRow = "TRAIL",
	HornRow = "HORN",
	NoneLabel = "NONE",
	EmptyLine = "Win these in crates",
}

-- Player level: XP per match, level thresholds grow linearly. The level shows as a badge by the name.
Config.Progression = {
	MatchBaseXp = 50,
	XpPerFare = 10,
	PlacementXp = { 60, 40, 25, 15 }, -- by final placement; beyond the list pays the last entry
	LevelBaseXp = 100, -- XP to go from level 1 to 2
	LevelStepXp = 60, -- each level needs this much more than the last
	MaxLevel = 99,
}

-- Levels that unlock something (checklist 2026-10-28): reaching a level hands over its prize once per account, the way
-- a drop does (an owned car or horn pays DuplicateGems instead). Accounts already past a level get it on their next
-- join. Dense early (a reward in each of the first few matches), then a long road. QUESTS shows the next few.
Config.Levels = {
	Rewards = {
		{ Level = 2, Id = "Lv2", Kind = "Gems", Rarity = "Common", Amount = 50 },
		{ Level = 3, Id = "Lv3", Kind = "Horn", Rarity = "Common", Ref = "Squeaky" },
		{ Level = 5, Id = "Lv5", Kind = "Paint", Rarity = "Rare", Ref = "Bronze" },
		{ Level = 7, Id = "Lv7", Kind = "Gems", Rarity = "Rare", Amount = 100 },
		{ Level = 10, Id = "Lv10", Kind = "Trail", Rarity = "Epic", Ref = "Checkered" },
		{ Level = 12, Id = "Lv12", Kind = "Horn", Rarity = "Rare", Ref = "Kazoo" },
		{ Level = 15, Id = "Lv15", Kind = "Vehicle", Rarity = "Epic", Ref = "Horse" },
		{ Level = 20, Id = "Lv20", Kind = "Paint", Rarity = "Epic", Ref = "Silver" },
		{ Level = 25, Id = "Lv25", Kind = "Gems", Rarity = "Epic", Amount = 300 },
		{ Level = 30, Id = "Lv30", Kind = "Trail", Rarity = "Legendary", Ref = "Afterburner" },
		{ Level = 40, Id = "Lv40", Kind = "Paint", Rarity = "Legendary", Ref = "Platinum" },
		{ Level = 50, Id = "Lv50", Kind = "Trail", Rarity = "Legendary", Ref = "HallOfFame" },
		{ Level = 75, Id = "Lv75", Kind = "Paint", Rarity = "Mythic", Ref = "Diamond" },
		{ Level = 99, Id = "Lv99", Kind = "Trail", Rarity = "Mythic", Ref = "MaxedOut" },
	} :: { LevelReward }, -- in level order
	CatchUpDelay = 4, -- seconds after a join before old levels pay out (after the streak toast)
	Notice = "LEVEL %d  %s UNLOCKED!",
	DuplicateNotice = "LEVEL %d  +%d GEMS (%s WAS ALREADY YOURS)",
	CatchUpNotice = "%d LEVEL REWARDS UNLOCKED!",
	NextCount = 3, -- upcoming rewards shown in QUESTS
	NextLine = "LV %d",
	ChipWidth = 140,
	LockedMark = "LV%d", -- on the Garage's next level paint
}

-- Quests: three daily (reset at 00:00 UTC) and one weekly (reset Monday 00:00 UTC), paying Gems on completion.
Config.Quests = {
	DailyCount = 3,
	DailyPool = {
		{ Id = "deliver", Text = "Deliver %d passengers", Goal = 8, Reward = 15 },
		{ Id = "tips", Text = "Earn $%d in tips", Goal = 20, Reward = 15 },
		{ Id = "knockouts", Text = "Make %d passengers bail", Goal = 3, Reward = 20 },
		{ Id = "drift", Text = "Drift for %d seconds", Goal = 60, Reward = 10 },
		{ Id = "tomato", Text = "Hit %d rivals with a Tomato", Goal = 4, Reward = 15 },
		{ Id = "top2", Text = "Finish top 2 in %d matches", Goal = 2, Reward = 20 },
		{ Id = "red", Text = "Deliver %d long fares", Goal = 3, Reward = 15 },
	} :: { QuestDef },
	WeeklyPool = {
		{ Id = "deliver", Text = "Deliver %d passengers", Goal = 40, Reward = 60 },
		{ Id = "wins", Text = "Win %d matches", Goal = 3, Reward = 80 },
		{ Id = "knockouts", Text = "Make %d passengers bail", Goal = 15, Reward = 70 },
	} :: { QuestDef },
}

-- Login streak: consecutive UTC days. Pays PerDay * min(days, MaxDays) Gems on the first join of each day.
-- The 7-day reward calendar (checklist 2026-10-28: framed as loss). The first join of each UTC day pays that day's prize;
-- a missed day starts the run over at DAY 1. Past DAY 7 the run keeps counting and the calendar goes round again (an
-- owned trail pays its DuplicateGems). The card shows after PLAY, when you're not racing.
Config.Streak = {
	Calendar = {
		{ Id = "Day1", Kind = "Gems", Rarity = "Common", Amount = 10 },
		{ Id = "Day2", Kind = "Gems", Rarity = "Common", Amount = 15 },
		{ Id = "Day3", Kind = "Gems", Rarity = "Common", Amount = 20 },
		{ Id = "Day4", Kind = "Boost", Rarity = "Rare", Ref = "LemonNitro" },
		{ Id = "Day5", Kind = "Gems", Rarity = "Rare", Amount = 30 },
		{ Id = "Day6", Kind = "Gems", Rarity = "Rare", Amount = 40 },
		{ Id = "Day7", Kind = "Trail", Rarity = "Epic", Ref = "OnFire" },
	} :: { Prize },
	ClaimDelay = 3, -- seconds after a join (lets the client boot)
	RolloverCheckSeconds = 30, -- how often the server looks for 00:00 UTC passing (players still in claim the new day)
	Title = "DAILY STREAK",
	StreakLine = "DAY %d",
	DayLabel = "DAY %d",
	TodayLabel = "TODAY",
	TomorrowLine = "Come back tomorrow for DAY %d: %s",
	LoseLine = "Miss a day and it's back to DAY 1.",
	DuplicateLabel = "+%d GEMS",
	Button = "NICE!",
	TileWidth = 84,
	TileHeight = 96,
	AutoCloseSeconds = 15,
}

-- Studio-only soak test (src/server/Studio/SoakMonitor): with the workspace attribute set before Play, bots fill every
-- seat with nobody driving, and the Output (and the Studio log file) gets "[Soak]" lines for phases, rounds, matches,
-- odd cars and server health, for long unattended runs.
Config.Soak = {
	Attribute = "Soak",
	PollSeconds = 0.25, -- how often the round phase is read
	SampleSeconds = 1, -- how often cars are checked while racing
	StuckSeconds = 15, -- a car that moved less than StuckStuds in this long while racing
	StuckStuds = 6,
	FlipUpY = 0.2, -- chassis up vector's Y below this...
	FlipSeconds = 5, -- ...for this long
	FallBelow = -40, -- studs: under the map
	HitchSeconds = 0.05, -- a server frame longer than this counts as a hitch
	BigHitchSeconds = 0.25, -- and one longer than this is printed with the phase it happened in
	PhaseSlack = 10, -- seconds past a phase's planned end before it's reported as overrunning
}

-- The daily rotating shop (checklist 2026-10-28): each UTC day Count cosmetics are for sale for Gems in the SHOP's
-- DAILY tab, at least one of each kind. They rotate in from the drop pool's trails, horns and drop-only paints whose
-- rarity has a price here, so Legendary and Mythic stay crate-only, and level and streak rewards stay earned. Every
-- server and client works the day's list out from the UTC day (Shared/DailyShop). Bought means owned for good.
Config.DailyShop = {
	Count = 4,
	KindOrder = { "Paint", "Trail", "Horn" },
	Prices = { Common = 60, Rare = 150, Epic = 400 } :: { [string]: number }, -- Gems, by rarity
	Kinds = { Paint = "PAINT", Trail = "TRAIL", Horn = "HORN" } :: { [string]: string },
	ResetLine = "New items in %s",
	HornHint = "Tap the swatch to hear it.",
	BoughtLine = "%s IS YOURS! EQUIP IT IN THE GARAGE",
	OwnedLabel = "OWNED",
	PriceLabel = "%d GEMS",
	SwatchSize = 40,
}

-- Sessions: Roblox ranks experiences by play time, return days and playing with friends, so the next match, a friend
-- in the server and an invite that brings someone new all pay Gems (earned by play, never sold). The streak survives a
-- trip to Arcade and back.
Config.Session = {
	StreakGems = 2, -- each match in a row after the first adds this many Gems to the match award...
	StreakMaxGems = 10, -- ...up to this (the 6th match in a row and on)
	FriendGems = 3, -- a match finished with a Roblox friend in the server
	StreakLine = "STREAK x%d +%d",
	FriendLine = "FRIEND +%d",
	InviteButton = "INVITE",
	InvitePrompt = "Race me in CrazyFare!",
	-- Roblox's referral system: someone new who joins through your invite pays you both, once.
	Referral = {
		InviteeGems = 50,
		InviterGems = 100, -- paid on the spot, or on the inviter's next join when they're elsewhere
		MaxPerInviter = 10, -- invites that pay, per account, ever
		Store = "CF_Referrals", -- DataStore of invites waiting for an inviter who wasn't in the server
		InviteeNotice = "A FRIEND INVITED YOU  +%d GEMS",
		InviterNotice = "YOUR FRIEND JOINED  +%d GEMS",
	},
}

-- Chaos (Phase X, owner spec 2026-10-27): mechanics that make rounds louder, built and playtested one at a time.
Config.Chaos = {
	-- Ramming: two racers' cars (players or bots) meeting with a closing speed above MinSpeed. The faster car is the
	-- attacker; the other's passenger takes DamageMin..DamageMax by closing speed (MinSpeed..FullSpeed).
	Ram = {
		MinSpeed = 35, -- studs/s of closing speed
		FullSpeed = 90, -- closing speed that does DamageMax
		DamageMin = 15,
		DamageMax = 40,
		Padding = 1.5, -- studs around both footprints (contact is read from replicated positions)
		MaxHeightGap = 4, -- studs: a car flying over another isn't a ram
		Lookback = 0.25, -- seconds of speed history: the speed going into the bump, not after it
		PairCooldown = 1.5, -- seconds before the same two cars can ram again
		CrashImmuneSeconds = 0.6, -- the bump's own speed loss isn't also a crash for either car
		Shove = 28, -- studs/s added to the hit car along the attacker's line (half at MinSpeed, full at FullSpeed)
	},
	-- Bounty: this round's cash leader wears a crown (over their cab for everyone else, on everyone's minimap); making
	-- their passenger bail pays the Hunter Bonus times Mult. The crown changes hands only when someone passes the leader.
	Bounty = {
		Mult = 2,
		MinCash = 1, -- dollars this round before anyone wears the crown
		Banner = "NEW LEADER: %s",
		You = "YOU",
		BannerSeconds = 1.4,
		BannerCooldown = 3, -- seconds between banners when the lead swaps back and forth (the crown still moves)
		Crown = "\u{1F451}",
		Color = Color3.fromRGB(255, 205, 50),
		CrownSize = 46, -- px, the same at any distance
		CrownHeight = 8, -- studs above the cab
		MinimapCrownSize = 18, -- px
		HunterLine = "BOUNTY x%d", -- under the payout when you bail the leader's passenger
	},
	-- Frenzy: the last Seconds of every race round (not Arcade, whose clock moves and has its own best-run board):
	-- payouts x PayMult, item boxes back in BoxRespawnSeconds, one Golden Fare, faster music, a red tint, FRENZY!.
	Frenzy = {
		Seconds = 30,
		PayMult = 2, -- the whole delivery payout (fare, tip and stunt cash), bots too
		BoxRespawnSeconds = 1,
		MusicSpeed = 1.12, -- pitch and tempo together (Roblox plays them as one)
		Tint = Color3.fromRGB(255, 190, 178), -- Lighting ColorCorrection tint while it lasts
		TintSeconds = 1.2,
		Color = Color3.fromRGB(255, 80, 60),
		Banner = "FRENZY!",
		BannerSub = "PAYOUTS x2  ·  GOLDEN FARE!", -- the Golden Fare that spawns with it would be announced in the same frame
		BannerSeconds = 1.6,
		Phase = "FRENZY  ·  PAYOUTS x2", -- under the timer while it lasts
		PayLine = "FRENZY x2", -- under the payout
		Sting = "Combo", -- Config.Sounds.Stings key played when it starts
	},
	-- World events: one per race round, starting StartMin..StartMax seconds after GO and lasting Seconds, picked by
	-- Weight among the ones this map has (Maps nil = any map). A banner and a sting when it starts; its name and time
	-- left stay under the timer.
	Events = {
		StartMin = 60,
		StartMax = 120,
		Seconds = 30,
		Sting = "Golden", -- Config.Sounds.Stings key
		BannerSeconds = 1.8,
		Color = Color3.fromRGB(120, 220, 255),
		List = {
			{ Id = "RushHour", Name = "RUSH HOUR!", Sub = "TRAFFIC JUST DOUBLED", Weight = 1 },
			{ Id = "Drawbridge", Name = "DRAWBRIDGE!", Sub = "IT'S GOING UP. JUMP IT.", Weight = 1, Maps = { City = true } },
			{ Id = "Parade", Name = "PARADE!", Sub = "MAIN STREET IS CLOSED", Weight = 1, Maps = { City = true } },
			{ Id = "HydrantBurst", Name = "HYDRANTS!", Sub = "FREE LIFTS", Weight = 1, Maps = { City = true } },
			{ Id = "MoneyTruck", Name = "MONEY TRUCK!", Sub = "IT SPILLED. GO GO GO", Weight = 1 },
		} :: { { Id: string, Name: string, Sub: string, Weight: number, Maps: { [string]: boolean }? } },
		RushHour = { ExtraTraffic = 24 },
		Drawbridge = { MaxAngle = 20, RiseSeconds = 10, LowerSeconds = 4 }, -- degrees; up over RiseSeconds, down over the last LowerSeconds
		Parade = {
			Axis = "Z", -- the road runs along X at Z = Coord
			Coord = 60, -- the road just south of the plaza
			From = -320, -- the first float starts here and rolls toward +X
			Speed = 9, -- studs/s
			Floats = 6,
			Spacing = 18, -- studs between float centers
			Size = Vector3.new(14, 3, 20), -- float base: length along the road, height, width across it
			Colors = { Color3.fromRGB(240, 90, 160), Color3.fromRGB(90, 200, 250), Color3.fromRGB(250, 210, 60), Color3.fromRGB(130, 230, 120), Color3.fromRGB(190, 120, 250), Color3.fromRGB(250, 140, 60) },
		},
		HydrantBurst = {
			LaunchSpeed = 72, -- studs/s straight up
			Radius = 5, -- studs around a jet that throw a car
			Cooldown = 1.5, -- seconds before the same car can be thrown again
			JetHeight = 18,
			JetWidth = 3,
			JetColor = Color3.fromRGB(120, 200, 255),
		},
		MoneyTruck = {
			Pickups = 10,
			MinDollars = 2,
			MaxDollars = 5,
			-- It parks on the sidewalk, never in a lane (owner 2026-10-27: it sat in the middle of a junction).
			BlockFractions = { 0.3, 0.5, 0.7 }, -- where along a block it may park
			Clearance = 24, -- studs from stops, stalls, hydrants, item boxes, ramps, boost pads and start pads
			Margin = 2, -- studs of bare pavement it needs ahead and behind
			ScatterAlong = 16, -- coins land up to this far along the road either side of it
			LaneMargin = 2, -- and across both lanes, this far inside the curbs
			PickupRadius = 4.5,
			Size = Vector3.new(7, 6, 13), -- the truck's body
		},
	},
	-- Passenger requests: when a person (not a bot: bots do no stunts) picks someone up, a Chance they want something on
	-- the way, counted from the server-checked stunts. Done before the drop-off, it adds BonusFrac of the base fare to
	-- the tip (lost with the tip on a late arrival or a bail). Single: one stunt has to reach Goal; otherwise they add up.
	Requests = {
		Chance = 0.35,
		BonusFrac = 0.5,
		List = {
			{ Id = "TakeTheJump", Stunt = "Airtime", Goal = 1.5, Single = true, Unit = "S", Label = "BIG AIR", Shout = "AND CATCH SOME AIR!" },
			{ Id = "NearMisses", Stunt = "NearMiss", Goal = 3, Single = false, Unit = "", Label = "NEAR MISSES", Shout = "AND SCARE ME A LITTLE!" },
			{ Id = "DriftSeconds", Stunt = "Drift", Goal = 4, Single = false, Unit = "S", Label = "DRIFT", Shout = "AND DRIFT! I LOVE A DRIFT!" },
		} :: { { Id: string, Stunt: string, Goal: number, Single: boolean, Unit: string, Label: string, Shout: string } },
		PayLine = "REQUEST DONE", -- under the payout
		Sting = "NewBest", -- Config.Sounds.Stings key when one is done
		Color = Color3.fromRGB(255, 170, 60), -- the fare card's request row while it's open (green when done)
	},
	-- Carpool fares: now and then (Chance per new passenger; never a Golden Fare) 2..MaxRiders people wait together.
	-- They board together and each has a stop. Every stop pays like a delivery (its own base, timer, tip and stunt cash)
	-- times PayMult, then the next stop starts; each next stop is a NextTier trip from the last. One HP for the whole
	-- group; a bail empties the cab.
	Carpool = {
		Chance = 0.12,
		MaxRiders = 3,
		PayMult = 1.2,
		NextTier = "Green",
		Label = "CARPOOL x%d", -- over the waiting group
		NextShout = "NEXT STOP: %s!", -- over your cab after each drop
		DropLine = "%d TO GO", -- under a stop's payout
		Color = Color3.fromRGB(190, 120, 250),
		Spacing = 2.2, -- studs between the people standing at the curb
		Shirts = { Color3.fromRGB(240, 240, 240), Color3.fromRGB(90, 160, 220), Color3.fromRGB(240, 140, 60) }, -- the others'
	},
	-- Ticking fares: a Chance of a new passenger (never Golden or a carpool) who is late and holds a giant alarm clock.
	-- The fare starts at StartMult times the base and drops one step every TickSeconds to FloorMult at the deadline,
	-- so every second costs money; the tip and stunt cash go by the plain base as usual. A rival who makes them bail
	-- gets the Hunter Bonus on what the fare was worth at that moment. No requests: they're in a hurry.
	Ticking = {
		Chance = 0.1,
		StartMult = 3,
		FloorMult = 1,
		TickSeconds = 1,
		Label = "TICK TOCK", -- over the waiting passenger and on the fare card
		PayLine = "TICK TOCK x%.1f", -- under the payout: what the clock left of the multiplier
		Lines = { "I'M LATE! EVERY SECOND COSTS YOU!", "TICK TOCK! FASTER = MORE CASH!", "THE CLOCK IS EATING YOUR TIP!" } :: { string },
		Color = Color3.fromRGB(255, 120, 40),
		FaceColor = Color3.fromRGB(250, 250, 245),
		HandColor = Color3.fromRGB(25, 25, 30),
		ClockSize = 1.8, -- studs across: the clock the waiting passenger holds up
		RiderClockSize = 1.5, -- the one beside the rider's head in the cab
		TickPitch = 1.4, -- the countdown by the cab ticks every second while they ride
		TickPunch = 1.15, -- and bumps this much on each tick (the last seconds keep their big punch)
	},
	-- The hop (the owner's "Crazy Hop"; on screen just HOP): E, R1 or the HOP button pops your cab straight up, about
	-- 8 studs with the arcade air gravity, once every Cooldown seconds. Over traffic, over a Banana or an Oil Slick
	-- (traps only catch you within 5 studs up), onto a roof. A hop's own flight is never BIG AIR: airtime that starts
	-- with a hop pays only past it (off a ramp or a drop it still pays). Bots hop over traps on their line.
	Hop = {
		Speed = 38, -- studs/s straight up
		Cooldown = 4,
		Buffer = 0.15, -- seconds: a press this soon before touchdown hops on landing
		FreeAirSlack = 0.1, -- seconds added to a hop's own flight time before airtime pays
		Sound = "Land", -- Config.Sounds.Ids key, played as you leave the ground
		SoundPitch = 1.5,
		BotTrapMin = 6, -- a bot hops over a trap between this many...
		BotTrapLook = 18, -- ...and this many studs ahead...
		BotTrapReach = 3, -- ...within its trigger radius plus this of the bot's line
	},
	-- Weather: every race round rolls one by Weight (0 = off) among those its map allows (Arcade and the gaps between matches stay
	-- Clear). The server sets the sky for everyone (WeatherService); the grip and speed rules work on players
	-- (VehicleController), traffic and bots alike. The banner replaces READ THE BOARD while the round gets ready.
	Weather = {
		List = {
			{ Id = "Clear", Name = "", Sub = "", Weight = 4, Color = Color3.new(1, 1, 1), CloudCover = -1, Particle = "", ClockTime = -1, Brightness = 1, FogDensity = -1, Haze = -1, Tint = Color3.new(1, 1, 1), Saturation = 0, GripMult = 1, TopSpeedMult = 1, DriftBoostMult = 1, PayMult = 1, PayLine = "", TrafficSpeedMult = 1, BotSpeedMult = 1 },
			{ Id = "Rain", Name = "RAIN!", Sub = "SLICK ROADS. DRIFTS FILL BOOST FAST", Weight = 2, Color = Color3.fromRGB(120, 180, 255), CloudCover = 0.95, Particle = "Rain", ClockTime = -1, Brightness = 0.6, FogDensity = 0.42, Haze = 1.5, Tint = Color3.fromRGB(205, 215, 230), Saturation = -0.3, GripMult = 0.75, TopSpeedMult = 1, DriftBoostMult = 1.6, PayMult = 1, PayLine = "", TrafficSpeedMult = 0.9, BotSpeedMult = 0.92 },
			-- Fog is OFF (owner 2026-10-27: "way too foggy", then not sure he likes it at all): Weight 0 never rolls; Studio's
			-- Weather button still shows it. Weight 1 brings it back (already lightened from Density 0.7 / Haze 2.5).
			{ Id = "Fog", Name = "FOG!", Sub = "HARD TO SEE. FOLLOW THE ARROW", Weight = 0, Color = Color3.fromRGB(200, 205, 215), CloudCover = 0.8, Particle = "", ClockTime = -1, Brightness = 0.95, FogDensity = 0.48, Haze = 1, Tint = Color3.fromRGB(235, 235, 240), Saturation = -0.2, GripMult = 1, TopSpeedMult = 1, DriftBoostMult = 1, PayMult = 1, PayLine = "", TrafficSpeedMult = 0.85, BotSpeedMult = 0.9 },
			{ Id = "Night", Name = "NIGHT SHIFT!", Sub = "NIGHT RATES: FARES x1.25", Weight = 1, Color = Color3.fromRGB(170, 140, 255), CloudCover = -1, Particle = "", ClockTime = 0, Brightness = 1, FogDensity = -1, Haze = -1, Tint = Color3.new(1, 1, 1), Saturation = 0, GripMult = 1, TopSpeedMult = 1, DriftBoostMult = 1, PayMult = 1.25, PayLine = "NIGHT RATES x1.25", TrafficSpeedMult = 1, BotSpeedMult = 1 },
			{ Id = "Snow", Name = "SNOW!", Sub = "ICY ROADS. EASY ON THE TURNS", Weight = 1, Maps = { City = true }, Color = Color3.fromRGB(220, 240, 255), CloudCover = 0.85, Particle = "Snow", ClockTime = -1, Brightness = 1.1, FogDensity = 0.4, Haze = 1, Tint = Color3.fromRGB(225, 235, 255), Saturation = -0.25, GripMult = 0.6, TopSpeedMult = 0.92, DriftBoostMult = 1.2, PayMult = 1, PayLine = "", TrafficSpeedMult = 0.8, BotSpeedMult = 0.85 },
		} :: { WeatherDef },
		Particles = {
			Rain = { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = Color3.fromRGB(205, 220, 240), Transparency = 0.15, Size = 0.8, Squash = -3, Rate = 500, Lifetime = 0.7, SpeedMin = 90, SpeedMax = 110, Drift = Vector3.zero, Spin = 0, Streaks = true, Area = 60, Height = 28, Ahead = 28 },
			Snow = { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = Color3.new(1, 1, 1), Transparency = 0.05, Size = 0.6, Squash = 0, Rate = 160, Lifetime = 5, SpeedMin = 6, SpeedMax = 10, Drift = Vector3.new(2, -1, 1), Spin = 60, Streaks = false, Area = 90, Height = 25, Ahead = 25 },
		} :: { [string]: WeatherParticles },
	},
	-- Fruit stands: market stalls straddling the curb (the map's Features.FruitStands). Drive through one at MinSpeed or
	-- more and it bursts into flying fruit; with an empty item slot you get a free item, rolled by rank like an item
	-- box. It's back RespawnSeconds later and at every round start. Nothing solid: no crash, no passenger damage. Bots
	-- with an empty slot swerve to the curb for one ahead on their road.
	FruitStands = {
		Radius = 5.5, -- studs (flat) from the stall's center on the curb line: a car hugging the curb reaches it
		MinSpeed = 25, -- studs/s
		RespawnSeconds = 20,
		BotLook = 60, -- a bot with an empty slot looks this far ahead on its road for one
		BotReach = 13, -- studs off the bot's line a stall can be and still count as on its road
		Lines = { "FREE FRUIT!", "SMOOTHIE TIME!", "I'M NOT PAYING FOR THAT!", "MANGO ON MY SHIRT!" } :: { string },
		FruitColors = {
			Color3.fromRGB(255, 150, 30),
			Color3.fromRGB(220, 40, 40),
			Color3.fromRGB(250, 220, 60),
			Color3.fromRGB(90, 190, 70),
			Color3.fromRGB(140, 70, 180),
		} :: { Color3 },
		CounterColor = Color3.fromRGB(150, 100, 60),
		CrateColor = Color3.fromRGB(190, 140, 80),
		AwningColors = { Color3.fromRGB(230, 50, 50), Color3.fromRGB(250, 250, 245) } :: { Color3 },
		MapColor = Color3.fromRGB(255, 150, 30), -- its dot on the minimap (faded while it's smashed)
		-- the smash, client only: fruit flying along the smasher's path, bouncing down the road
		Pieces = 16,
		PieceSizeMin = 0.6,
		PieceSizeMax = 1.2,
		FlySpeed = 40, -- studs/s along the smasher's path (plus a sideways spread of half that)
		FlyUp = 45,
		Spin = 10, -- radians/s, any axis
		DebrisSeconds = 2.5,
		Sound = "Splat", -- Config.Sounds.Ids key, played at the stall
		SoundPitch = 0.85,
		SoundRange = 150, -- studs: heard this far away
		-- Studio "To stand": lined up this far before the nearest stall, this far into the road from the curb
		DebugRunUp = 40,
		DebugLane = 3,
	},
	Labels = { Ram = "RAMMED!", Cash = "CASH", Request = "REQUEST COMPLETE!", Smash = "FRUIT SMASH!" } :: { [string]: string }, -- popups over your cab
}

-- Live events: weekly windows (UTC) when something good happens in every server, so players have a time to come back
-- to. Edit on update day; servers and clients read the same schedule (src/shared/Events.luau).
Config.Events = {
	Kinds = {
		GoldenHour = { Name = "GOLDEN HOUR", Color = Color3.fromRGB(255, 200, 40), GoldenChanceMult = 4, GemMult = 1 },
		DoubleGems = { Name = "DOUBLE GEMS", Color = Color3.fromRGB(80, 230, 255), GoldenChanceMult = 1, GemMult = 2 },
	} :: { [string]: EventKindDef },
	Weekly = {
		{ Kind = "GoldenHour", Day = 7, HourUtc = 18, Hours = 1 }, -- Saturday 10-11 AM PST
		{ Kind = "DoubleGems", Day = 1, HourUtc = 18, Hours = 3 }, -- Sunday 10 AM-1 PM PST
	} :: { EventWindow },
	SoonHours = 48, -- between matches, the next event shows this far ahead
	DebugAttribute = "DebugEvent", -- Studio: the Debug panel's "Next event" pretends this kind is live for the next hour
	LiveLine = "%s  %s LEFT", -- name, time left
	SoonLine = "%s  %s", -- name, day and time (the player's own clock)
}

-- Leaderboards (OrderedDataStore; in-memory when DataStores are unavailable).
Config.Leaderboards = {
	RefreshSeconds = 60,
	Top = 10,
	WeeklyTrailTop = 10, -- players in this week's top N get the exclusive trail
	FriendsScan = 100, -- how many weekly entries to scan for friends
}

-- Monetization. Product and pass ids come from the Roblox Creator Dashboard; 0 = not configured (shop hides it).
-- Nothing here touches passenger HP, item damage, speed or quota.
Config.Monetization = {
	-- Pay-to-win (owner decision 2026-10-27, "100% pay to win"): passes, Robux-only cars and in-match boosts sell real
	-- advantage. Ids are pasted from Creator Hub (docs/STORE-SETUP.html); an id of 0 shows COMING SOON (TEST in Studio,
	-- which grants it through the Debug remote so every effect can be tried before the ids exist).
	Products = {
		GemsSmall = { Id = 3723346712, Gems = 120, Label = "120 Gems", Robux = 49 },
		GemsMedium = { Id = 3723346867, Gems = 320, Label = "320 Gems", Robux = 99 },
		GemsLarge = { Id = 3723346948, Gems = 900, Label = "900 Gems", Robux = 249 },
		-- one-time, first 2 sessions: Gems, the Go-Kart, and every upgrade raised to at least UpgradeLevel
		StarterPack = { Id = 3723347071, Gems = 300, Label = "Starter Pack", Robux = 79, Vehicle = "GoKart", UpgradeLevel = 3 },
	} :: { [string]: ProductDef },
	ProductOrder = { "GemsSmall", "GemsMedium", "GemsLarge" },
	GamePasses = {
		VIP = { Id = 2058845586, Label = "VIP", Effect = "2x Gems, +25% cash on every fare, gold VIP tag", Robux = 399 },
		TurboTank = { Id = 2057393584, Label = "Turbo Tank", Effect = "Double boost tank, refills 50% faster", Robux = 249 },
		ArmoredSeats = { Id = 2056997574, Label = "Armored Seats", Effect = "Your passengers take half damage", Robux = 299 },
		DoubleItem = { Id = 2058221612, Label = "Double Item", Effect = "Hold 2 items at once", Robux = 299 },
		HeadStart = { Id = 2057321599, Label = "Head Start", Effect = "Start every round with $10 toward the quota", Robux = 199 },
		FareRadar = { Id = 2057201618, Label = "Fare Radar", Effect = "Golden and long fares glow from anywhere", Robux = 149 },
		PitStopPlus = { Id = 2060213610, Label = "Pit Stop Plus", Effect = "6 cards at every Pit Stop", Robux = 149 },
		DoubleXp = { Id = 2060201531, Label = "2x XP", Effect = "Double XP from every match", Robux = 149 },
	} :: { [string]: GamePassDef },
	PassOrder = { "VIP", "TurboTank", "ArmoredSeats", "DoubleItem", "HeadStart", "FareRadar", "PitStopPlus", "DoubleXp" },
	VipGemMult = 2,
	VipCashMult = 1.25, -- every delivery's payout
	VipCashLine = "VIP +25%",
	VipColor = Color3.fromRGB(255, 205, 50), -- the VIP tag over your cab
	PitStopPlusCards = 6,
	TurboTankMult = 2, -- boost tank size
	TurboFillMult = 1.5, -- boost refill from drifts and near misses
	ArmoredSeatsDamageMult = 0.5,
	DoubleItemSlots = 2, -- items held with Double Item (1 without); bought items can go past it
	HeadStartDollars = 10, -- added at the start of every round (and when you take a seat mid-match)
	HeadStartLine = "HEAD START",
	DoubleXpMult = 2,
	StarterPackSessions = 2, -- offered during the player's first N sessions
	-- Premium vehicles: a Robux product (VehicleRobux is the price shown); the Gem price too unless the car is RobuxOnly.
	VehicleProducts = {
		NightCab = 3723347252,
		IceCreamTruck = 3723347372,
		RocketCab = 3723347470,
		ArmoredLimo = 3723347558,
		Phantom = 3723363979, -- sold only inside PhantomOffer
	} :: { [string]: number },
	VehicleRobux = { NightCab = 149, IceCreamTruck = 149, RocketCab = 499, ArmoredLimo = 399, Phantom = 999 } :: { [string]: number },
	-- The Phantom's Robux offer: unix seconds (UTC). Outside the window it reads MYTHIC DROP ONLY and can't be bought.
	-- StartUtc 0 = no offer; EndUtc 0 = on sale from StartUtc with no end (ON SALE NOW, no countdown).
	-- Owner 2026-10-28 "Make it available for purchase": on sale from the v16 publish, no end date yet.
	PhantomOffer = { StartUtc = 1793220319, EndUtc = 0 },
	-- Permanent upgrades sold for Robux (developer products), applied by StoreService once Roblox confirms the purchase.
	-- (The in-match boosts Item Drop, Tomato Barrage, Nitro Refill, Patch Up and Cash Boost were cut 2026-10-28, owner:
	-- no temporary upgrades. Their products are off sale in Creator Hub.)
	Boosts = {
		MaxUpgrades = { Id = 3723348059, Label = "MAX UPGRADES", Effect = "Every upgrade to the top level, for every car", Robux = 199, FallbackGems = 500, Color = Color3.fromRGB(170, 110, 255) },
	} :: { [string]: BoostDef },
	BoostOrder = { "MaxUpgrades" },
	BoughtLine = "%s!", -- the HUD line when one lands
	FallbackLine = "%s COULDN'T APPLY  +%d GEMS", -- already maxed
	Tabs = { "DAILY", "PASSES", "CARS", "UPGRADES", "GEMS" }, -- the first one opens (DAILY: Config.DailyShop)
	-- Fare Radar pass: a beacon over every waiting Golden and long (Red) fare, seen through buildings from anywhere,
	-- while you drive with nobody aboard
	Radar = {
		CheckSeconds = 0.25,
		Lift = 6, -- studs above the passenger...
		RaiseBySize = 1.1, -- ...then this many of its own heights higher, so it clears their badge at any distance
		Size = 54, -- px
		GoldenText = "$$$",
		LongText = "$$",
	},
}

-- Post-match drops (owner spec 2026-10-28): one free crate per match finished, never sold and never improved by any
-- purchase (Gems and Robux can't buy, reroll or upgrade a drop: that would make it a paid random item). Placement picks
-- the tier, the tier's odds pick the rarity, weights pick the prize. A car or paint you already own pays Gems instead.
-- Pity: an Epic or better is guaranteed by the PityEpic-th drop since the last one. Bots get no drops.
Config.Drops = {
	Rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
	Colors = {
		Common = Color3.fromRGB(190, 195, 205),
		Rare = Color3.fromRGB(70, 150, 255),
		Epic = Color3.fromRGB(175, 90, 255),
		Legendary = Color3.fromRGB(255, 190, 40),
		Mythic = Color3.fromRGB(255, 70, 160),
	} :: { [string]: Color3 },
	-- placement -> crate tier; any place not listed is Bronze
	TierByPlace = { "Gold", "Silver", "Silver" },
	DefaultTier = "Bronze",
	TierNames = { Gold = "GOLD CRATE", Silver = "SILVER CRATE", Bronze = "BRONZE CRATE" } :: { [string]: string },
	TierColors = {
		Gold = Color3.fromRGB(255, 200, 50),
		Silver = Color3.fromRGB(200, 210, 225),
		Bronze = Color3.fromRGB(205, 130, 70),
	} :: { [string]: Color3 },
	-- percent per rarity (each tier adds to 100)
	TierOdds = {
		Bronze = { Common = 70, Rare = 22, Epic = 6.4, Legendary = 1.5, Mythic = 0.1 },
		Silver = { Common = 60, Rare = 27, Epic = 9.5, Legendary = 3.2, Mythic = 0.3 },
		Gold = { Common = 48, Rare = 32, Epic = 14, Legendary = 5.5, Mythic = 0.5 },
	} :: { [string]: { [string]: number } },
	PityEpic = 30, -- an Epic or better by this many drops since the last one
	DuplicateGems = { Common = 10, Rare = 30, Epic = 100, Legendary = 400, Mythic = 1500 } :: { [string]: number },
	-- The Phantom's weight inside the Mythic pool (the pool's other Mythic weights add to 100 - this). A 6-car match
	-- averages a 0.23% Mythic chance per drop, so 4.3 makes the Phantom about 1 in 10,000 drops.
	PhantomWeight = 4.3,
	PhantomRef = "Phantom",
	Pool = {
		-- Common
		{ Id = "Gems15", Kind = "Gems", Rarity = "Common", Weight = 22, Amount = 15 },
		{ Id = "Gems25", Kind = "Gems", Rarity = "Common", Weight = 16, Amount = 25 },
		{ Id = "Gems40", Kind = "Gems", Rarity = "Common", Weight = 10, Amount = 40 },
		{ Id = "PaintCherry", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Cherry" },
		{ Id = "PaintMint", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Mint" },
		{ Id = "PaintSky", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Sky" },
		{ Id = "PaintGrape", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Grape" },
		{ Id = "PaintSnow", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Snow" },
		{ Id = "PaintMidnight", Kind = "Paint", Rarity = "Common", Weight = 4, Ref = "Midnight" },
		{ Id = "BoostTomato", Kind = "Boost", Rarity = "Common", Weight = 6, Ref = "Tomato" },
		{ Id = "BoostBanana", Kind = "Boost", Rarity = "Common", Weight = 5, Ref = "Banana" },
		{ Id = "BoostOil", Kind = "Boost", Rarity = "Common", Weight = 4, Ref = "OilSlick" },
		{ Id = "BoostNitro", Kind = "Boost", Rarity = "Common", Weight = 5, Ref = "LemonNitro" },
		{ Id = "BoostShield", Kind = "Boost", Rarity = "Common", Weight = 4, Ref = "Shield" },
		{ Id = "BoostSeatbelt", Kind = "Boost", Rarity = "Common", Weight = 4, Ref = "Seatbelt" },
		-- Rare
		{ Id = "Gems75", Kind = "Gems", Rarity = "Rare", Weight = 40, Amount = 75 },
		{ Id = "PaintSunset", Kind = "Paint", Rarity = "Rare", Weight = 15, Ref = "Sunset" },
		{ Id = "PaintLime", Kind = "Paint", Rarity = "Rare", Weight = 15, Ref = "Lime" },
		{ Id = "PaintBubblegum", Kind = "Paint", Rarity = "Rare", Weight = 15, Ref = "Bubblegum" },
		{ Id = "PaintTeal", Kind = "Paint", Rarity = "Rare", Weight = 15, Ref = "Teal" },
		-- Epic
		{ Id = "Gems200", Kind = "Gems", Rarity = "Epic", Weight = 40, Amount = 200 },
		{ Id = "CarGoKart", Kind = "Vehicle", Rarity = "Epic", Weight = 12, Ref = "GoKart" },
		{ Id = "CarShoppingCart", Kind = "Vehicle", Rarity = "Epic", Weight = 12, Ref = "ShoppingCart" },
		{ Id = "CarHorse", Kind = "Vehicle", Rarity = "Epic", Weight = 12, Ref = "Horse" },
		{ Id = "CarNightCab", Kind = "Vehicle", Rarity = "Epic", Weight = 12, Ref = "NightCab" },
		{ Id = "CarIceCreamTruck", Kind = "Vehicle", Rarity = "Epic", Weight = 12, Ref = "IceCreamTruck" },
		-- Legendary
		{ Id = "Gems600", Kind = "Gems", Rarity = "Legendary", Weight = 40, Amount = 600 },
		{ Id = "CarRocketCab", Kind = "Vehicle", Rarity = "Legendary", Weight = 30, Ref = "RocketCab" },
		{ Id = "CarArmoredLimo", Kind = "Vehicle", Rarity = "Legendary", Weight = 30, Ref = "ArmoredLimo" },
		-- Mythic (the Phantom joins below with PhantomWeight)
		{ Id = "Gems2500", Kind = "Gems", Rarity = "Mythic", Weight = 95.7, Amount = 2500 },
	} :: { DropEntry },
	-- names on the reveal ("%s" is the prize's own name, or the Gem amount)
	Names = {
		Gems = "%s GEMS",
		Paint = "%s PAINT",
		Vehicle = "%s",
		Boost = "START NEXT MATCH WITH %s",
		Trail = "%s TRAIL",
		Horn = "%s HORN",
		Card = "%s CARD",
	} :: { [string]: string },
	DuplicateLine = "ALREADY YOURS  +%d GEMS",
	PityLine = "EPIC OR BETTER WITHIN %d DROPS",
	MythicBanner = "%s PULLED THE PHANTOM!",
	MythicPrizeBanner = "%s PULLED A MYTHIC!",
	-- the reveal over the podium (seconds)
	Reveal = {
		Delay = 1.2, -- after the podium appears
		DropSeconds = 0.35, -- the crate falls in
		ShakeSeconds = 1.1,
		ShakeDegrees = 9,
		BurstSeconds = 0.45,
		HoldSeconds = 8, -- the prize stays up this long after the reveal (the podium is 12 s)
		BannerSeconds = 4, -- a Mythic pull's banner for everyone
		FlashAlpha = 0.35, -- the screen flash's strongest opacity (0 = solid)
	},
	OddsTitle = "DROP ODDS",
	OddsNote = "Free after every match. Better places get better crates.",
	PhantomOddsLine = "THE PHANTOM: 1 in %s",
}
-- the Phantom joins the Mythic pool at its own weight (D3 builds the car; until then a pull owns it and shows the banner)
table.insert(Config.Drops.Pool, { Id = "CarPhantom", Kind = "Vehicle", Rarity = "Mythic", Weight = Config.Drops.PhantomWeight, Ref = Config.Drops.PhantomRef })
-- D2: the material paints, trails, horns and Weirdo cards join the pool at their own rarity and weight
for _, entry in
	{
		{ Id = "PaintFrost", Kind = "Paint", Rarity = "Rare", Weight = 10, Ref = "Frost" },
		{ Id = "PaintChrome", Kind = "Paint", Rarity = "Epic", Weight = 8, Ref = "Chrome" },
		{ Id = "PaintLaser", Kind = "Paint", Rarity = "Epic", Weight = 8, Ref = "Laser" },
		{ Id = "PaintGold", Kind = "Paint", Rarity = "Legendary", Weight = 20, Ref = "Gold" },
	} :: { DropEntry }
do
	table.insert(Config.Drops.Pool, entry)
end
for _, id in Config.Cosmetics.TrailOrder do
	local def = Config.Cosmetics.Trails[id]
	table.insert(Config.Drops.Pool, { Id = "Trail" .. id, Kind = "Trail", Rarity = def.Rarity, Weight = def.Weight, Ref = id })
end
for _, id in Config.Cosmetics.HornOrder do
	local def = Config.Cosmetics.Horns[id]
	table.insert(Config.Drops.Pool, { Id = "Horn" .. id, Kind = "Horn", Rarity = def.Rarity, Weight = def.Weight, Ref = id })
end
for _, id in Config.Cosmetics.CardOrder do
	local def = Config.Cosmetics.Cards[id]
	table.insert(Config.Drops.Pool, { Id = "Card" .. id, Kind = "Card", Rarity = def.Rarity, Weight = def.Weight, Ref = id })
end

-- Sounds. Asset ids are placeholders until the owner uploads audio; 0 = silent. Everything plays through SoundController.
Config.Sounds = {
	Volume = 0.5,
	MusicVolume = 0.25,
	BoostLoopRegion = { 1.2, 6.6 }, -- seconds of the BoostLoop clip that loop (skips the lighter's click on and off)
	BoostLoopPitch = 0.75, -- deeper than the clip: a rocket, not a lighter
	Ids = {
		-- Roblox-licensed Creator Store clips (Pro Sound Effects + APM), picked 2026-10-26; swap any for the owner's own uploads.
		Honk = 9114402481, -- Ferrari 308 Car Honking Dual Air Horns 7
		HonkVip = 9113071178, -- Air Horn Bursts 5
		Engine = 80317022777602, -- Car-Engine-Loop (Roblox Resources group), 9 s loop; pitch follows speed
		Drift = 9120399191, -- Vehicle Skids Long Heavy Tire Squeal 4 (looped while drifting)
		Boost = 9114329395, -- Energy Cloud Whooshing By Very Fast 1; plays as any boost lights (Shift, Lemon Nitro, Dash)
		BoostLoop = 9120192582, -- Torch Lighter 3 (SFX, Pro Sound Effects, 8.0 s): steady mini rocket flame, looped while boosting
		Land = 9114742182, -- Gym Bag Thudding 5 (SFX, Pro Sound Effects, 1.25 s): touchdown after airtime
		Pickup = 9113205239, -- Audi Car Door Movement Opening Closing 4
		Deliver = 9113728049, -- Cash Register 2
		Coin = 9126073001, -- Synth Sparkle Tone High Pitch Bell Tone Ding (1.16 s); one per paid stunt, pitched up the chain
		Tick = 9114069409, -- Dial Switch Twisting Sharp Ticking 48 (0.42 s); money counters tick as they roll
		Stamp = 9114025921, -- Date Stamp Big Office Impact Good Squeak 9 (0.94 s); the delivery grade stamp landing
		Splat = 9119293925, -- Small Splat 2
		Spinout = 9119197920, -- Slide Whistle 3
		Crash = 9120369181, -- Vehicle Crash 2 (Pro Sound Effects); wall hit with a passenger aboard
		Bail = 9113864076, -- Comic Tube Doink 1
		Countdown = 9114640708, -- Graphic Beeps 6
		Go = 9113072516, -- Air Horn Various Lengths And Pitches 3
		RoundEnd = 1844584907, -- Glamour Fanfare 7 (APM, Milan Pilar)
	} :: { [string]: number },
	-- Music: these play in turn, each once through, starting from a random one. APM tracks from the Creator Store
	-- (licensed for every experience), picked 2026-10-27 by search; swap any for the owner's own uploads.
	Playlist = {
		1841068132, -- Keep on Moving (APM, KPM Main Series), 63 s
		1845330177, -- Skater Punk (APM, Chris Goulstone), 236 s
		9043204604, -- Rock'n'Rolla Surf (APM, Franck Fossey), 111 s
		1837235810, -- Wild Cat Scratch (APM, Mark Alberts), 107 s
	} :: { number },
	-- Callout stings: short hits over the music (which dips under them).
	Stings = {
		Combo = 1846901697, -- Stab OL (APM), 3 s brass stab: the chain reaches a number in ComboStingChains
		Golden = 9116394545, -- Magic Glows Soft Clusters Of Chiming Hits 1 (Pro Sound Effects), 1 s: a Golden Fare boards
		NewBest = 9120686092, -- Whistle Ta Da 2 (Pro Sound Effects), 2 s: the license plate says NEW BEST
		Win = 9120974911, -- Wrestling Crowd 1 (Pro Sound Effects), 5 s: you won the match
		Mythic = 9116394545, -- slot: a Mythic drop pull, for everyone in the server (reuses the Golden chime until one is picked)
		DropReveal = 9120686092, -- slot: an Epic or better reveal (reuses the ta-da)
	} :: { [string]: number },
	StingVolume = 0.6,
	ComboStingChains = { 5, 10 } :: { number },
	MusicDuck = 0.35, -- the music drops to this share of its volume under a sting
	MusicDuckSeconds = 1.6,
	FinalBeeps = 5, -- the countdown beep ticks through the last seconds of the clock (rounds and Arcade)
	FinalBeepPitch = 1.25,
	PassengerLines = { -- spoken as text bubbles already; ids here add voice when available
		Board = 0,
		Angry = 0,
		Thanks = 0,
	} :: { [string]: number },
}

-- Camera shake on hits (client only).
Config.Shake = {
	Splat = 0.8,
	Spinout = 1.2,
	Crash = 0.5,
	Rammed = 1.1, -- your car got rammed
	Ram = 0.45, -- you rammed someone
	Decay = 6, -- 1/s
}

-- Touch controls (phones/tablets): on-screen buttons sized in pixels.
-- Phones: hold GAS to drive (owner 2026-10-27: no auto-forward, a forward and a backwards button). BRAKE slows to a
-- stop, holds there for ReverseDelay (time to pick up or drop off), then reverses, reading REVERSE once stopped; BRAKE
-- then GAS at low speed is a Dash, as on a keyboard. Steering is an analog strip.
Config.Touch = {
	ButtonSize = 64, -- px: BRAKE, DRIFT, HOP, HONK
	BigButton = 84, -- px: GAS (and BOOST's width), where the right thumb rests
	ItemButton = Vector2.new(104, 64), -- px: wide enough for the item's name
	Margin = 18,
	Gap = 10,
	Opacity = 0.45,
	HoldSpeed = 4, -- studs/s: slower than this, a held BRAKE holds the car still (fares claim under 5)...
	ReverseDelay = 0.7, -- ...for this long, then reverses
	SteerPad = Vector2.new(200, 84), -- px: the steering strip, bottom-left
	SteerKnob = 56,
	SteerDeadzone = 0.12, -- share of the strip's half-width around the middle that steers nothing
	ReverseTextSize = 13, -- BRAKE reads REVERSE while the cab is stopped or backing up (holding it there reverses)
	FareCardGap = 12, -- px (before phone scaling): on touch the fare card sits left of the minimap, clear of the buttons
	FareCardWidth = 200, -- px (before phone scaling) on touch, so it clears the timer on narrow phones
	-- The driving buttons show only while you can drive, so menus between rounds (GARAGE, SHOP, INVITE...) are never
	-- under them (owner 2026-10-27, phone pass)
	ShowInPhases = { Countdown = true, Playing = true } :: { [string]: boolean },
}

-- Persistent profile (ProfileStore). Bump StoreName to wipe everyone in a test place.
Config.Data = {
	StoreName = "CrazyFare_v1",
	Template = {
		Gems = 0,
		Level = 1,
		Xp = 0,
		OwnedVehicles = { YellowCab = true } :: { [string]: boolean },
		SelectedVehicle = "YellowCab",
		Paint = "",
		Upgrades = { Speed = 0, Handling = 0, Boost = 0 } :: { [string]: number },
		Quests = {} :: { [string]: any },
		Streak = { Days = 0, LastDay = 0 },
		Stats = { Matches = 0, Wins = 0, Fares = 0, BestTip = 0, Knockouts = 0 } :: { [string]: number },
		Purchases = {} :: { [string]: boolean }, -- receipt ids already granted (idempotent ProcessReceipt)
		Sessions = 0,
		StarterPackBought = false,
		TotalGemsEarned = 0,
		BestLicense = 0, -- best match license so far (index into Config.License.Grades; 0 = none yet)
		ArcadeBest = 0, -- best Arcade run (cents)
		ArcadeBestLicense = 0,
		CoachDone = false, -- the first-match coach prompts have all been shown
		Settings = { Music = 5, Sfx = 5, Shake = true, SpeedFx = true }, -- OPTIONS: volume steps (Config.Options.VolumeSteps) and switches
		DropCount = 0, -- post-match drops opened, ever
		PityCounter = 0, -- drops since the last Epic or better (Config.Drops.PityEpic)
		-- owned paints, trails, horns, cards (1 each) and boost tokens (count)
		Inventory = { Paints = {}, Boosts = {}, Trails = {}, Horns = {}, Cards = {} } :: { [string]: { [string]: number } },
		Equipped = { Trail = "", Horn = "" }, -- "" = none (the default honk; no trail unless you earn the weekly one)
		WeirdoQueue = "", -- a new card's weirdo, spawned once in your next round as a bonus fare ("" = none)
		OnboardingStep = 0, -- the furthest new-player funnel step logged for this account (Config.Metrics.Onboarding)
		BadgesGiven = {} :: { [string]: boolean }, -- Config.Badges keys already sent to Roblox for this account
		LevelRewardsTo = 1, -- Config.Levels rewards up to this level are handed over
		PhantomSerial = 0, -- your Phantom's number among all owners (0 = none yet)
		ReferredBy = 0, -- UserId of the friend whose invite brought this player (0 = none)
		ReferralsPaid = 0, -- invites of theirs that have paid out (Config.Session.Referral.MaxPerInviter)
	},
}

-- Solo Arcade: your own server where the clock is everything. Start with StartSeconds; every pickup adds time by trip
-- length and every arrival by its grade (capped at MaxClock); the run ends at 0. No bots, no quota, no Pit Stop, the
-- City with its set pieces. Graded by its total (Config.License.Arcade); your best run is saved and on the board.
-- Live servers send you to a reserved server of your own; in Studio the server you're in switches.
Config.Arcade = {
	Map = "City",
	StartSeconds = 50,
	MaxClock = 99,
	PickupSeconds = { Green = 6, Yellow = 9, Red = 12 } :: { [string]: number },
	GradeSeconds = { Speedy = 5, OnTime = 2, Slow = 0 } :: { [string]: number },
	EndSeconds = 12, -- the results stay up this long, then the next run starts by itself (or PLAY AGAIN)
	DangerSeconds = 10, -- the clock turns red
	TimeBonus = "+%d SEC",
	Title = "TIME'S UP!",
	PlayAgain = "PLAY AGAIN",
	Button = "ARCADE", -- in the menu between matches
	LeaveButton = "RACE",
	Phase = "ARCADE  ·  BEAT YOUR BEST",
}

-- First-match coach: one short prompt at a time in the strip under the timer, until each is done (or has had its
-- time), once per account. Words per input: keyboard / touch / gamepad.
Config.Coach = {
	Steps = {
		{ Id = "pickup", Keyboard = "STOP NEXT TO A $ TO PICK UP", Touch = "STOP NEXT TO A $ TO PICK UP", Gamepad = "STOP NEXT TO A $ TO PICK UP", MaxSeconds = 0 },
		{ Id = "deliver", Keyboard = "FOLLOW THE ARROW, STOP IN THE RING", Touch = "FOLLOW THE ARROW, STOP IN THE RING", Gamepad = "FOLLOW THE ARROW, STOP IN THE RING", MaxSeconds = 0 },
		{ Id = "drift", Keyboard = "HOLD SPACE WHILE TURNING TO DRIFT", Touch = "HOLD DRIFT WHILE TURNING", Gamepad = "HOLD A WHILE TURNING TO DRIFT", MaxSeconds = 14 },
		{ Id = "boost", Keyboard = "HOLD SHIFT TO BOOST", Touch = "HOLD BOOST", Gamepad = "HOLD B TO BOOST", MaxSeconds = 12 },
		{ Id = "hop", Keyboard = "PRESS E TO HOP", Touch = "TAP HOP TO JUMP", Gamepad = "PRESS R1 TO HOP", MaxSeconds = 12 },
		{ Id = "item", Keyboard = "PRESS Q TO USE YOUR ITEM", Touch = "TAP YOUR ITEM", Gamepad = "PRESS X TO USE YOUR ITEM", MaxSeconds = 12 },
	} :: { { Id: string, Keyboard: string, Touch: string, Gamepad: string, MaxSeconds: number } }, -- MaxSeconds 0 = until done
	DriftSeconds = 0.5, -- drifting this long counts as done
	BoostSeconds = 0.3,
	BoostTankToShow = 0.5, -- the boost prompt waits for this much in the tank
}

-- Licenses: a grade for every match (from your three-round total) and every Arcade run (from its total), shown as a
-- plate on the podium. Your best of each is saved.
Config.License = {
	Grades = { "D", "C", "B", "A", "S", "LEGEND" },
	Colors = {
		Color3.fromRGB(150, 150, 160),
		Color3.fromRGB(110, 200, 90),
		Color3.fromRGB(70, 150, 240),
		Color3.fromRGB(170, 90, 240),
		Color3.fromRGB(250, 200, 40),
		Color3.fromRGB(255, 80, 180),
	},
	Race = { 0, 90, 160, 230, 300, 380 }, -- dollars over a match for each grade (the three quotas add up to 300)
	Arcade = { 0, 40, 90, 150, 220, 300 }, -- dollars in one Arcade run for each grade
	Title = "CRAZYFARE",
	NewBest = "NEW BEST!",
}

-- One raycast chassis drives every vehicle; these shape how the stats above feel.
Config.Chassis = {
	SuspensionRest = 1.6, -- ray length below the wheel attachment before the wheel radius
	SuspensionStiffness = 2.5, -- multiples of the car's weight per rest-length of compression
	SuspensionDampingRatio = 0.5, -- 1 = critically damped
	WheelRadius = 1.1,
	BrakeAccel = 70,
	ReverseTopSpeed = 25,
	ReverseAccelMult = 0.5,
	RollingDrag = 0.35, -- 1/s on forward speed while coasting
	SideDragInAir = 0.2,
	SpeedSteerFalloff = 0.55, -- steering lost at top speed (0..1)
	DriftSteerBonus = 1.3, -- steering multiplier while drifting
	DriftMinSpeed = 25,
	DriftMinSide = 10, -- lateral speed that counts as a drift
	AirAngularDamping = 1.5,
	AirUprightStrength = 2, -- how hard the car levels itself mid-air
	SpeedHardCapMult = 1.08, -- velocity is clamped at TopSpeed * boost * this
	BoostFillPerDriftSecond = 0.6, -- boost tank seconds per second of drifting
	BoostFillPerNearMiss = 0.5,
	BoostSpeedMult = 1.25,
	BoostAccelMult = 1.5,
	FlipResetSeconds = 2.5, -- upside-down for this long = auto reset
	ResetLift = 4,
	NearMissPadding = 3.5, -- studs around the car that count as a near miss
	NearMissCooldown = 0.6,
	AirtimeMinSeconds = 0.35,
	SpinAngularSpeed = 7, -- radians/s during a Banana spinout
	SpinGripMult = 0.2,
	MaxStepSeconds = 1 / 30, -- physics step clamp; longer frames are treated as this
	-- Dash: hold brake while almost stopped, then hit the gas = a launch. A movement trick, not a paid stunt.
	-- Deliberate only (owner 2026-10-27: it fired "randomly" when stopping at pickups and backing off walls): a short
	-- brake tap at a near-standstill, then gas right away. Holding the brake longer is reversing, never a Dash.
	DashMaxSpeed = 8, -- studs/s: slower than this counts as almost stopped
	DashArmSeconds = 0.2, -- the brake tap lasts at least this long...
	DashArmMax = 0.8, -- ...and at most this long
	DashWindow = 0.3, -- seconds after letting go of the brake to hit the gas
	AirGravityMult = 0.45, -- gravity on your cab while all four wheels are off the ground: jumps hang longer (arcade air)
	PadSpeed = 120, -- a boost pad throws you to this forward speed, then it runs like a Dash (tested: 105 left the jump block's crest at 63 and landed on the roof)
	DashSeconds = 1.2,
	DashSpeedMult = 1.4, -- top speed while dashing (does not stack with Lemon Nitro; the bigger one wins)
	DashAccelMult = 2.5,
	DashKick = 35, -- studs/s of forward speed the launch gives at once
	DashCooldown = 1,
}

-- Speed feel (client only): boost flames, speed streaks, landing dust, drift smoke, the DASH! popup.
Config.SpeedFx = {
	Labels = { Dash = "DASH!", Pad = "BOOST!" } :: { [string]: string },
	Flames = { Rate = 140, Lifetime = 0.18, Speed = 18, Size = 1.3, Spread = 12, LightRange = 12, LightBrightness = 4 },
	Streaks = {
		StartFrac = 0.72, -- of top speed: streaks start fading in
		Count = 26,
		Seconds = 0.32, -- one streak's trip from the inner ring to the screen edge
		InnerRadius = 0.22, -- of the screen's half-diagonal: streaks start this far out (the cab stays clear)
		Length = 140, -- px at full intensity
		Thickness = 3,
		MaxOpacity = 0.6,
		BoostBonus = 0.4, -- extra intensity while boosting or dashing
	},
	-- Cartoon puffs (balls that swell and fade): a ring of dust on landing, tire smoke while drifting
	Dust = { MinPuffs = 7, MaxPuffs = 16, PerAirSecond = 8, Speed = 14, Rise = 2, StartSize = 1.6, EndSize = 5, Seconds = 0.55, Opacity = 0.8, GroundLift = 0.8, Shake = 0.35, ShakeAirSeconds = 1.2 },
	Smoke = { Rate = 14, StartSize = 1, EndSize = 4.5, Seconds = 0.8, Rise = 4, Spread = 1.5, Opacity = 0.6 }, -- Rate: puffs per second per rear tire
}

Config.Camera = {
	Distance = 22,
	Height = 9,
	LookAhead = 8,
	Stiffness = 6, -- higher = snappier follow
	FovBase = 70,
	FovSpeedBonus = 12, -- at top speed
	FovBoostBonus = 6,
}

Config.Net = {
	SnapshotHz = 10,
	-- Max messages per second per player, per remote. Add a line here for every new client->server remote.
	RateLimits = {
		UseItem = 4,
		ComboEvent = 10,
		DriveState = 12,
		ResetVehicle = 2,
		ClientReady = 1,
		PitStopBuy = 6,
		PitStopReady = 4,
		GarageAction = 5,
		CoachDone = 1,
		ArcadeRequest = 2,
		RequestLeaderboards = 1,
		ShopAction = 4,
		HailCab = 2,
		RateRide = 2,
		DepotChoice = 2,
		Play = 1,
		SaveSettings = 2,
		MapVote = 4,
		DailyBuy = 2,
		Debug = 10,
	} :: { [string]: number },
	-- Server-side position sanity: strikes when a car moves farther per frame than its fastest legal speed allows.
	SpeedSanity = {
		Slack = 4, -- studs of forgiveness per frame
		Strikes = 4, -- consecutive bad frames before a correction
	},
}

Config.Hud = {
	WorldTagDistance = 150, -- "$value" + HP bar over loaded rivals
	WorldTagNameDistance = 70, -- a rival's name only this close (owner 2026-10-27: too many words at once)
	-- A rival's lifetime fares (profile Stats) under their name while they carry nobody: the big number everyone grinds
	-- and sees (checklist 2026-10-28). The Roblox player list stays off; it covers the minimap.
	LifetimeStat = "Fares",
	LifetimeAttribute = "LifetimeFares", -- mirrored on the Player by DataService, read into the snapshot
	LifetimeLine = "%s FARES",
	LifetimeColor = Color3.fromRGB(255, 214, 110),
	LifetimeTextSize = 13,
	NpcHideCheckSeconds = 0.25, -- how often waiting passengers' badges are hidden / shown as you pick up and drop off
	MinimapSize = 190, -- px
	NoticeSeconds = 2.2, -- a one-line notice (quest done, streak, level up) stays this long
	-- Messages while driving sit in a small strip under the timer and leave fast (owner 2026-10-27: big center text hid
	-- the road and he hit people and cars). Only the pre-round text (read the board, 3-2-1, GO, the winner) is big.
	PayoutPunchSeconds = 1.1,
	MessageSeconds = 1.1,
	CrashMessageSeconds = 0.7, -- "-20 HP" after a crash
	NpcBillboardDistance = 450,
	BeaconHeight = 70, -- destination beacon part height
	BeaconLabel = { Width = 160, Height = 40, Lift = 4, MaxDistance = 2000 }, -- the destination's name on top of the beam (px, studs above the top, studs)
	Arrow = { Height = 7.5, Length = 4.5, Width = 1.3, Thickness = 0.7, Pitch = 24, Transparency = 0.3, TurnAroundDegrees = 110 }, -- 3D destination arrow over the local cab; Pitch tilts the nose down (degrees) so the chase cam sees its face. It shows the distance, plus STOP in the ring or TURN AROUND past this angle
	-- Slot-machine money counters (TOTAL top-left, FARE on the fare card): every digit is a reel that rolls up
	CounterRollSeconds = 0.9, -- a counter covers any gap in about this long
	CounterMinRate = 250, -- cents per second at the slowest, so a small tip still visibly rolls
	CounterTickMaxPerSecond = 16, -- tick sounds while a counter rolls
	CounterLandHold = 0.55, -- after a delivery the TOTAL waits this long for the flying coins to land
	TotalHeight = 48, -- px
	FareHeight = 30, -- px
	-- Coin burst on delivery: coins pop out of the cab and fly into the TOTAL
	BurstCoinsMin = 6,
	BurstCoinsMax = 16,
	BurstCoinsPerDollar = 1,
	BurstOutSeconds = 0.22,
	BurstFlySeconds = 0.42,
	BurstSpread = 110, -- px
	-- Delivery grade stamp
	StampDelay = 0.25, -- after the payout punch
	StampSeconds = 0.8, -- on screen before it fades
	-- Where to: the passenger's shout, the arrival banner, the countdown by the cab, the drop-off ring on the ground
	ShoutSeconds = 1.5, -- "TAKE ME TO THE STADIUM!" over the cab (your passenger's later lines use the same bubble)
	ArrivalDistance = 70, -- studs from the destination where its name banner slides in
	ArrivalSeconds = 1.1,
	CountdownWarn = 10, -- seconds left: the countdown by the cab turns yellow
	CountdownDanger = 5, -- and red, ticking every second
	DropRing = { Segments = 32, Width = 0.7, Thickness = 0.2, Transparency = 0.1, DiscTransparency = 0.82, PulseSeconds = 0.8 },
	-- Phones: when the screen below Roblox's top bar is smaller than FitSize, every HUD and panel shrinks to fit (never
	-- below FitMinScale), each piece staying in its corner. Touch pads and full-screen effects keep their size.
	FitSize = Vector2.new(900, 580), -- the garage (820 x 580) is the biggest panel
	-- 0.5 left HUD text near 7 points on a 360-point-tall phone (owner 2026-10-27, phone pass); big centered panels
	-- (garage, Pit Stop, progress, shop) shrink themselves further when they'd still overflow (UI.CenterBelowTopbar)
	FitMinScale = 0.65,
	PanelFitMargin = 0.96, -- a self-fitting panel uses at most this share of the space below the top bar
	TopbarHeight = 58, -- px: Roblox's top bar, which the top-left money block sits under (it never scales)
	EventChipY = 196, -- px from the top: the live-event line under the Gems
}

-- Drop-off names, given out when the map is built: a drop-off on a landmark or park block takes that block's name, the
-- rest take the map's list in order. Shown on rooftop signs, the beacon, the fare card, "TAKE ME TO ...!" and on arrival.
Config.Destinations = {
	Landmarks = { hotel = "HOTEL ZEPHYR", dome = "THE STADIUM", antenna = "RADIO TOWER" } :: { [string]: string },
	Parks = { City = "CITY PARK", Beach = "PALM PARK" } :: { [string]: string },
	Names = {
		City = { "THE BURGER JOINT", "THE MALL", "THE HOSPITAL", "THE ARCADE", "THE TRAIN STATION", "CITY HALL", "THE PIZZA PLACE", "THE GYM", "THE BOWLING ALLEY", "THE FIRE STATION", "THE MUSEUM", "POLICE HQ" },
		Beach = { "THE PIER", "THE SURF SHOP", "THE LIGHTHOUSE", "THE BOARDWALK", "THE ICE CREAM HUT", "THE BEACH CLUB", "THE MARINA", "THE SNACK SHACK", "LIFEGUARD TOWER", "THE AQUARIUM", "VOLLEYBALL COURTS", "HOTEL SEABREEZE" },
	} :: { [string]: { string } },
	-- Rooftop signs over every drop-off (client-side billboards; the current destination lights up in its tier color)
	SignHeight = 30, -- studs above the drop-off
	SignWidth = 22, -- studs
	SignHeightStuds = 5,
	SignActiveScale = 1.35,
	SignMaxDistance = 420, -- studs: your destination's sign
	SignIdleDistance = 110, -- every other drop-off's sign only this close
}

-- Imported art (Kenney kits, CC0, from assets/kenney; the meshes live in ReplicatedStorage.MapModels =
-- models/MapModels.rbxmx). Buildings replace the City's boxes; roof icons stand on the building behind named drop-offs
-- so you can look for "the giant burger". Nothing here changes a rule: looks only.
Config.Art = {
	Buildings = {
		FrontYaw = 0, -- degrees that turn a template so its storefront points along +Z (Kenney's front)
		Fill = 0.9, -- a building covers this share of its lot's width and depth
		MinHeight = 22, -- studs: a template that comes out shorter or taller than this for its lot is skipped there
		MaxHeight = 100,
		DowntownRadius = 170, -- studs from the map center: blocks this close take towers up to DowntownMaxHeight
		DowntownMaxHeight = 190,
	},
	-- The Beach's blocks: Kenney suburban houses (MapModels.Houses) placed by the same rules as Buildings, each in a
	-- fenced yard with a stone path from its door to the sidewalk; street trees out front.
	Houses = { FrontYaw = 0, Fill = 0.72, MinHeight = 8, MaxHeight = 40, DowntownRadius = 0, DowntownMaxHeight = 40 },
	Fence = { Model = "fence", Height = 2.6, Gap = 7 }, -- MapModels.Street; studs tall; the front fence's opening for the path
	Path = { Model = "path-stones-long", Width = 3 }, -- MapModels.Street; studs wide
	-- Destination name -> icon (ReplicatedStorage.MapModels.Icons.<Model>). Size: its longest side in studs; Yaw: degrees
	-- added so its best side faces the street; Tilt: degrees it leans toward the street (a pizza stands up).
	RoofIcons = {
		["THE BURGER JOINT"] = { Model = "burger", Size = 24, Yaw = 0, Tilt = 25 },
		["THE PIZZA PLACE"] = { Model = "pizza", Size = 26, Yaw = 0, Tilt = 70 },
		["POLICE HQ"] = { Model = "police", Size = 24, Yaw = 90, Tilt = 0 },
		["THE FIRE STATION"] = { Model = "firetruck", Size = 26, Yaw = 90, Tilt = 0 },
		["THE HOSPITAL"] = { Model = "ambulance", Size = 26, Yaw = 90, Tilt = 0 },
		["THE ICE CREAM HUT"] = { Model = "ice-cream", Size = 20, Yaw = 0, Tilt = 0 },
		["THE SNACK SHACK"] = { Model = "hot-dog", Size = 20, Yaw = 0, Tilt = 0 },
		["THE BEACH CLUB"] = { Model = "cocktail", Size = 20, Yaw = 0, Tilt = 0 },
		["THE AQUARIUM"] = { Model = "fish", Size = 22, Yaw = 90, Tilt = 0 },
	} :: { [string]: { Model: string, Size: number, Yaw: number, Tilt: number } },
	RoofIconProbe = 20, -- studs inward from a drop-off: the point its building is looked for around
	RoofIconSearch = 24, -- the building's footprint must come this close to that point
	RoofIconFloat = 12, -- no building behind it: the icon floats this far above the rooftop sign
	RoofIconInset = 0.35, -- it stands this share of its Size back from the roof's street edge
	RoofIconLift = 3, -- studs above the roof
	-- Street pieces (MapModels.Street; City only): Model, Height in studs, Yaw = degrees that turn the model to face the
	-- way the generator means (a streetlight's arm over the road, a sign or signal's face toward oncoming drivers).
	Street = {
		Streetlight = { Model = "light-curved", Height = 13, Yaw = 180 },
		TrafficLight = { Model = "traffic-light", Height = 11, Yaw = -90 },
		StreetSign = { Model = "road-sign-street", Height = 9, Yaw = 0 },
		StopSign = { Model = "road-sign-stop", Height = 8, Yaw = -90 },
	} :: { [string]: { Model: string, Height: number, Yaw: number } },
	-- a glowing bulb under each streetlight's head (the mesh has none): up and out along the arm as shares of its Height
	LampGlow = { Up = 0.92, Out = 0.25, Size = Vector3.new(1.1, 0.3, 1.3) },
	MidBlockLights = { 0.35, 0.65 }, -- streetlights along inner roads, as fractions of the way between junctions
	LightCurbInset = 1.5, -- studs onto the sidewalk from the curb
	FurnitureClearance = 10, -- studs from stops, stalls, hydrants, walls and the drawbridge
	Trees = { "tree-large", "tree-small" }, -- MapModels.Street models; parks and the strip between sidewalk and buildings
	TreeHeight = { 15, 21 }, -- park trees, studs, random between
	TrunkSize = Vector3.new(1.2, 6, 1.2), -- the invisible collider under each park tree
	-- Street trees: one near each corner of a block, on its north and south sides, far from the mid-block stops; looks only,
	-- nothing collides with them (owner 2026-10-27: a tree every 22 studs, solid, got in the way of pickups).
	StreetTreeOffset = 30, -- studs from the middle of the block's side
	StreetTreeHeight = { 12, 16 },
	TreeInset = 2, -- studs inside the sidewalk's inner edge: behind the walkers, in front of the buildings
	-- Kenney cars (MapModels.Cars), looks only: traffic keeps its collider box and wears a car picked from its kind's
	-- list (an empty list keeps the parts body: Kenney has no bus); each bot wears one by its slot over its hidden parts
	-- cab, with a roof sign in the bot's color so it reads as a rival cab. Traffic and bots use different models.
	TrafficCars = { Sedan = { "sedan", "suv", "truck" }, Van = { "van", "delivery" }, Bus = {} } :: { [string]: { string } },
	BotCars = { "sedan-sports", "hatchback-sports", "suv-luxury" },
	CarYaw = 0, -- degrees: imported Kenney cars already face -Z like ours (checked in Studio: a spoiler showed up front at 180)
	CarWidthSlack = 1.1, -- a car may come out this much wider than its collider
	BotSignSize = Vector3.new(2.2, 0.6, 1),
	-- Road markings and curbs (City). Markings never cross a junction.
	Roads = {
		CenterLine = 0.35, -- each of the two yellow center lines, studs wide
		CenterGap = 0.35,
		EdgeLine = 0.35, -- the white line along each curb
		EdgeInset = 1.2, -- studs in from the curb
		StopLine = 0.9, -- the white bar across each approach lane
		StopGap = 1, -- studs before the crosswalk
		ManholeChance = 0.5, -- per block of road
		ManholeSize = 3,
		CurbWidth = 1,
		CurbLip = 0.12, -- studs above the sidewalk (looks only: the curb never collides)
	},
}

-- Sky: dynamic clouds over every map (WeatherService makes them; a weather's CloudCover overrides the cover).
Config.Sky = {
	CloudCover = 0.5,
	CloudDensity = 0.55,
	CloudColor = Color3.fromRGB(255, 255, 255),
}

-- Delivery grade: how much of the fare timer was left at the drop-off. The tip already pays for speed; the stamp says it out loud.
Config.Grades = {
	SpeedyFrac = 0.6, -- this share of the timer left or more: SPEEDY
	OnTimeFrac = 0.25, -- this or more: ON TIME; less: SLOW
	Labels = { Speedy = "SPEEDY!", OnTime = "ON TIME", Slow = "SLOW" } :: { [string]: string },
	Colors = {
		Speedy = Color3.fromRGB(255, 70, 190),
		OnTime = Color3.fromRGB(250, 210, 60),
		Slow = Color3.fromRGB(150, 160, 190),
	} :: { [string]: Color3 },
}

-- Each map is a data entry. The blockout spec is shared by DevBlockout (builds it) and the minimap (draws it).
Config.Map = {
	Current = "City",
	-- Pickups and drop-offs stand at least this far (studs) from ramps and humps, the hill, the drawbridge, boost pads,
	-- hydrants and fruit stalls (owner 2026-10-27: a passenger stood inside a drawbridge tower; stops beside ramps jam up).
	SpotClearance = 20,
	Rotation = { "City", "Beach" }, -- one match per entry, in order
	City = {
		DisplayName = "City",
		Theme = "city",
		UnlockGems = 0,
		ClockTime = 15.6, -- mid-afternoon: warm light, long shadows (was 14.5 before the art pass)
		Blockout = {
			Half = 320, -- playable area is -Half..Half on X and Z
			RoadCoords = { -300, -180, -60, 60, 180, 300 }, -- road center lines on both axes
			RoadWidth = 24,
			CellCenters = { -240, -120, 0, 120, 240 }, -- block centers between roads
			CellSize = 96,
			Sidewalk = 8,
			WallHeight = 14,
			Seed = 7,
			BuildingMinHeight = 16,
			BuildingMaxHeight = 64,
			PickupPoints = 12,
			DropoffPoints = 12,
			NearStartPickups = 4, -- of the pickups, at least this many inside the first tier-weight band
			ItemBoxes = 6,
			SkylineInner = 380, -- background skyline ring (not reachable) between these radii
			SkylineOuter = 500,
			SkylineMinHeight = 50,
			SkylineMaxHeight = 150,
			WindowFloorHeight = 6, -- one window band per this many studs of building
			PropsPerCell = 2,
			Features = {
				Alleys = { { X = -120, Z = -120 }, { X = 120, Z = 120 } },
				AlleyWidth = 12,
				-- On the road beside the plaza: everyone sees it leaving the grid; at speed you get air off the top.
				Hill = { X = 60, ZFrom = -43, ZTo = 43, Height = 8, Flat = 20 },
				-- Over a block, straight ahead of the start grid (the plaza is the run-up): a 12-stud launch north, a warehouse
				-- roof at 9 (come up short and you land on it), a landing ramp down to the next road.
				-- (Tested 2026-10-27: a 12-stud climb bled 68 studs/s to 39 and only hopped onto the roof; now lower, with a boost pad.)
				JumpBlock = { X = 0, Z = -120, Dir = -1, Width = 24, LaunchStart = -36, Crest = -14, RoofStart = -8, RoofEnd = 20, LandEnd = 40, CrestHeight = 8, RoofHeight = 6 },
				-- After the jump block's landing: a clear lane on through the radio tower's block (the tower moves aside),
				-- so a full-speed landing has room to brake or turn instead of meeting the tower's base.
				Runout = { X = 0, Z = -240, Width = 24, LandmarkShift = 28 },
				-- A shortcut from the junction at (-60, 60) to the one at (-180, 180), with a big hump halfway.
				DiagonalPark = { X = -120, Z = 120, Width = 14 },
				BigHumps = {
					{ X = -120, Z = 120, Yaw = 135, Height = 6, Length = 40, Crest = 4, Width = 12 }, -- mid-park, along the diagonal path
					{ X = 0, Z = 300, Yaw = 90, Height = 7, Length = 44, Crest = 4, Width = 14 }, -- on the long south road (room to go round)
				},
				-- One pad in front of each big jump, from one side (owner 2026-10-27: too many boosts; was 7, the hill had two).
				BoostPads = {
					{ X = 0, Z = -34, Yaw = 0, Length = 14, Width = 18 }, -- the plaza's north edge: off the grid and into the jump block
					{ X = -96, Z = 96, Yaw = 135, Length = 12, Width = 12 }, -- the park path, from the plaza side into its hump
					{ X = -46, Z = 300, Yaw = 90, Length = 12, Width = 14 }, -- the south road, eastbound into its hump
				},
				Tunnel = { X = -180, ZFrom = -43, ZTo = 43, Height = 14 },
				-- The east road's mirror of the tunnel: two leaves meeting mid-block that rise into a jump in the event.
				Drawbridge = { X = 180, Z = 0, LeafLength = 22, Width = 24, Thickness = 0.4 },
				-- Curb hydrants mid-block, spraying into the near lane during the Hydrants event.
				Hydrants = {
					{ X = -46.5, Z = -120, DX = -1, DZ = 0 },
					{ X = -73.5, Z = 120, DX = 1, DZ = 0 },
					{ X = 73.5, Z = -240, DX = -1, DZ = 0 },
					{ X = 46.5, Z = 240, DX = 1, DZ = 0 },
					{ X = 193.5, Z = -120, DX = -1, DZ = 0 },
					{ X = 166.5, Z = 240, DX = 1, DZ = 0 },
					{ X = -193.5, Z = -240, DX = 1, DZ = 0 },
					{ X = -166.5, Z = 240, DX = -1, DZ = 0 },
					{ X = -120, Z = -46.5, DX = 0, DZ = -1 },
					{ X = 120, Z = -73.5, DX = 0, DZ = 1 },
					{ X = -240, Z = 73.5, DX = 0, DZ = -1 },
					{ X = 240, Z = 193.5, DX = 0, DZ = -1 },
				},
				HydrantSpray = 7,
				-- Fruit stalls on the curb a quarter of the way along a block (pickups stand mid-block, props on corners):
				-- swerve to the curb to smash one for a free item.
				FruitStands = {
					{ X = -72, Z = 24, DX = 1, DZ = 0 },
					{ X = 72, Z = -144, DX = -1, DZ = 0 },
					{ X = -192, Z = 96, DX = 1, DZ = 0 },
					{ X = 192, Z = -144, DX = -1, DZ = 0 },
					{ X = 24, Z = 192, DX = 0, DZ = -1 },
					{ X = -96, Z = -192, DX = 0, DZ = 1 },
					{ X = 144, Z = 192, DX = 0, DZ = -1 },
					{ X = -216, Z = -72, DX = 0, DZ = 1 },
				},
			} :: MapFeatures?,
		},
		Gimmicks = {} :: { [string]: number },
	},
	Beach = {
		DisplayName = "Beach",
		Theme = "beach",
		UnlockGems = 500, -- cumulative Gems earned (used for private-server map choice later)
		ClockTime = 16.5,
		Blockout = {
			Half = 320,
			RoadCoords = { -300, -180, -60, 60, 180, 300 },
			RoadWidth = 24,
			CellCenters = { -240, -120, 0, 120, 240 },
			CellSize = 96,
			Sidewalk = 8,
			WallHeight = 14,
			Seed = 21,
			BuildingMinHeight = 10,
			BuildingMaxHeight = 30,
			PickupPoints = 12,
			DropoffPoints = 12,
			NearStartPickups = 4,
			ItemBoxes = 6,
			SkylineInner = 380,
			SkylineOuter = 500,
			SkylineMinHeight = 50,
			SkylineMaxHeight = 150,
			WindowFloorHeight = 6,
			PropsPerCell = 2,
			Features = nil :: MapFeatures?,
		},
		Gimmicks = { SandSlowMult = 0.7, BoardwalkSpeedMult = 1.1 } :: { [string]: number },
	},
}

return Config
