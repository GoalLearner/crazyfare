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
	WheelType: string, -- "wheels" | "legs" (animation only)
	TopSpeed: number, -- studs/s
	Accel: number, -- studs/s^2 at standstill
	Handling: number, -- lateral grip rate (1/s); higher = sticks harder
	DriftGrip: number, -- fraction of Handling kept on the rear axle while drifting
	BoostTank: number, -- seconds of boost at full tank
	SteerMax: number, -- degrees at standstill
	Gimmick: string,
	Color: Color3,
}

export type TierWeightBand = { MaxDistance: number, Green: number, Yellow: number, Red: number }

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
	MinPlayers = 1, -- 1 so a solo Studio run plays; raise to 2 for the public place
	AutoStartDelay = 4, -- seconds after MinPlayers is met before PreCountdown
	PreCountdownSeconds = 3, -- "read the board": NPCs visible, cars frozen
	CountdownSeconds = 3, -- 3-2-1
	CapSeconds = 240, -- round time cap; highest cash wins at the cap
	Quotas = { 30, 45, 60 }, -- round 1, 2, 3
	RoundsPerMatch = 3, -- Phase 3 uses this; Phase 1 loops round 1
	PodiumSeconds = 10,
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
		Green = { Base = 3, Hp = 60, Color = Color3.fromRGB(80, 220, 100), MinTrip = 60, MaxTrip = 190, Label = "SHORT" },
		Yellow = { Base = 6, Hp = 80, Color = Color3.fromRGB(250, 210, 60), MinTrip = 190, MaxTrip = 330, Label = "MEDIUM" },
		Red = { Base = 10, Hp = 100, Color = Color3.fromRGB(240, 70, 70), MinTrip = 330, MaxTrip = 9999, Label = "LONG" },
	} :: { [string]: TierDef },
	-- Spawn weighting by the PickupPoint's distance from the StartGrid center: greens near, reds far.
	TierWeightsByDistance = {
		{ MaxDistance = 150, Green = 70, Yellow = 25, Red = 5 },
		{ MaxDistance = 250, Green = 25, Yellow = 50, Red = 25 },
		{ MaxDistance = 9999, Green = 5, Yellow = 30, Red = 65 },
	} :: { TierWeightBand },
	TimeBase = 8, -- fare seconds = TimeBase + distance / TimeSpeed
	TimeSpeed = 30,
	TimeoutBails = false, -- true: timer at 0 = passenger bails (no attacker). false: pays base, no tip (owner call 2026-10-26)
	ThanksSeconds = 2, -- delivered NPC lingers, then despawns
	RespawnDelay = 1, -- before a replacement NPC appears
}

Config.Tips = {
	MaxFrac = 0.8, -- a perfect ride tips 80% of base
	TimeWeight = 0.5, -- speedy share
	ChillWeight = 0.5, -- chill share
	TimeFloor = 0.15, -- fraction of timer remaining where the speedy tip starts
	TimeCeil = 0.85, -- fraction where it maxes
	HpFloor = 0.4, -- passenger HP fraction where the chill tip starts
}

Config.Combo = {
	Step = 0.1, -- multiplier per step
	Max = 1.5,
	IdleSeconds = 3, -- no event for this long starts the decay
	DecayStepSeconds = 0.5, -- then lose one step per this
	DriftTickSeconds = 0.5, -- one step per this much drifting
	AirtimeStepSeconds = 0.5, -- one step per this much airtime
	NearMissMinSpeed = 45,
	MinSpeedForEvents = 20, -- server rejects combo events while slower than this
	MaxEventsPerSecond = 8,
}

Config.Passenger = {
	RegenPerSecond = 2,
	RegenDelay = 3, -- seconds after damage before regen resumes
	RegenMinSpeed = 5, -- must be driving
	CrashDeltaThreshold = 30, -- server-observed velocity delta (studs/s) that starts to hurt
	CrashDamagePerStud = 0.6,
	CrashDamageMax = 35,
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
		TurnRate = 3.5, -- radians/s of homing
		LockRange = 250, -- nearest loaded rival inside this at launch
		HitRadius = 7,
		Lifetime = 4,
		Damage = 30,
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
	Stats = {
		YellowCab = {
			DisplayName = "Yellow Cab",
			WheelType = "wheels",
			TopSpeed = 90,
			Accel = 45,
			Handling = 6,
			DriftGrip = 0.25,
			BoostTank = 4,
			SteerMax = 32,
			Gimmick = "none",
			Color = Color3.fromRGB(250, 200, 40),
		},
	} :: { [string]: VehicleStats },
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
	NpcBillboardDistance = 450,
	BeaconHeight = 70, -- destination beacon part height
	Arrow = { Height = 10, Length = 7, Width = 1.6, Thickness = 0.5 }, -- 3D destination arrow over the local cab
}

-- Each map is a data entry. The blockout spec is shared by DevBlockout (builds it) and the minimap (draws it).
Config.Map = {
	Current = "City",
	City = {
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
}

return Config
