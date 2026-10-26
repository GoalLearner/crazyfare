--!strict
-- Round state machine: Waiting -> PreCountdown (read the board) -> Countdown -> Playing -> Podium -> PreCountdown...
-- Phase 1 loops single rounds; Phase 3 adds the 3-round match and Pit Stop on top of this.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)
local VehicleService = require(script.Parent.VehicleService)
local ComboService = require(script.Parent.ComboService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)

local RoundService = {}

local phase: Types.RoundPhase = "Waiting"
local roundIndex = 1
local phaseStartsAt = 0
local phaseEndsAt = 0
local results: { Types.PodiumEntry }? = nil
local waitingSince: number? = nil
local roundState: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

function RoundService.GetPayload(): Types.RoundStatePayload
	return {
		phase = phase,
		round = roundIndex,
		quota = FareService.GetQuota(),
		startsAt = phaseStartsAt,
		endsAt = phaseEndsAt,
		results = results,
	}
end

local function setPhase(newPhase: Types.RoundPhase, duration: number)
	phase = newPhase
	phaseStartsAt = now()
	phaseEndsAt = if duration > 0 then phaseStartsAt + duration else 0
	roundState:FireAllClients(RoundService.GetPayload())
end

function RoundService.GetPhase(): Types.RoundPhase
	return phase
end

local function beginPreCountdown()
	roundIndex = 1 -- Phase 3: advance through RoundsPerMatch
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	FareService.ResetAll()
	FareService.SetQuota(Config.Round.Quotas[roundIndex])
	ComboService.ResetAll()
	ItemService.ClearAll()
	PassengerService.ClearAll()
	VehicleService.ResetAllToGrid()
	PassengerService.EnsureCount(FareService.TargetNpcCount())
	setPhase("PreCountdown", Config.Round.PreCountdownSeconds)
end

local function beginCountdown()
	setPhase("Countdown", Config.Round.CountdownSeconds)
end

local function beginPlaying()
	setPhase("Playing", Config.Round.CapSeconds)
	VehicleService.SetReleased(true)
	FareService.SetEnabled(true)
	ItemService.SetEnabled(true)
end

local function endRound()
	if phase ~= "Playing" then
		return
	end
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	VehicleService.SetReleased(false)
	results = FareService.GetResults()
	setPhase("Podium", Config.Round.PodiumSeconds)
end

local function beginWaiting()
	waitingSince = nil
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	VehicleService.SetReleased(false)
	setPhase("Waiting", 0)
end

function RoundService.ForceEnd()
	endRound()
end

function RoundService.Init()
	roundState = Remotes.Get("RoundState")

	FareService.OnQuotaReached:Connect(function()
		endRound()
	end)

	Remotes.Get("ClientReady").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "ClientReady", Config.Net.RateLimits.ClientReady, 3) then
			return
		end
		roundState:FireClient(player, RoundService.GetPayload())
		local entry = VehicleService.GetEntry(player)
		if entry then
			Remotes.Get("VehicleAssigned"):FireClient(player, entry.model)
		end
		local item = ItemService.GetHeld(player)
		if item ~= "" then
			Remotes.Get("ItemEvent"):FireClient(player, { kind = "Granted", item = item })
		end
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if #Players:GetPlayers() == 0 and phase ~= "Waiting" then
				beginWaiting()
			end
		end)
	end)
end

function RoundService.Start()
	RunService.Heartbeat:Connect(function()
		local t = now()
		local playerCount = #Players:GetPlayers()

		if phase == "Waiting" then
			if playerCount >= Config.Round.MinPlayers then
				if not waitingSince then
					waitingSince = t
				elseif t - (waitingSince :: number) >= Config.Round.AutoStartDelay then
					beginPreCountdown()
				end
			else
				waitingSince = nil
			end
		elseif phase == "PreCountdown" then
			if t >= phaseEndsAt then
				beginCountdown()
			end
		elseif phase == "Countdown" then
			if t >= phaseEndsAt then
				beginPlaying()
			end
		elseif phase == "Playing" then
			if t >= phaseEndsAt then
				endRound()
			end
		elseif phase == "Podium" then
			if t >= phaseEndsAt then
				if playerCount >= Config.Round.MinPlayers then
					beginPreCountdown()
				else
					beginWaiting()
				end
			end
		end
	end)
end

return RoundService
