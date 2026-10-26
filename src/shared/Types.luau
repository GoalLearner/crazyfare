--!strict
-- Shared type aliases. Payload shapes here are what crosses the network; keep them flat and small.

export type Tier = "Green" | "Yellow" | "Red"
export type RoundPhase = "Waiting" | "PreCountdown" | "Countdown" | "Playing" | "Podium"
export type RankBucket = "Leader" | "Mid" | "Last"

-- One taxi in the 10 Hz snapshot.
export type PlayerSnap = {
	id: number, -- UserId
	name: string,
	x: number,
	z: number,
	yaw: number, -- radians, heading around Y
	cash: number,
	fare: number, -- current fare's base value (0 when empty)
	tier: string, -- "" when empty
	hp: number,
	maxHp: number,
	combo: number,
	rank: number,
	item: string, -- held item id or ""
}

-- One NPC in the snapshot. state: 0 available, 1 boarded (hidden), 2 walking back, 3 thanking
export type NpcSnap = {
	id: number,
	x: number,
	z: number,
	tier: string,
	state: number,
}

export type Snapshot = {
	t: number,
	players: { PlayerSnap },
	npcs: { NpcSnap },
}

export type PodiumEntry = {
	id: number,
	name: string,
	cash: number,
	fares: number,
	bestTip: number,
}

export type RoundStatePayload = {
	phase: RoundPhase,
	round: number,
	quota: number,
	startsAt: number, -- server time the phase began
	endsAt: number, -- server time the phase ends (0 = open-ended)
	results: { PodiumEntry }?,
}

-- FareEvent kinds: "Claimed" | "Delivered" | "Bailed" | "Taken" | "NearDestination"
export type FareEventPayload = {
	kind: string,
	npcId: number?,
	tier: string?,
	base: number?,
	destination: Vector3?,
	destinationIndex: number?,
	startedAt: number?,
	deadline: number?,
	payout: number?,
	tip: number?,
	combo: number?,
	reason: string?, -- bail reason: "hp" | "timeout"
	position: Vector3?,
	line: string?,
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
	base: number,
	pickupIndex: number,
	destinationIndex: number,
	destination: Vector3,
	startedAt: number,
	deadline: number,
	distance: number,
}

return {}
