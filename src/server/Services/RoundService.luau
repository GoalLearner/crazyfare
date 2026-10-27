--!strict
-- Match state machine:
--   Waiting -> PreCountdown (read the board) -> Countdown -> Playing -> RoundEnd -> PitStop -> PreCountdown ...
--   after the last round: Playing -> MatchEnd (podium, Gems, rematch vote) -> PreCountdown of a new match.
-- Cash carries across rounds inside a match (unspent cash is quota progress) and resets with the match.
-- Arcade mode (Config.Arcade): one run on the clock instead of rounds: PreCountdown -> Countdown -> Playing (the clock
-- grows with pickups and arrivals) -> MatchEnd (the run's grade) -> the next run. A reserved Arcade server is always
-- in it; in Studio the server switches on request. RACE sends you back to the server you came from (your friends are
-- there), or to any server if that one is gone or full.

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
local BotService = require(script.Parent.BotService)
local SessionService = require(script.Parent.SessionService)

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
local mode = "Race" -- "Race" | "Arcade"
local arcadeServer = false -- a reserved server someone was sent to for Arcade
local returnTo: { [Player]: string } = {} -- Arcade server: the JobId each player came from
local retried: { [Player]: boolean } = {}

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
		quota = if mode == "Arcade" then 0 else FareService.GetQuota(), -- 0: no quota (the clock ends an Arcade run)
		startsAt = phaseStartsAt,
		endsAt = phaseEndsAt,
		results = results,
		map = MapService.GetCurrentMap(),
		votes = if phase == "MatchEnd" then voteCount() else nil,
		voters = if phase == "MatchEnd" then #Players:GetPlayers() else nil,
		mode = mode,
	}
end

function RoundService.GetMode(): string
	return mode
end

local function broadcast(timeBonus: number?)
	local payload = RoundService.GetPayload()
	payload.timeBonus = timeBonus
	roundState:FireAllClients(payload)
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

-- Fresh round: bots fill (or give up) seats, board, items, cars on the grid, boosts from the Pit Stop applied.
local function beginRoundSetup()
	results = nil
	BotService.Rebalance()
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

-- One Arcade run: no bots, no quota, the City, everyone back on the grid, a fresh board.
local function beginArcadeRun()
	mode = "Arcade"
	roundIndex = 1
	results = nil
	table.clear(rematchVotes)
	BotService.RemoveAll()
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	FareService.ResetMatch()
	FareService.DisableQuota()
	ComboService.ResetAll()
	ItemService.ClearAll()
	PassengerService.ClearAll()
	PitStopService.ClearBoosts()
	if MapService.GetCurrentMap() ~= Config.Arcade.Map then
		MapService.LoadMap(Config.Arcade.Map)
		ItemService.RefreshBoxes()
		VehicleService.RespawnAll()
	end
	VehicleService.ResetAllToGrid()
	PassengerService.EnsureCount(FareService.TargetNpcCount())
	setPhase("PreCountdown", Config.Round.PreCountdownSeconds)
end

-- The clock grows (never past MaxClock from now) and everyone is told by how much.
local function addTime(seconds: number)
	if mode ~= "Arcade" or phase ~= "Playing" or seconds <= 0 then
		return
	end
	phaseEndsAt = math.min(now() + Config.Arcade.MaxClock, phaseEndsAt + seconds)
	broadcast(seconds)
end

local function endArcade()
	if phase ~= "Playing" then
		return
	end
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	VehicleService.SetReleased(false)
	local run = FareService.GetResults(true)
	ProgressionService.AwardArcade(run)
	for _, entry in run do
		local player = Players:GetPlayerByUserId(entry.id)
		if player then
			LeaderboardService.ReportArcade(player, entry.cash)
		end
	end
	results = run
	table.clear(rematchVotes)
	setPhase("MatchEnd", Config.Arcade.EndSeconds)
end

local function beginMatch()
	mode = "Race"
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
	setPhase("Playing", if mode == "Arcade" then Config.Arcade.StartSeconds else Config.Round.CapSeconds)
	VehicleService.SetReleased(true)
	FareService.SetEnabled(true)
	ItemService.SetEnabled(true)
end

