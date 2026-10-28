--!strict
-- Client-side world state, written by NetController and VehicleController, read by everything that draws.
-- Controllers never talk to each other directly; they read this table and listen to its signals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

export type FareInfo = {
	tier: string,
	base: number,
	destination: Vector3,
	destinationIndex: number,
	destinationName: string, -- "THE STADIUM" ("" if the map gave none)
	startedAt: number,
	deadline: number,
	stunts: number, -- stunt cash riding in the fare (cents)
	passenger: string, -- the passenger's kind (Config.PassengerTypes.Kinds key)
	golden: boolean, -- a Golden Fare (triple pay, gold everything)
	request: string?, -- what they asked for on the way (Config.Chaos.Requests.List Id)
	requestProgress: number,
	requestDone: boolean,
	riders: number, -- people aboard (2+ = a carpool)
	ticking: boolean, -- the fare drops every second (Config.Chaos.Ticking)
}

local defaultStats = Config.Vehicles.Stats[Config.Vehicles.Default]
local defaultSettings = Config.Data.Template.Settings

local State = {
	vehicle = nil :: Model?, -- the car you drive (grid or depot); nil on foot
	chassis = nil :: BasePart?,
	sessionState = "", -- "Title" | "Driver" | "Passenger" | "Depot" | "Queued" (your SessionState attribute; "" until placed)
	rideChassis = nil :: BasePart?, -- riding along in someone's cab (a player fare): its chassis
	rideDriverId = 0, -- that cab's owner (0 when not riding)
	stats = defaultStats,
	snapshot = nil :: Types.Snapshot?,
	round = nil :: Types.RoundStatePayload?,
	fare = nil :: FareInfo?,
	item = "",
	pitStop = nil :: Types.PitStopOfferPayload?,
	profile = nil :: Types.ProfilePayload?,
	quests = nil :: Types.QuestPayload?,
	boards = nil :: Types.LeaderboardPayload?,
	-- OPTIONS (from your profile, then your own changes)
	settings = { music = defaultSettings.Music, sfx = defaultSettings.Sfx, shake = defaultSettings.Shake, speedFx = defaultSettings.SpeedFx } :: Types.SettingsPayload,
	gems = 0,
	-- self, mirrored from the snapshot
	cash = 0,
	hp = 0,
	maxHp = 0,
	combo = 1,
	rank = 0,
	-- local driving state (VehicleController writes these every frame)
	speed = 0,
	forwardSpeed = 0,
	drifting = false,
	boosting = false, -- Shift boost, Lemon Nitro or a Dash: flames, whoosh, wider FOV
	dashing = false,
	grounded = true,
	boostTank = 0,
	boostTankMax = defaultStats.BoostTank,
	hopReadyAt = 0, -- os.clock() when the hop is ready again (Config.Chaos.Hop.Cooldown)
	-- timed effects (server time)
	nitroUntil = 0,
	spinUntil = 0,
	spinDirection = 1,
	oilUntil = 0,
	shieldUp = false,
	splatUntil = 0,
	splatStartedAt = 0,
	splatCoverage = 0,
	pendingShove = Vector3.zero, -- a ram's push, added to your car on the next physics step
}

local vehicleChanged: Signal.Signal<Model?> = Signal.new()
local fareEvent: Signal.Signal<Types.FareEventPayload> = Signal.new()
local itemEvent: Signal.Signal<Types.ItemEventPayload> = Signal.new()
local roundChanged: Signal.Signal<Types.RoundStatePayload> = Signal.new()
local snapshotReceived: Signal.Signal<Types.Snapshot> = Signal.new()
local honk: Signal.Signal<nil> = Signal.new()
local pitStopChanged: Signal.Signal<nil> = Signal.new()
local profileChanged: Signal.Signal<nil> = Signal.new()
local questsChanged: Signal.Signal<nil> = Signal.new()
local boardsChanged: Signal.Signal<nil> = Signal.new()
local notice: Signal.Signal<string> = Signal.new()
local shake: Signal.Signal<number> = Signal.new()
local dashed: Signal.Signal<string> = Signal.new()
local landed: Signal.Signal<number> = Signal.new()
local hopped: Signal.Signal<nil> = Signal.new()
local riderSaid: Signal.Signal<string> = Signal.new()
local sessionChanged: Signal.Signal<string> = Signal.new()
local rideChanged: Signal.Signal<nil> = Signal.new()
local settingsChanged: Signal.Signal<nil> = Signal.new()

State.VehicleChanged = vehicleChanged
State.FareEvent = fareEvent
State.ItemEvent = itemEvent
State.RoundChanged = roundChanged
State.SnapshotReceived = snapshotReceived
State.Honk = honk
State.PitStopChanged = pitStopChanged
State.ProfileChanged = profileChanged
State.QuestsChanged = questsChanged
State.BoardsChanged = boardsChanged
State.Notice = notice -- one-shot HUD messages from the server (quest done, level up, streak)
State.Shake = shake -- camera shake strength (Config.Shake)
State.Dashed = dashed -- the local cab just launched: "Dash" (brake tap) or "Pad" (a boost pad)
State.Landed = landed -- the local cab touched down after this many seconds of air
State.Hopped = hopped -- the local cab just hopped (dust, a thump, the coach)
State.RiderSaid = riderSaid -- your own passenger said this (shown in the HUD's bubble over your cab, never stacked)
State.SessionChanged = sessionChanged -- your session state changed (driving, on foot, in the depot)
State.RideChanged = rideChanged -- you got into (or out of) someone's cab as their passenger
State.SettingsChanged = settingsChanged -- OPTIONS changed (or arrived with your profile): volumes, shake, speed effects

-- The cab the camera, popups and arrow follow: the one you ride in, else your own.
function State.ViewChassis(): BasePart?
	return State.rideChassis or State.chassis
end

function State.IsDriver(): boolean
	return State.sessionState == "Driver"
end

function State.SetVehicle(model: Model?)
	State.vehicle = model
	State.chassis = if model then model.PrimaryPart else nil
	local vehicleId = if model then model:GetAttribute("VehicleId") else nil
	State.stats = (if typeof(vehicleId) == "string" then Config.Vehicles.Stats[vehicleId] else nil) or defaultStats
	vehicleChanged:Fire(model)
end

function State.GetSelfSnap(): Types.PlayerSnap?
	local snap = State.snapshot
	if not snap then
		return nil
	end
	local userId = game:GetService("Players").LocalPlayer.UserId
	for _, p in snap.players do
		if p.id == userId then
			return p
		end
	end
	return nil
end

function State.GetPhase(): Types.RoundPhase
	local round = State.round
	return if round then round.phase else "Waiting"
end

-- Clear everything that belongs to one round.
function State.ResetRound()
	State.fare = nil
	State.item = ""
	State.boostTank = 0
	State.hopReadyAt = 0
	State.nitroUntil = 0
	State.spinUntil = 0
	State.oilUntil = 0
	State.shieldUp = false
	State.splatUntil = 0
	State.splatCoverage = 0
	State.pendingShove = Vector3.zero
	State.combo = 0 -- stunt chain from the snapshot
	State.cash = 0
	State.hp = 0
	State.maxHp = 0
end

return State
