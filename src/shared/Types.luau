--!strict
-- Shared type aliases. Payload shapes here are what crosses the network; keep them flat and small.

export type Tier = "Green" | "Yellow" | "Red"
export type RoundPhase = "Waiting" | "PreCountdown" | "Countdown" | "Playing" | "RoundEnd" | "PitStop" | "MatchEnd"
export type RankBucket = "Leader" | "Mid" | "Last"
-- Where a person is (SessionService; also the player's SessionState attribute): on the title screen (just joined, not
-- placed yet), racing, riding/walking the city while every seat is taken, in the Taxi Depot between matches, or waiting
-- for the next round's seat (walking meanwhile).
export type SessionState = "Title" | "Driver" | "Passenger" | "Depot" | "Queued"

-- One taxi in the 10 Hz snapshot.
export type PlayerSnap = {
	id: number, -- UserId
	name: string,
	x: number,
	z: number,
	yaw: number, -- radians, heading around Y
	cash: number, -- cents earned toward this round's quota
	fare: number, -- current fare's value in cents (0 when empty; a ticking fare's drops every second)
	tier: string, -- "" when empty
	hp: number,
	maxHp: number,
	combo: number, -- stunt chain (0 = none running)
	rank: number,
	item: string, -- held item id or ""
	gems: number, -- session total
	level: number,
	vip: boolean,
	bot: boolean, -- an AI rival taxi
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
	riders: number, -- people in the group (2+ = a carpool)
	ticking: boolean, -- a ticking fare (Config.Chaos.Ticking)
	player: boolean?, -- a person hailing a cab (Config.PlayerFare)
}

export type Snapshot = {
	t: number,
	players: { PlayerSnap },
	npcs: { NpcSnap },
	bounty: number?, -- UserId of the cash leader wearing the bounty crown (Config.Chaos.Bounty)
}

export type PodiumEntry = {
	id: number,
	name: string,
	cash: number, -- cents: this round's earnings, or the match total on the last round
	fares: number,
	bestTip: number, -- cents
	gems: number?, -- awarded at match end (players only)
	xp: number?,
	levelUp: boolean?,
	bot: boolean?, -- an AI rival taxi
	license: string?, -- match end / Arcade end, people only: the grade this match earned (Config.License.Grades)
	newBest: boolean?, -- that grade beats their best (Arcade: the run beats their best run)
	streak: number?, -- match end: matches in a row, when it paid a bonus
	streakGems: number?,
	friendGems: number?, -- a Roblox friend was in the server
	event: string?, -- a live event multiplied the Gems (Config.Events.Kinds id)
}

export type RoundStatePayload = {
	phase: RoundPhase,
	round: number,
	quota: number,
	startsAt: number, -- server time the phase began
	endsAt: number, -- server time the phase ends (0 = open-ended)
	results: { PodiumEntry }?,
	map: string?, -- current map name
	ready: number?, -- Pit Stop: players who tapped READY
	readyOf: number?, -- Pit Stop: players present (bots never count)
	mode: string?, -- "Race" | "Arcade"
	timeBonus: number?, -- Arcade: seconds just added to the clock
	frenzy: boolean?, -- the last Config.Chaos.Frenzy.Seconds of a race round
	event: string?, -- the world event running (Config.Chaos.Events.List Id)
	eventEndsAt: number?, -- server time it ends
	eventAt: Vector3?, -- where it is, when it has one place (the money truck)
	weather: string?, -- this round's weather (Config.Chaos.Weather.List Id)
	slots: { SlotEntry }?, -- Waiting / MatchEnd: who drives the next match, people first, then bots (the depot board)
	maxDrivers: number?, -- seats on the grid
}

export type SlotEntry = { name: string, id: number, bot: boolean? } -- id: UserId (bots below 0)

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
	passes: { [string]: boolean }, -- game passes owned (Config.Monetization.GamePasses keys)
	xpToNext: number, -- XP needed to reach the next level
	xpIntoLevel: number, -- XP earned since the current level began
	bestLicense: number, -- index into Config.License.Grades (0 = none yet)
	arcadeBest: number, -- cents
	arcadeBestLicense: number,
	coachDone: boolean,
	settings: SettingsPayload,
	inventory: { [string]: { [string]: number } }, -- Paints (owned = 1), Boosts (tokens: next match starts holding one)
	dropCount: number,
	pity: number, -- drops since the last Epic or better
}