local function endRound()
	if phase ~= "Playing" then
		return
	end
	if mode == "Arcade" then
		endArcade()
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
		ProgressionService.AwardLicense(results :: { Types.PodiumEntry })
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
	BotService.RemoveAll()
	setPhase("Waiting", 0)
end

function RoundService.ForceEnd()
	endRound()
end

function RoundService.Init()
	roundState = Remotes.Get("RoundState")

	FareService.OnQuotaReached:Connect(function()
		if mode == "Race" then
			endRound()
		end
	end)
	FareService.OnClaimed:Connect(function(_player: Player, tier: string)
		addTime(Config.Arcade.PickupSeconds[tier] or 0)
	end)
	FareService.OnGraded:Connect(function(_player: Player, grade: string)
		addTime(Config.Arcade.GradeSeconds[grade] or 0)
	end)

	-- Arcade: a reserved server someone was sent to runs it for good.
	Players.PlayerAdded:Connect(function(player: Player)
		local ok, data = pcall(function()
			return player:GetJoinData()
		end)
		local joined = if ok and typeof(data) == "table" then (data :: any).TeleportData else nil
		if typeof(joined) == "table" and (joined :: any).mode == "Arcade" and game.PrivateServerId ~= "" then
			arcadeServer = true
			local from = (joined :: any).from
			if typeof(from) == "string" and from ~= "" then
				returnTo[player] = from
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		returnTo[player] = nil
		retried[player] = nil
	end)
	-- Back from Arcade: the server you came from may be gone or full; then any server will do.
	game:GetService("TeleportService").TeleportInitFailed:Connect(function(player: Player, _result: any, message: string)
		if not arcadeServer or retried[player] or not returnTo[player] then
			return
		end
		retried[player] = true
		warn("[RoundService] return teleport failed, any server instead: " .. tostring(message))
		pcall(function()
			local options = Instance.new("TeleportOptions")
			options:SetTeleportData({ streak = SessionService.GetStreak(player) })
			game:GetService("TeleportService"):TeleportAsync(game.PlaceId, { player }, options)
		end)
	end)
	Remotes.Get("ArcadeRequest").OnServerEvent:Connect(function(player: Player, action: any)
		if not RateLimiter.Allow(player, "ArcadeRequest", Config.Net.RateLimits.ArcadeRequest) then
			return
		end
		if phase ~= "Waiting" and phase ~= "PreCountdown" and phase ~= "MatchEnd" then
			return -- only between matches
		end
		local TeleportService = game:GetService("TeleportService")
		if action == "start" and mode ~= "Arcade" then
			if RunService:IsStudio() then
				beginArcadeRun()
			else
				local sent, err = pcall(function()
					local code = TeleportService:ReserveServer(game.PlaceId)
					local data = { mode = "Arcade", from = game.JobId, streak = SessionService.GetStreak(player) }
					TeleportService:TeleportToPrivateServer(game.PlaceId, code, { player }, nil, data)
				end)
				if not sent then
					warn("[RoundService] Arcade teleport failed: " .. tostring(err))
				end
			end
		elseif action == "leave" and mode == "Arcade" then
			if RunService:IsStudio() or not arcadeServer then
				beginMatch()
			else
				pcall(function()
					local options = Instance.new("TeleportOptions")
					local from = returnTo[player]
					if from then
						options.ServerInstanceId = from
					end
					options:SetTeleportData({ streak = SessionService.GetStreak(player) })
					TeleportService:TeleportAsync(game.PlaceId, { player }, options)
				end)
			end
		end
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
			if mode == "Arcade" then
				beginArcadeRun()
			else
				beginMatch()
			end
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
	if RunService:IsStudio() or arcadeServer then
		return Config.Round.StudioMinPlayers
	end
	-- with bots filling the empty seats, one person is enough for a match
	return if Config.Bots.Enabled then math.min(Config.Bots.MinHumans, Config.Round.MinPlayers) else Config.Round.MinPlayers
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
					if arcadeServer then
						beginArcadeRun()
					else
						beginMatch()
					end
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
					if mode == "Arcade" then
						beginArcadeRun()
					else
						beginMatch()
					end
				else
					beginWaiting()
				end
			end
		end
	end)
end

return RoundService
