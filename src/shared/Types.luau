--!strict
-- Shared type aliases. Payload shapes here are what crosses the network; keep them flat and small.

export type Tier = "Green" | "Yellow" | "Red"
export type RoundPhase = "Waiting" | "PreCountdown" | "Countdown" | "Playing" | "RoundEnd" | "PitStop" | "MatchEnd"
export type RankBucket = "Leader" | "Mid" | "Last"

-- One taxi in the 10 Hz snapshot.
export type PlayerSnap = {
	id: number, -- UserId
	name: string,
	x: number,
	z: number,
	yaw: number, -- radians, heading around Y
	cash: number, -- cents earned toward this round's quota
	fare: number, -- current fare's base value in cents (0 when empty)
	tier: string, -- "" when empty
	hp: number,
	maxHp: number,
	combo: number, -- stunt chain (0 = none running)
	rank: number,
	item: string, -- held item id or ""
	gems: number, -- session total
	level: number,
	vip: boolean,
}

-- One NPC in the snapshot. state: 0 available, 1 boarded (hidden), 2 walking back, 3 thanking
export type NpcSnap = {
	id: number,
	x: number,
	z: number,
	tier: string,
	state: number,
	kind: string, -- Config.PassengerTypes.Kinds key
	golden: boolean,
}

export type Snapshot = {
	t: number,
	players: { PlayerSnap },
	npcs: { NpcSnap },
}

export type PodiumEntry = {
	id: number,
	name: string,
	cash: number, -- cents: this round's earnings, or the match total on the last round
	fares: number,
	bestTip: number, -- cents
	gems: number?, -- awarded at match end
	xp: number?,
	levelUp: boolean?,
}

export type RoundStatePayload = {
	phase: RoundPhase,
	round: number,
	quota: number,
	startsAt: number, -- server time the phase began
	endsAt: number, -- server time the phase ends (0 = open-ended)
	results: { PodiumEntry }?,
	map: string?, -- current map name
	votes: number?, -- rematch votes so far (MatchEnd)
	voters: number?, -- players present
}

export type ProfilePayload = {
	gems: number,
	level: number,
	xp: number,
	owned: { [string]: boolean },
	selected: string,
	paint: string,
	upgrades: { [string]: number },
	stats: { [string]: number },
	vip: boolean,
	pitStopPlus: boolean,
	showStarterPack: boolean, -- first sessions only, until bought
	xpToNext: number, -- XP needed to reach the next level
	xpIntoLevel: number, -- XP earned since the current level began
}

export type QuestEntry = { id: string, text: string, goal: number, progress: number, reward: number, done: boolean }
export type QuestPayload = {
	daily: { QuestEntry },
	weekly: QuestEntry?,
	streakDays: number,
	dailyResetsIn: number, -- seconds
	weeklyResetsIn: number,
	notice: string?, -- one-shot message (quest done, level up, streak)
}

export type BoardEntry = { id: number, name: string, value: number }
export type LeaderboardPayload = {
	weekly: { BoardEntry },
	friends: { BoardEntry },
	bestTip: { BoardEntry },
	knockouts: { BoardEntry },
	weekResetsIn: number,
}

export type PitStopCard = { id: string, name: string, effect: string, price: number, bought: boolean }
export type PitStopOfferPayload = { cards: { PitStopCard }, cash: number, endsAt: number, buysLeft: number }

-- FareEvent kinds: "Claimed" | "Delivered" | "Bailed" | "Taken" | "Expired" | "Hurt" | "HunterBonus" | "Stunt" | "ChainBroken"
-- | "Golden" (to everyone: a Golden Fare appeared at `position`)
export type FareEventPayload = {
	kind: string,
	npcId: number?,
	tier: string?,
	base: number?,
	destination: Vector3?,
	destinationIndex: number?,
	destinationName: string?, -- "Claimed": "THE STADIUM"
	startedAt: number?,
	deadline: number?,
	payout: number?,
	tip: number?,
	stunts: number?, -- "Delivered": stunt cash this ride paid; "Stunt": stunt cash riding in the fare so far (cents)
	grade: string?, -- "Delivered": "Speedy" | "OnTime" | "Slow" (Config.Grades)
	stunt: string?, -- "Stunt": "Drift" | "Airtime" | "NearMiss"
	chain: number?, -- "Stunt": chain after it; "ChainBroken": the chain that ended
	reason: string?, -- bail reason: "hp" | "timeout" | "pedestrian"; "ChainBroken": "crash" | "bail" | "idle"
	amount: number?, -- "Hurt": HP the passenger lost; "Stunt": cents it paid (0 with no passenger or at the fare's cap)
	source: string?, -- "Hurt": "crash" | an item name | "debug" | ...
	position: Vector3?,
	line: string?,
	passenger: string?, -- "Claimed": the passenger's kind (Config.PassengerTypes.Kinds key)
	golden: boolean?, -- "Claimed": a Golden Fare
	bonus: string?, -- "Delivered": what the passenger's rules did ("SMOOTH RIDE  TIP x2", "GOLDEN x3")
}

-- ItemEvent kinds: "Granted" | "Used" | "Splat" | "Spinout" | "Boost" | "HitConfirm" | "BoxTaken"
export type ItemEventPayload = {
	kind: string,
	item: string?,
	seconds: number?,
	coverage: number?,
	position: Vector3?,
	attacker: string?,
}

-- Client -> server combo report. kind: "Drift" | "Airtime" | "NearMiss"; value = seconds for Drift/Airtime
export type ComboEventPayload = {
	kind: string,
	value: number,
}

export type Fare = {
	npcId: number,
	expired: boolean, -- timer ran out: passenger still rides, tip is gone
	tier: string,
	base: number, -- cents
	pickupIndex: number,
	destinationIndex: number,
	destination: Vector3,
	startedAt: number,
	deadline: number,
	distance: number,
	stuntTips: number, -- cents of stunt cash this ride has earned so far
	kind: string, -- the passenger's kind (Config.PassengerTypes.Kinds key)
	golden: boolean,
}

return {}