-- A post-match drop (DropService -> the player who opened it), or a Mythic pull told to everyone (kind "Mythic").
export type DropEventPayload = {
	kind: string, -- "Drop" | "Mythic"
	tier: string?, -- "Gold" | "Silver" | "Bronze"
	rarity: string?,
	prize: string?, -- Config.Drops.Pool Id
	name: string?, -- what the reveal says ("ROCKET CAB", "75 GEMS")
	duplicateGems: number?, -- you had it: Gems instead
	pity: number?, -- drops since the last Epic or better, after this one
	who: string?, -- "Mythic": the puller's display name
	phantom: boolean?, -- "Mythic": the prize was the Phantom
}

-- OPTIONS: volume steps index Config.Options.VolumeSteps (1 = off); the switches turn camera shake and speed effects off.
export type SettingsPayload = { music: number, sfx: number, shake: boolean, speedFx: boolean }

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
	arcade: { BoardEntry }, -- best Arcade run (cents)
	weekResetsIn: number,
}

export type PitStopCard = { id: string, name: string, effect: string, price: number, bought: boolean }
export type PitStopOfferPayload = { cards: { PitStopCard }, cash: number, endsAt: number, buysLeft: number }

-- FareEvent kinds: "Claimed" | "Delivered" | "Bailed" | "Taken" | "Expired" | "Hurt" | "HunterBonus" | "Stunt" | "ChainBroken"
-- | "NewLeader" (to everyone: `line` = the new leader's name, `you` when it's you) | "Cash" (a money-truck pickup: `payout`)
-- | "Request" (your passenger's request moved: `request`, `progress`, `done`, and `payout` = the bonus when done)
-- | "NextStop" (a carpool's next leg, shaped like "Claimed")
-- | "Golden" (to everyone: a Golden Fare appeared at `position`)
-- | "Rate" (to a rider whose ride just arrived: `line` = the driver's name, `deadline` = when the default rating lands)
-- | "RideTip" (to the driver: the rider's stars came in, `payout` = the tip, `stars`, `line` = the rider's name)
-- | "RideOver" (to a rider: out of the cab, `reason` = "delivered" | "hp" | "timeout" | "released", `payout` = gems)
-- Every ride event a player-fare driver gets is mirrored to the rider with `ride` = true (the rider's HUD shows the
-- trip, not their money).
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
	reason: string?, -- bail reason: "hp" | "timeout"; "ChainBroken": "crash" | "bail" | "idle" | "pedestrian"
	amount: number?, -- "Hurt": HP the passenger lost; "Stunt": cents it paid (0 with no passenger or at the fare's cap)
	source: string?, -- "Hurt": "crash" | an item name | "debug" | ...
	position: Vector3?,
	line: string?,
	passenger: string?, -- "Claimed": the passenger's kind (Config.PassengerTypes.Kinds key)
	golden: boolean?, -- "Claimed": a Golden Fare
	bonus: string?, -- "Delivered": what the passenger's rules did ("SMOOTH RIDE  TIP x2", "GOLDEN x3")
	bounty: boolean?, -- "HunterBonus": the passenger was the leader's (paid times Config.Chaos.Bounty.Mult)
	request: string?, -- "Claimed" / "Request": the passenger's request (Config.Chaos.Requests.List Id)
	progress: number?, -- "Request": toward its Goal
	done: boolean?, -- "Request": just completed
	riders: number?, -- "Claimed" / "NextStop": people aboard (2+ = a carpool)
	ticking: boolean?, -- "Claimed": a ticking fare (the fare drops every second)
	you: boolean?, -- "NewLeader": you took the lead
	ride: boolean?, -- mirrored to a rider: the trip you're riding, not your own fare
	stars: number?, -- "RideTip": the rating
}

-- ItemEvent kinds: "Granted" | "Used" | "Splat" | "Spinout" | "Boost" | "HitConfirm" | "BoxTaken"
-- | "Smash" (you drove through a fruit stand: `item` is the free item, nil when your slot was full)
export type ItemEventPayload = {
	kind: string,
	item: string?,
	seconds: number?,
	coverage: number?,
	position: Vector3?,
	attacker: string?,
	push: Vector3?, -- "Rammed": studs/s to add to your car
	count: number?, -- "Granted": items waiting behind this one (Double Item, bought items)
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
	request: string?, -- Config.Chaos.Requests.List Id the passenger asked for
	requestProgress: number, -- toward its Goal (seconds or count)
	requestDone: boolean,
	riders: number, -- people still aboard, the one going to this stop included (2+ = a carpool)
	stops: { number }, -- carpool: drop-off indices after this one
	ticking: boolean, -- the fare drops every second (Config.Chaos.Ticking)
}

return {}
