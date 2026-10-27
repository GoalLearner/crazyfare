--!strict
-- Match state machine:
--   Waiting -> PreCountdown (read the board) -> Countdown -> Playing -> RoundEnd -> PitStop -> PreCountdown ...
--   after the last round: Playing -> MatchEnd (podium, Gems, rematch vote) -> PreCountdown of a new match.
-- Cash carries across rounds inside a match (unspent cash is quota progress) and resets with the match.

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
local PitStopService = require(script.Parent.PitStopService)
local GemService = require(script.Parent.GemService)
local ProgressionService = require(script.Parent.ProgressionService)
local QuestService = require(script.Parent.QuestService)
local LeaderboardService = require(script.Parent.LeaderboardService)

local MapService = require(script.Parent.MapService)

local RoundService = {}

local phase: Types.RoundPhase = "Waiting"
local roundIndex = 1
local phaseStartsAt = 0
local phaseEndsAt = 0
local results: { Types.PodiumEntry }? = nil
local waitingSince: number? = nil
local rematchVotes: { [Player]: boolean } = {}
local matchCount = 0
local roundState: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function voteCount(): number
	local n = 0
	for player in rematchVotes do
		if player.Parent then
			n += 1
		end
	end
	return n
end

function RoundService.GetPayload(): Types.RoundStatePayload
	return {
		phase = phase,
		round = roundIndex,
		quota = FareService.GetQuota(),
		startsAt = phaseStartsAt,
		endsAt = phaseEndsAt,
		results = results,
		map = MapService.GetCurrentMap(),
		votes = if phase == "MatchEnd" then voteCount() else nil,
		voters = if phase == "MatchEnd" then #Players:GetPlayers() else nil,
	}
end

local function broadcast()
	roundState:FireAllClients(RoundService.GetPayload())
end

local function setPhase(newPhase: Types.RoundPhase, duration: number)
	phase = newPhase
	phaseStartsAt = now()
	phaseEndsAt = if duration > 0 then phaseStartsAt + duration else 0
	broadcast()
end

function RoundService.GetPhase(): Types.RoundPhase
	return phase
end

function RoundService.GetRound(): number
	return roundIndex
end

-- Fresh round: board, items, cars on the grid, boosts from the Pit Stop applied.
local function beginRoundSetup()
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	FareService.ResetRound()
	FareService.SetQuota(Config.Round.Quotas[math.min(roundIndex, #Config.Round.Quotas)])
	ComboService.ResetAll()
	ItemService.ClearAll()
	PassengerService.ClearAll()
	VehicleService.ResetAllToGrid()
	PitStopService.ApplyBoosts()
	PassengerService.EnsureCount(FareService.TargetNpcCount())
	setPhase("PreCountdown", Config.Round.PreCountdownSeconds)
end

local function beginMatch()
	roundIndex = 1
	table.clear(rematchVotes)
	FareService.ResetMatch()
	-- Map rotation: one match per entry.
	local rotation = Config.Map.Rotation
	local nextMap = rotation[(matchCount % #rotation) + 1]
	matchCount += 1
	if nextMap and nextMap ~= MapService.GetCurrentMap() then
		PassengerService.ClearAll()
		ItemService.ClearAll()
		MapService.LoadMap(nextMap)
		ItemService.RefreshBoxes()
		VehicleService.RespawnAll()
	end
	beginRoundSetup()
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
	PitStopService.ClearBoosts()
	results = FareService.GetResults(roundIndex >= Config.Round.RoundsPerMatch) -- the last round shows the match total
	if roundIndex < Config.Round.RoundsPerMatch then
		setPhase("RoundEnd", Config.Round.RoundEndSeconds)
	else
		results = GemService.AwardMatch(results :: { Types.PodiumEntry })
		ProgressionService.AwardMatch(results :: { Types.PodiumEntry })
		QuestService.OnMatchEnd(results :: { Types.PodiumEntry })
		for _, entry in results :: { Types.PodiumEntry } do
			local player = Players:GetPlayerByUserId(entry.id)
			if player then
				LeaderboardService.AddWeeklyGems(player, entry.gems or 0)
			end
		end
		table.clear(rematchVotes)
		setPhase("MatchEnd", Config.Round.MatchEndSeconds)
	end
end

local function beginPitStop()
	local closesAt = now() + Config.PitStop.Seconds
	PitStopService.Open(roundIndex, closesAt)
	setPhase("PitStop", Config.PitStop.Seconds)
end

local function beginWaiting()
	waitingSince = nil
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	VehicleService.SetReleased(false)
	PitStopService.Close()
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

	Remotes.Get("RematchVote").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "RematchVote", Config.Net.RateLimits.RematchVote) then
			return
		end
		if phase ~= "MatchEnd" or rematchVotes[player] then
			return
		end
		rematchVotes[player] = true
		broadcast()
		if voteCount() >= #Players:GetPlayers() then
			beginMatch()
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		rematchVotes[player] = nil
		task.defer(function()
			if #Players:GetPlayers() == 0 and phase ~= "Waiting" then
				beginWaiting()
			end
		end)
	end)
end

local function minPlayers(): number
	return if RunService:IsStudio() then Config.Round.StudioMinPlayers else Config.Round.MinPlayers
end

function RoundService.Start()
	RunService.Heartbeat:Connect(function()
		local t = now()
		local playerCount = #Players:GetPlayers()

		if phase == "Waiting" then
			if playerCount >= minPlayers() then
				if not waitingSince then
					waitingSince = t
				elseif t - (waitingSince :: number) >= Config.Round.AutoStartDelay then
					beginMatch()
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
		elseif phase == "RoundEnd" then
			if t >= phaseEndsAt then
				beginPitStop()
			end
		elseif phase == "PitStop" then
			if t >= phaseEndsAt then
				PitStopService.Close()
				roundIndex += 1
				beginRoundSetup()
			end
		elseif phase == "MatchEnd" then
			if t >= phaseEndsAt then
				if playerCount >= minPlayers() then
					beginMatch()
				else
					beginWaiting()
				end
			end
		end
	end)
end

return RoundService
