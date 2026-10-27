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
	GemPrice: number, -- 0 = everyone owns it
	-- Gimmick flags; systems branch on these, never on the vehicle id.
	Hop: boolean?, -- Space hops instead of drifting
	HopPower: number?, -- studs/s of upward velocity per hop
	ImmuneTo: { [string]: boolean }?, -- trap kinds that do nothing to this vehicle
	PassengerDamageMult: number?, -- scales every hit the passenger takes
	PassengerHpBonus: number?, -- extra HP on boarding
	Wobble: number?, -- random steering noise (0..1)
}

export type TierWeightBand = { MaxDistance: number, Green: number, Yellow: number, Red: number }

export type PitStopCardDef = { Name: string, Effect: string, Share: number, Value: number } -- Share: price as a fraction of the next round's quota
export type QuestDef = { Id: string, Text: string, Goal: number, Reward: number }
export type ProductDef = { Id: number, Gems: number, Label: string, Robux: number, Vehicle: string? }
export type GamePassDef = { Id: number, Label: string, Effect: string }

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
}

-- Pedestrians (PedestrianService): walk the sidewalk around each block and cross the street at the corners when no
-- car is coming. Hit one and your passenger walks out. The reaction is a cartoon hop, spin and yell, never a knockdown
-- or injury, which keeps the game in Roblox's "mild violence" band.
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
	PadThrottle = Enum.KeyCode.ButtonR2,
	PadBrake = Enum.KeyCode.ButtonL2,
	PadSteer = Enum.KeyCode.Thumbstick1,
	PadDrift = Enum.KeyCode.ButtonA,
	PadBoost = Enum.KeyCode.ButtonB,
	PadItem = Enum.KeyCode.ButtonX,
	PadHonk = Enum.KeyCode.ButtonY,
	PadReset = Enum.KeyCode.ButtonSelect,
}

Config.Round = {
	MinPlayers = 2, -- live servers wait for this many before a match starts
	StudioMinPlayers = 1, -- so a solo Studio run plays
	AutoStartDelay = 4, -- seconds after MinPlayers is met before PreCountdown
	PreCountdownSeconds = 3, -- "read the board": NPCs visible, cars frozen
	CountdownSeconds = 3, -- 3-2-1
	CapSeconds = 180, -- round time cap; highest earnings this round win at the cap
	Quotas = { 75, 100, 125 }, -- dollars earned THIS round (round 1, 2, 3); paced for 6-9 fares by a good player
	RoundsPerMatch = 3,
	RoundEndSeconds = 5, -- placements shown between a round and its Pit Stop
	MatchEndSeconds = 20, -- final podium + rematch vote
	PodiumSeconds = 10, -- unused since Phase 3; kept for the solo loop
}

Config.Fares = {
	NpcsPerPlayer = 2,
	MinNpcs = 4,
	MaxNpcs = 12, -- never more than PickupPoints
	PickupRadius = 12, -- claim: inside this and slower than StopSpeed
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

-- Pit Stop: between rounds, spend this round's cash on next-round-only boosts. Unspent cash carries forward.
Config.PitStop = {
	Seconds = 30,
	CardsOffered = 5, -- Pit Stop Plus (Phase 6) makes this 6
	MaxBuys = 2, -- cards one player can buy per Pit Stop; the rich still have to choose
	-- Price = Share x the NEXT round's quota (round 2 = $45, round 3 = $60), so cards keep pace with the money and
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
	Count = 10, -- cars per map
	SpeedMin = 18, -- cruise speeds are spread evenly across this range so no two cars match (studs/s; the Yellow Cab tops out at 90)
	SpeedMax = 50,
	Accel = 12, -- studs/s^2 back up to cruise
	Brake = 40, -- studs/s^2 when closing on a slower car ahead
	FollowGap = 24, -- inside this gap (lane point to lane point) a car matches the car ahead; at a body length it stops
	MinImpactSpeed = 15, -- closing speed into a traffic car that counts as a crash (at least a small one); below is a nudge
	JunctionApproach = 60, -- inside this distance of the next intersection's center a car claims it, or stops to wait its turn
	JunctionClear = 24, -- a car holds the intersection until its lane point is this far past the center
	StopLine = 25, -- a waiting car stops with its lane point this far from the center: clear of the crossing lanes and behind the crosswalk
	PedestrianStopDistance = 45, -- someone crossing this far ahead: the car stops for them (a car at full cruise needs ~31 to stop)
	PedestrianLaneHalf = 13, -- either side of the lane line that counts: the whole crossing, not just the car's own lane
	LaneOffset = 6, -- lane center from the road center line
	StraightWeight = 2, -- odds at an intersection: straight vs each possible turn
	TurnWeight = 1,
	SpawnClearance = 70, -- no car spawns this close to a start pad
	SpawnSpacing = 45, -- nor this close to another traffic car
	SpawnTries = 30,
	BodySize = Vector3.new(6, 2.4, 11.5),
	RideHeight = 0.85, -- gap under the body (the wheels fill it)
	Density = 3, -- several times a player cab: you bounce off, it barely notices
	MaxForce = 1000000, -- AlignPosition / AlignOrientation strength that keeps it in its lane
	Responsiveness = 25,
	ResetDistance = 40, -- knocked this far from its lane point, it snaps back
	BlockedLag = 6, -- body this far behind its lane point (a player car in the way): the car waits, and so does the queue behind it
	BlockedRespawn = 8, -- seconds blocked before the car respawns elsewhere so the lane clears
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
	CrashLines = { "OW!", "MY NECK!", "EYES ON THE ROAD!", "WAS THAT A WALL?!", "I SPILLED MY COFFEE!" },
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
	Order = { "YellowCab", "GoKart", "ShoppingCart", "Horse", "NightCab", "IceCreamTruck" },
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
			Color = Color3.fromRGB(250, 200, 40),
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
	} :: { [string]: VehicleStats },
}

