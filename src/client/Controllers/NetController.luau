--!strict
-- The only place remotes are received. Writes State and fires its signals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)

local NetController = {}

local localPlayer = Players.LocalPlayer
local settingsLoaded = false -- your profile's OPTIONS were applied

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The cab you ride in as a player fare (RidingWith = its owner's UserId), found by its OwnerUserId.
local function findRide()
	local id = localPlayer:GetAttribute("RidingWith")
	local chassis: BasePart? = nil
	if typeof(id) == "number" then
		for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
			if inst:IsA("Model") and inst:GetAttribute("OwnerUserId") == id and inst:GetAttribute("Depot") ~= true then
				chassis = inst.PrimaryPart
				break
			end
		end
	end
	local driverId = if typeof(id) == "number" then id else 0
	if chassis ~= State.rideChassis or driverId ~= State.rideDriverId then
		State.rideChassis = chassis
		State.rideDriverId = driverId
		State.RideChanged:Fire()
	end
end

local function adoptIfMine(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("OwnerUserId") == localPlayer.UserId then
		if State.vehicle ~= inst then
			State.SetVehicle(inst)
		end
	end
	if State.rideDriverId ~= 0 and not State.rideChassis then
		findRide() -- your driver's cab was respawned
	end
end

local function onSnapshot(snapshot: Types.Snapshot)
	State.snapshot = snapshot
	local me = State.GetSelfSnap()
	-- riding along: the fare card's passenger HP is yours, which is the cab's
	if State.rideDriverId ~= 0 then
		for _, p in snapshot.players do
			if p.id == State.rideDriverId then
				State.hp = p.hp
				State.maxHp = p.maxHp
				State.combo = p.combo
			end
		end
	end
	if me then
		State.cash = me.cash
		State.hp = me.hp
		State.maxHp = me.maxHp
		State.combo = me.combo
		State.rank = me.rank
		State.item = me.item
		State.gems = me.gems or 0
	end
	State.SnapshotReceived:Fire(snapshot)
end

local function onRoundState(payload: Types.RoundStatePayload)
	local previous = State.round
	State.round = payload
	if payload.phase == "PreCountdown" or (payload.phase == "Waiting" and (not previous or previous.phase ~= "Waiting")) then
		State.ResetRound()
	end
	State.RoundChanged:Fire(payload)
end

local function onFareEvent(payload: Types.FareEventPayload)
	if (payload.kind == "Claimed" or payload.kind == "NextStop") and payload.destination and payload.deadline and payload.startedAt then
		State.fare = {
			tier = payload.tier or "Green",
			base = payload.base or 0,
			destination = payload.destination,
			destinationIndex = payload.destinationIndex or 0,
			destinationName = payload.destinationName or "",
			startedAt = payload.startedAt,
			deadline = payload.deadline,
			stunts = 0,
			passenger = payload.passenger or "Regular",
			golden = payload.golden == true,
			request = payload.request,
			requestProgress = 0,
			requestDone = false,
			riders = payload.riders or 1,
			ticking = payload.ticking == true,
		}
	elseif payload.kind == "Request" then
		local fare = State.fare
		if fare and fare.request == payload.request then
			fare.requestProgress = payload.progress or fare.requestProgress
			fare.requestDone = payload.done == true
		end
	elseif payload.kind == "Stunt" then
		local fare = State.fare
		if fare and payload.stunts then
			fare.stunts = payload.stunts
		end
	elseif payload.kind == "Delivered" or payload.kind == "Bailed" or payload.kind == "RideOver" then
		State.fare = nil
	end
	State.FareEvent:Fire(payload)
end

local function onItemEvent(payload: Types.ItemEventPayload)
	local kind = payload.kind
	if kind == "Granted" then
		State.item = payload.item or ""
		State.itemCount = payload.count or 0
	elseif kind == "Used" then
		State.item = ""
		State.itemCount = 0 -- the next in line arrives with its own "Granted"
	elseif kind == "Boost" then
		State.nitroUntil = now() + (payload.seconds or Config.Items.LemonNitro.Seconds)
	elseif kind == "Spinout" then
		State.spinUntil = now() + (payload.seconds or Config.Items.Banana.SpinSeconds)
		State.Shake:Fire(Config.Shake.Spinout)
		State.spinDirection = if math.random() < 0.5 then -1 else 1
	elseif kind == "Oil" then
		State.oilUntil = now() + (payload.seconds or Config.Items.OilSlick.Seconds)
	elseif kind == "Rammed" then
		State.Shake:Fire(Config.Shake.Rammed)
		State.pendingShove = payload.push or Vector3.zero
	elseif kind == "Ram" then
		State.Shake:Fire(Config.Shake.Ram)
	elseif kind == "Launched" then
		State.pendingShove += payload.push or Vector3.zero -- a hydrant throws your car up
	elseif kind == "ShieldUp" then
		State.shieldUp = true
	elseif kind == "ShieldBreak" then
		State.shieldUp = false
	elseif kind == "Splat" then
		State.Shake:Fire(Config.Shake.Splat)
		State.splatStartedAt = now()
		local wipe = payload.seconds or Config.Items.Tomato.WipeSeconds
		local extraWiper = localPlayer:GetAttribute("Pit_ExtraWiper")
		if typeof(extraWiper) == "number" then
			wipe *= extraWiper
		end
		State.splatUntil = now() + wipe
		State.splatCoverage = payload.coverage or Config.Items.Tomato.SplatCoverage
	end
	State.ItemEvent:Fire(payload)
end

function NetController.Init()
	Remotes.Get("VehicleAssigned").OnClientEvent:Connect(function(model: any)
		if typeof(model) == "Instance" and model:IsA("Model") then
			State.SetVehicle(model)
		end
	end)
	Remotes.Get("Snapshot").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) == "table" then
			onSnapshot(snapshot :: Types.Snapshot)
		end
	end)
	Remotes.Get("RoundState").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			onRoundState(payload :: Types.RoundStatePayload)
		end
	end)
	Remotes.Get("FareEvent").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			onFareEvent(payload :: Types.FareEventPayload)
		end
	end)
	Remotes.Get("ItemEvent").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			onItemEvent(payload :: Types.ItemEventPayload)
		end
	end)
	Remotes.Get("PitStopOffer").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			State.pitStop = payload :: Types.PitStopOfferPayload
			State.PitStopChanged:Fire()
		end
	end)
	Remotes.Get("ProfileSync").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			local profile = payload :: Types.ProfilePayload
			State.profile = profile
			-- your saved OPTIONS, once: after that your own changes lead (they're saved as you make them)
			if not settingsLoaded and typeof(profile.settings) == "table" then
				settingsLoaded = true
				State.settings = profile.settings
				State.SettingsChanged:Fire()
			end
			State.ProfileChanged:Fire()
		end
	end)
	Remotes.Get("QuestSync").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			local quests = payload :: Types.QuestPayload
			State.quests = quests
			State.QuestsChanged:Fire()
			if quests.notice then
				State.Notice:Fire(quests.notice)
			end
		end
	end)
	Remotes.Get("LeaderboardSync").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			State.boards = payload :: Types.LeaderboardPayload
			State.BoardsChanged:Fire()
		end
	end)

	-- Fallback discovery in case VehicleAssigned arrived before we were listening.
	for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
		adoptIfMine(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Vehicle):Connect(adoptIfMine)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.Vehicle):Connect(function(inst: Instance)
		if State.vehicle == inst then
			State.SetVehicle(nil)
		end
		if State.rideChassis and State.rideChassis:IsDescendantOf(inst) then
			State.rideChassis = nil
			State.RideChanged:Fire()
		end
	end)

	-- Where you are (SessionService) and whose cab you ride in, from your own attributes.
	local function readSession()
		local state = localPlayer:GetAttribute("SessionState")
		local current = if typeof(state) == "string" then state else ""
		if current ~= State.sessionState then
			State.sessionState = current
			if current ~= "Driver" then
				State.pitStop = nil -- the Pit Stop is for drivers
			end
			State.SessionChanged:Fire(current)
		end
	end
	readSession()
	localPlayer:GetAttributeChangedSignal("SessionState"):Connect(readSession)
	findRide()
	localPlayer:GetAttributeChangedSignal("RidingWith"):Connect(function()
		findRide()
		if State.rideDriverId == 0 then
			State.fare = nil
		end
	end)
end

function NetController.Start() end

return NetController
