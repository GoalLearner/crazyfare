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

local function now(): number
	return workspace:GetServerTimeNow()
end

local function adoptIfMine(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("OwnerUserId") == localPlayer.UserId then
		if State.vehicle ~= inst then
			State.SetVehicle(inst)
		end
	end
end

local function onSnapshot(snapshot: Types.Snapshot)
	State.snapshot = snapshot
	local me = State.GetSelfSnap()
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
	if payload.kind == "Claimed" and payload.destination and payload.deadline and payload.startedAt then
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
		}
	elseif payload.kind == "Stunt" then
		local fare = State.fare
		if fare and payload.stunts then
			fare.stunts = payload.stunts
		end
	elseif payload.kind == "Delivered" or payload.kind == "Bailed" then
		State.fare = nil
	end
	State.FareEvent:Fire(payload)
end

local function onItemEvent(payload: Types.ItemEventPayload)
	local kind = payload.kind
	if kind == "Granted" then
		State.item = payload.item or ""
	elseif kind == "Used" then
		State.item = ""
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
			State.profile = payload :: Types.ProfilePayload
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
	end)
end

function NetController.Start() end

return NetController