-- Permanent upgrades (Gems), global across vehicles in v1. Applied as player attributes Up_<Name> = 1 + Per * level.
Config.Upgrades = {
	Order = { "Speed", "Handling", "Boost" },
	Speed = { Per = 0.03, Max = 5, Costs = { 60, 90, 130, 180, 240 } },
	Handling = { Per = 0.04, Max = 5, Costs = { 60, 90, 130, 180, 240 } },
	Boost = { Per = 0.08, Max = 5, Costs = { 50, 80, 120, 170, 230 } },
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
	} :: { { Name: string, Color: Color3 } },
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
Config.Streak = {
	PerDay = 5,
	MaxDays = 7,
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
	Products = {
		GemsSmall = { Id = 0, Gems = 120, Label = "120 Gems", Robux = 49 },
		GemsMedium = { Id = 0, Gems = 320, Label = "320 Gems", Robux = 99 },
		GemsLarge = { Id = 0, Gems = 900, Label = "900 Gems", Robux = 249 },
		StarterPack = { Id = 0, Gems = 300, Label = "Starter Pack", Robux = 79, Vehicle = "GoKart" }, -- one-time, first 2 sessions
	} :: { [string]: ProductDef },
	ProductOrder = { "GemsSmall", "GemsMedium", "GemsLarge" },
	GamePasses = {
		VIP = { Id = 0, Label = "VIP", Effect = "2x Gems, VIP badge, VIP horn" },
		PitStopPlus = { Id = 0, Label = "Pit Stop Plus", Effect = "6 cards at every Pit Stop" },
	} :: { [string]: GamePassDef },
	VipGemMult = 2,
	PitStopPlusCards = 6,
	StarterPackSessions = 2, -- offered during the player's first N sessions
	-- Premium vehicles: Robux product OR their (large) Gem price.
	VehicleProducts = {
		NightCab = 0,
		IceCreamTruck = 0,
	} :: { [string]: number },
}

-- Sounds. Asset ids are placeholders until the owner uploads audio; 0 = silent. Everything plays through SoundController.
Config.Sounds = {
	Volume = 0.5,
	MusicVolume = 0.25,
	Ids = {
		-- Roblox-licensed Creator Store clips (Pro Sound Effects + APM), picked 2026-10-26; swap any for the owner's own uploads.
		Honk = 9114402481, -- Ferrari 308 Car Honking Dual Air Horns 7
		HonkVip = 9113071178, -- Air Horn Bursts 5
		Engine = 80317022777602, -- Car-Engine-Loop (Roblox Resources group), 9 s loop; pitch follows speed
		Drift = 9120399191, -- Vehicle Skids Long Heavy Tire Squeal 4 (looped while drifting)
		Boost = 9114329395, -- Energy Cloud Whooshing By Very Fast 1
		Pickup = 9113205239, -- Audi Car Door Movement Opening Closing 4
		Deliver = 9113728049, -- Cash Register 2
		Coin = 9126073001, -- Synth Sparkle Tone High Pitch Bell Tone Ding (1.16 s); one per paid stunt, pitched up the chain
		Splat = 9119293925, -- Small Splat 2
		Spinout = 9119197920, -- Slide Whistle 3
		Crash = 9120369181, -- Vehicle Crash 2 (Pro Sound Effects); wall hit with a passenger aboard
		Bail = 9113864076, -- Comic Tube Doink 1
		Countdown = 9114640708, -- Graphic Beeps 6
		Go = 9113072516, -- Air Horn Various Lengths And Pitches 3
		RoundEnd = 1844584907, -- Glamour Fanfare 7 (APM, Milan Pilar)
		Music = 1841068132, -- Keep on Moving (APM, KPM Main Series), 63 s loop
	} :: { [string]: number },
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
	Decay = 6, -- 1/s
}

-- Touch controls (phones/tablets): on-screen buttons sized in pixels.
Config.Touch = {
	ButtonSize = 64,
	Margin = 18,
	Opacity = 0.45,
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
	},
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
		GarageAction = 5,
		RematchVote = 2,
		RequestLeaderboards = 1,
		ShopAction = 4,
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
	MinimapSize = 190, -- px
	PayoutPunchSeconds = 1.6,
	MessageSeconds = 1.6,
	CrashMessageSeconds = 1.0, -- passenger yelp after a crash
	NpcBillboardDistance = 450,
	BeaconHeight = 70, -- destination beacon part height
	Arrow = { Height = 7.5, Length = 4.5, Width = 1.3, Thickness = 0.7, Pitch = 24, Transparency = 0.3, TurnAroundDegrees = 110, SideDegrees = 45 }, -- 3D destination arrow over the local cab; Pitch tilts the nose down (degrees) so the chase cam sees its face
}

-- Each map is a data entry. The blockout spec is shared by DevBlockout (builds it) and the minimap (draws it).
Config.Map = {
	Current = "City",
	Rotation = { "City", "Beach" }, -- one match per entry, in order
	City = {
		DisplayName = "City",
		Theme = "city",
		UnlockGems = 0,
		ClockTime = 14.5,
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
		},
		Gimmicks = { SandSlowMult = 0.7, BoardwalkSpeedMult = 1.1 } :: { [string]: number },
	},
}

return Config
