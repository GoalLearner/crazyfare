--!strict
-- Match state machine:
--   Waiting -> PreCountdown (read the board) -> Countdown -> Playing -> RoundEnd -> PitStop -> PreCountdown ...
--   after the last round: Playing -> MatchEnd (podium, Gems; STAY IN DEPOT opts out) -> PreCountdown of a new match.
-- Who drives is MatchController's: it hears every phase change, picks each match's drivers and seats late joiners.
-- Waiting is the Taxi Depot: its NEXT MATCH countdown runs while enough people want to play.
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
local ProgressionService = require(script.Parent.ProgressionService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local BotService = require(script.Parent.BotService)
local WorldEventService = require(script.Parent.WorldEventService)
local WeatherService = require(script.Parent.WeatherService)
local SessionService = require(script.Parent.SessionService)
local MatchController = require(script.Parent.MatchController)
local DropService = require(script.Parent.DropService)
local Racers = require(script.Parent.Parent.Racers)
local MapVoteService = require(script.Parent.MapVoteService)

local MapService = require(script.Parent.MapService)

local RoundService = {}

local phase: Types.RoundPhase = "Waiting"
local roundIndex = 1
local phaseStartsAt = 0
local phaseEndsAt = 0
local results: { Types.PodiumEntry }? = nil
local waitingSince: number? = nil
local readyPlayers: { [Player]: boolean } = {} -- Pit Stop: who tapped READY
local matchCount = 0
local roundState: RemoteEvent
local mode = "Race" -- "Race" | "Arcade"
local frenzy = false -- the last Config.Chaos.Frenzy.Seconds of a race round
local arcadeServer = false -- a reserved server someone was sent to for Arcade
local returnTo: { [Player]: string } = {} -- Arcade server: the JobId each player came from
local retried: { [Player]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function readyCount(): number
	local n = 0
	for player in readyPlayers do
		if player.Parent then
			n += 1
		end
	end
	return n
end

function RoundService.GetPayload(): Types.RoundStatePayload
	local event, eventEnds, eventPlace = WorldEventService.GetActive()
	local between = phase == "Waiting" or phase == "MatchEnd"
	local since = waitingSince
	return {
		phase = phase,
		round = roundIndex,
		quota = if mode == "Arcade" then 0 else FareService.GetQuota(), -- 0: no quota (the clock ends an Arcade run)
		startsAt = phaseStartsAt,
		-- Waiting: the depot's NEXT MATCH countdown while it runs (0 while too few want to play)
		endsAt = if phase == "Waiting" then (if since then since + Config.Round.AutoStartDelay else 0) else phaseEndsAt,
		results = results,
		map = MapService.GetCurrentMap(),
		ready = if phase == "PitStop" then readyCount() else nil,
		readyOf = if phase == "PitStop" then SessionService.CountDrivers() else nil,
		slots = if between then MatchController.Slots() else nil,
		maxDrivers = SessionService.MaxDrivers(),
		mode = mode,
		frenzy = if frenzy then true else nil,
		event = event,
		eventEndsAt = if event then eventEnds else nil,
		eventAt = eventPlace,
		weather = WeatherService.Get(),
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

-- Frenzy: payouts multiplied, item boxes back fast, one Golden Fare; everyone is told (the RoundState flag).
local function startFrenzy()
	local cfg = Config.Chaos.Frenzy
	frenzy = true
	FareService.SetPayMult(cfg.PayMult)
	ItemService.SetBoxRespawn(cfg.BoxRespawnSeconds)
	PassengerService.SpawnGolden()
end

local function stopFrenzy()
	if not frenzy then
		return
	end
	frenzy = false
	FareService.SetPayMult(1)
	ItemService.SetBoxRespawn(nil)
end

local function setPhase(newPhase: Types.RoundPhase, duration: number)
	if newPhase ~= "Playing" then
		stopFrenzy()
		WorldEventService.Cancel()
	end
	phase = newPhase
	phaseStartsAt = now()
	phaseEndsAt = if duration > 0 then phaseStartsAt + duration else 0
	MatchController.SetPhase(newPhase)
	broadcast()
end

function RoundService.GetPhase(): Types.RoundPhase
	return phase
end

function RoundService.GetRound(): number
	return roundIndex
end

-- Fresh round: riders out of the cabs, waiting people take open seats (rounds 2 and 3), bots fill (or give up) the
-- rest, board, items, cars on the grid, boosts from the Pit Stop applied.
local function beginRoundSetup()
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	PassengerService.ClearAll()
	local promoted = if roundIndex > 1 then MatchController.PromoteForRound() else {}
	BotService.Rebalance()
	FareService.ResetRound()
	MatchController.CatchUp(promoted)
	FareService.SetQuota(Config.Round.Quotas[math.min(roundIndex, #Config.Round.Quotas)])
	ComboService.ResetAll()
	ItemService.ClearAll()
	-- a match's first round: anyone holding a boost token from a drop starts with that item
	if roundIndex == 1 and mode == "Race" then
		for _, player in SessionService.GetDrivers() do
			local item = DropService.TakeStartToken(player)
			if item then
				ItemService.Give(player, item)
			end
		end
	end
	VehicleService.ResetAllToGrid()
	PitStopService.ApplyBoosts()
	PassengerService.EnsureCount(FareService.TargetNpcCount())
	WeatherService.Roll()
	setPhase("PreCountdown", Config.Round.PreCountdownSeconds)
end

-- One Arcade run: no bots, no quota, the City, everyone back on the grid, a fresh board.
local function beginArcadeRun()
	mode = "Arcade"
	roundIndex = 1
	results = nil
	BotService.RemoveAll()
	MatchController.MatchStart(MatchController.PickRoster(), { mode = "Arcade" })
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	FareService.ResetMatch()
	FareService.DisableQuota()
	WeatherService.Set("Clear")
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
	VehicleService.ResetAllToGrid() -- back on the plaza grid, out of the traffic lanes
	local run = FareService.GetResults(true)
	ProgressionService.AwardArcade(run)
	for _, entry in run do
		local player = Players:GetPlayerByUserId(entry.id)
		if player then
			LeaderboardService.ReportArcade(player, entry.cash)
		end
	end
	results = run
	SessionService.ReadyAll()
	setPhase("MatchEnd", Config.Arcade.EndSeconds)
end

local function beginMatch()
	mode = "Race"
	roundIndex = 1
	waitingSince = nil
	-- Map rotation: one match per entry, unless the last podium voted for another map.
	local rotation = Config.Map.Rotation
	local nextMap = MapVoteService.TakeWinner(rotation[(matchCount % #rotation) + 1])
	matchCount += 1
	if nextMap and nextMap ~= MapService.GetCurrentMap() then
		PassengerService.ClearAll()
		ItemService.ClearAll()
		MapService.LoadMap(nextMap)
		ItemService.RefreshBoxes()
		VehicleService.RespawnAll()
	end
	MatchController.MatchStart(MatchController.PickRoster(), { mode = "Race" })
	FareService.ResetMatch()
	beginRoundSetup()
end

local function beginCountdown()
	setPhase("Countdown", Config.Round.CountdownSeconds)
	-- a Mythic car on the grid is everyone's business
	for player, entry in VehicleService.GetAll() do
		local stats = Config.Vehicles.Stats[entry.vehicleId]
		if stats and stats.Mythic and not Racers.IsBot(player) then
			DropService.Banner(Config.Vehicles.Phantom.EnteredBanner)
			break
		end
	end
end

local function beginPlaying()
	setPhase("Playing", if mode == "Arcade" then Config.Arcade.StartSeconds else Config.Round.CapSeconds)
	if mode == "Race" then
		WorldEventService.ScheduleRound()
	end
	VehicleService.SetReleased(true)
	FareService.SetEnabled(true)
	ItemService.SetEnabled(true)
	-- new Weirdo cards' bonus fares, a few seconds in (if this round is still on)
	if mode == "Race" then
		local started = phaseStartsAt
		task.delay(Config.Cosmetics.Bonus.SpawnDelay, function()
			if phase == "Playing" and phaseStartsAt == started then
				DropService.SpawnWeirdos()
			end
		end)
	end
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
	PassengerService.EndRides() -- people riding along step out where their cab is before it goes back to the grid
	VehicleService.ResetAllToGrid() -- back on the plaza grid, out of the traffic lanes
	PitStopService.ClearBoosts()
	local standings = FareService.GetResults(roundIndex >= Config.Round.RoundsPerMatch) -- the last round shows the match total
	if roundIndex < Config.Round.RoundsPerMatch then
		results = standings
		setPhase("RoundEnd", Config.Round.RoundEndSeconds)
	else
		results = MatchController.MatchEnd(standings)
		setPhase("MatchEnd", Config.Round.MatchEndSeconds)
		MapVoteService.Open()
	end
end

local function beginPitStop()
	local closesAt = now() + Config.PitStop.Seconds
	table.clear(readyPlayers)
	PitStopService.Open(roundIndex, closesAt)
	setPhase("PitStop", Config.PitStop.Seconds)
end

-- Someone tapped READY, took it back or left: once every driver here is ready (bots never wait) the Pit Stop clock
-- drops to ReadySeconds (never up), and everyone sees the count.
local function readyChanged()
	if phase ~= "PitStop" then
		return
	end
	local humans = SessionService.CountDrivers()
	if humans > 0 and readyCount() >= humans and phaseEndsAt - now() > Config.PitStop.ReadySeconds then
		phaseEndsAt = now() + Config.PitStop.ReadySeconds
		PitStopService.SetEndsAt(phaseEndsAt)
	end
	broadcast()
end

local function beginWaiting()
	waitingSince = nil
	results = nil
	FareService.SetEnabled(false)
	ItemService.SetEnabled(false)
	VehicleService.ResetAllToGrid() -- back on the plaza grid, out of the traffic lanes
	PitStopService.Close()
	PassengerService.ClearAll()
	BotService.RemoveAll()
	MatchController.AllToDepot()
	MapVoteService.Close() -- a podium's vote doesn't pick the map for a match that starts who knows when
	WeatherService.Set("Clear")
	setPhase("Waiting", 0)
end

function RoundService.ForceEnd()
	endRound()
end

-- Studio: the running round's clock jumps to `seconds` left (to see Frenzy without waiting).
function RoundService.DebugSetClock(seconds: number)
	if RunService:IsStudio() and phase == "Playing" then
		phaseEndsAt = now() + seconds
		broadcast()
	end
end

function RoundService.Init()
	roundState = Remotes.Get("RoundState")
	WeatherService.OnChanged:Connect(function()
		broadcast()
	end)

	WorldEventService.OnChanged:Connect(function()
		broadcast()
	end)
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
		local model = VehicleService.GetModel(player)
		if model then
			Remotes.Get("VehicleAssigned"):FireClient(player, model)
		end
		local item = ItemService.GetHeld(player)
		if item ~= "" then
			Remotes.Get("ItemEvent"):FireClient(player, { kind = "Granted", item = item, count = ItemService.GetSpareCount(player) })
		end
	end)

	-- The depot board's line-up changed (someone arrived, left, or chose to stay or join).
	MatchController.OnSlotsChanged:Connect(function()
		if phase == "Waiting" or phase == "MatchEnd" then
			broadcast()
		end
	end)

	-- PitStopReady(ready): tap READY (or tap again to take it back) during the Pit Stop.
	Remotes.Get("PitStopReady").OnServerEvent:Connect(function(player: Player, ready: any)
		if not RateLimiter.Allow(player, "PitStopReady", Config.Net.RateLimits.PitStopReady) then
			return
		end
		if typeof(ready) ~= "boolean" or phase ~= "PitStop" then
			return
		end
		if ready then
			readyPlayers[player] = true
		else
			readyPlayers[player] = nil
		end
		readyChanged()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		readyPlayers[player] = nil
		task.defer(function()
			-- nobody left driving (and nobody to take a seat): the match is over, back to the depot
			if phase ~= "Waiting" and phase ~= "MatchEnd" and SessionService.CountDrivers() == 0 and not MatchController.HasQueued() then
				beginWaiting()
			else
				readyChanged() -- the one still shopping may have left
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
		local ready = MatchController.CountReady() -- people who want the next match (the depot's STAY opts out)

		if phase == "Waiting" then
			if ready >= minPlayers() then
				local since = waitingSince
				if not since then
					waitingSince = t
					broadcast() -- the depot's NEXT MATCH countdown starts
				elseif t - since >= Config.Round.AutoStartDelay then
					if arcadeServer then
						beginArcadeRun()
					else
						beginMatch()
					end
				end
			elseif waitingSince then
				waitingSince = nil
				broadcast()
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
			elseif mode == "Race" and not frenzy and phaseEndsAt - t <= Config.Chaos.Frenzy.Seconds then
				startFrenzy()
				broadcast()
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
				if ready >= minPlayers() then
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
