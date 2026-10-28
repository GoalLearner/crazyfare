--!strict
-- Who drives, rides or waits, match to match (owner spec 2026-10-27, lobby flow v1). The only code that changes a
-- person's SessionService state; RoundService runs the clock and calls in at each phase.
--
-- Joining: you start on the title screen (Title: no seat, counted nowhere); PLAY places you. Between matches
-- (Waiting, MatchEnd) that's the Taxi Depot. During a round with a free seat you drive at
-- once, a little behind last place (Config.Join.LateJoinPenalty) and in a bot's seat. With every seat taken by people
-- you ride along on foot (Passenger) until one opens. During RoundEnd or the Pit Stop you're Queued: walking now,
-- driving at the next round start. A seat that opens mid-round goes to the next person in SessionService.SeatOrder,
-- once any ride they're on has finished.
-- Between matches everyone who played is ready again (STAY IN DEPOT opts out); people take seats first, bots fill.
--
-- The upgrade seam (docs/SCALING.md): MatchStart(drivers, options) and MatchEnd(results) are what a lobby/queue
-- server would drive with a TeleportData roster (SessionService reads it into the seat order today).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local Racers = require(script.Parent.Parent.Racers)
local SessionService = require(script.Parent.SessionService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local BotService = require(script.Parent.BotService)
local GemService = require(script.Parent.GemService)
local ProgressionService = require(script.Parent.ProgressionService)
local QuestService = require(script.Parent.QuestService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local DropService = require(script.Parent.DropService)

export type MatchOptions = { mode: string } -- "Race" | "Arcade"

local MatchController = {}

local onSlotsChanged: Signal.Signal<nil> = Signal.new()
MatchController.OnSlotsChanged = onSlotsChanged -- the next match's line-up changed (the depot board redraws)

local phase = "Waiting" -- RoundService's phase (a plain string: the old solver mis-refines the union)
local mode = "Race"

local function banner(player: Player, text: string)
	SessionService.OnNotice:Fire(player, text)
end

local function isRiding(player: Player): boolean
	return player:GetAttribute("RidingWith") ~= nil
end

local function racing(): boolean
	return phase == "PreCountdown" or phase == "Countdown" or phase == "Playing"
end

local function freeSeats(): number
	return SessionService.MaxDrivers() - SessionService.CountDrivers()
end

-- Seats a newcomer may take: not driven, not promised to someone Queued, not held for a waiting passenger who is
-- finishing a ride (they were here first).
local function openSeats(): number
	local n = freeSeats()
	for _, player in Players:GetPlayers() do
		local state = SessionService.GetState(player)
		if state == "Queued" or (state == "Passenger" and isRiding(player)) then
			n -= 1
		end
	end
	return n
end

-- A late driver starts LateJoinPenalty behind last place this round (and on the match total), never below zero.
local function catchUp(player: Player)
	local lastRound, lastMatch = math.huge, math.huge
	for _, other in Racers.All() do
		if other ~= player then
			lastRound = math.min(lastRound, FareService.GetRoundEarned(other))
			lastMatch = math.min(lastMatch, FareService.GetMatchEarned(other))
		end
	end
	local penalty = Money.Cents(Config.Join.LateJoinPenalty)
	local roundStart = if lastRound == math.huge then 0 else math.max(0, lastRound - penalty)
	local matchStart = if lastMatch == math.huge then 0 else math.max(0, lastMatch - penalty)
	FareService.StartDriver(player, roundStart, math.max(roundStart, matchStart))
end

-- Into a seat now (mid-round or between rounds): car on a free pad, money caught up, a bot gives up its seat.
local function seat(player: Player, line: string)
	SessionService.SetState(player, "Driver")
	catchUp(player)
	BotService.Rebalance(true)
	banner(player, line)
end

-- The next people waiting for a seat (Passenger or Queued, by seat order) take any free ones. Mid-round they drive at
-- once; in RoundEnd or the Pit Stop they're Queued for the next round. Someone mid-ride finishes the ride first.
local function fillSeats()
	if mode ~= "Race" or phase == "Waiting" or phase == "MatchEnd" then
		return
	end
	local waiting: { Player } = {}
	for _, player in Players:GetPlayers() do
		local state = SessionService.GetState(player)
		if state == "Passenger" or (state == "Queued" and racing()) then
			table.insert(waiting, player)
		end
	end
	local seats = if racing() then freeSeats() else openSeats()
	for _, player in SessionService.SeatOrder(waiting) do
		if seats <= 0 then
			break
		end
		if isRiding(player) then
			continue -- the ride ends first; PassengerService.OnUnloaded brings us back here
		end
		seats -= 1
		if racing() then
			seat(player, Config.Join.SeatOpened)
		else
			SessionService.SetState(player, "Queued")
			banner(player, Config.Join.Queued)
		end
	end
	-- Queued people hold seats for the next round; once they're counted, nobody else is promised one.
end

-- The next match's people (seat order, up to the seats); bots fill the rest at round setup.
function MatchController.PickRoster(): { Player }
	local roster: { Player } = {}
	for _, player in SessionService.SeatOrder(Players:GetPlayers()) do
		if #roster >= SessionService.MaxDrivers() then
			break
		end
		table.insert(roster, player)
	end
	return roster
end

-- The depot board's line-up: who would drive if the next match started now, people first, then the bots.
function MatchController.Slots(): { Types.SlotEntry }
	local slots: { Types.SlotEntry } = {}
	local roster = MatchController.PickRoster()
	for _, player in roster do
		table.insert(slots, { name = player.DisplayName, id = player.UserId })
	end
	if mode == "Race" then
		for i = 1, BotService.WantedFor(#roster) do
			table.insert(slots, { name = Config.Bots.Names[(i - 1) % #Config.Bots.Names + 1], id = Config.Bots.IdBase - i, bot = true })
		end
	end
	return slots
end

-- A match begins with these people driving (MatchController.PickRoster, or a lobby's roster later). Everyone else who
-- wants to play rides along on foot; whoever chose the depot stays there. Bots fill seats at round setup.
function MatchController.MatchStart(drivers: { Player }, options: MatchOptions)
	mode = options.mode
	local driving: { [Player]: boolean } = {}
	local count = 0
	for _, player in drivers do
		if player.Parent and count < SessionService.MaxDrivers() then
			driving[player] = true
			count += 1
		end
	end
	-- Off the grid first (frees the pads), then onto it; anyone on the title screen stays there
	for _, player in Players:GetPlayers() do
		if not driving[player] and SessionService.GetState(player) ~= "Title" then
			if SessionService.WantsMatch(player) then
				SessionService.SetState(player, "Passenger")
				banner(player, Config.Join.Rider)
			else
				SessionService.SetState(player, "Depot")
			end
		end
	end
	for player in driving do
		SessionService.SetState(player, "Driver")
	end
end

-- Round 2 and 3 setup (after the passengers were cleared, so nobody is mid-ride): Queued people take their seats, then
-- passengers fill any left. Returns the new drivers; RoundService catches their money up after the round reset.
function MatchController.PromoteForRound(): { Player }
	local promoted: { Player } = {}
	local queued: { Player } = {}
	local riders: { Player } = {}
	for _, player in Players:GetPlayers() do
		local state = SessionService.GetState(player)
		if state == "Queued" then
			table.insert(queued, player)
		elseif state == "Passenger" then
			table.insert(riders, player)
		end
	end
	for _, list in { SessionService.SeatOrder(queued), SessionService.SeatOrder(riders) } do
		for _, player in list do
			if freeSeats() <= 0 then
				break
			end
			SessionService.SetState(player, "Driver")
			banner(player, Config.Join.NextRound)
			table.insert(promoted, player)
		end
	end
	-- Queued people who still have no seat (it filled up) walk on as passengers
	for _, player in queued do
		if SessionService.GetState(player) == "Queued" then
			SessionService.SetState(player, "Passenger")
		end
	end
	return promoted
end

function MatchController.CatchUp(players: { Player })
	for _, player in players do
		if player.Parent and SessionService.IsDriver(player) then
			catchUp(player)
		end
	end
end

-- The last round ended: awards (Gems, XP, license, quests, the weekly board), then everyone who played is ready for
-- the next match. Returns the results with the awards filled in.
function MatchController.MatchEnd(results: { Types.PodiumEntry }): { Types.PodiumEntry }
	local awarded = GemService.AwardMatch(results)
	ProgressionService.AwardMatch(awarded)
	ProgressionService.AwardLicense(awarded)
	QuestService.OnMatchEnd(awarded)
	for _, entry in awarded do
		local player = Players:GetPlayerByUserId(entry.id)
		if player then
			LeaderboardService.AddWeeklyGems(player, entry.gems or 0)
		end
	end
	DropService.AwardMatch(awarded) -- a free crate each, by place (bots get none)
	SessionService.ReadyAll()
	onSlotsChanged:Fire()
	return awarded
end

-- No match running (Waiting): everyone to the depot.
function MatchController.AllToDepot()
	mode = "Race"
	for _, player in Players:GetPlayers() do
		if SessionService.GetState(player) ~= "Title" then
			SessionService.SetState(player, "Depot")
		end
	end
end

-- Someone holds a seat for the next round (RoundEnd / Pit Stop), so the match goes on even with no driver right now.
function MatchController.HasQueued(): boolean
	for _, player in Players:GetPlayers() do
		if SessionService.GetState(player) == "Queued" then
			return true
		end
	end
	return false
end

-- People who want the next match (MinPlayers counts these).
function MatchController.CountReady(): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if SessionService.GetState(player) ~= "Title" and SessionService.WantsMatch(player) then
			n += 1
		end
	end
	return n
end

-- RoundService tells us every phase change.
function MatchController.SetPhase(newPhase: string)
	phase = newPhase
	if racing() then
		fillSeats()
	end
end

-- Someone arrived (or tapped JOIN in the depot mid-match): where do they go?
local function place(player: Player)
	if phase == "Waiting" or phase == "MatchEnd" or not SessionService.WantsMatch(player) then
		SessionService.SetState(player, "Depot")
	elseif openSeats() > 0 and (mode == "Arcade" or racing()) then
		seat(player, Config.Join.Driver)
	elseif openSeats() > 0 then
		SessionService.SetState(player, "Queued") -- RoundEnd or the Pit Stop: the next round's seat is theirs
		banner(player, Config.Join.Queued)
	else
		SessionService.SetState(player, "Passenger")
		banner(player, Config.Join.Rider)
	end
	onSlotsChanged:Fire()
end

-- Just arrived: the title screen, unless they came by teleport from our own servers (or Studio skips it).
local function enter(player: Player)
	if SessionService.SkipsTitle(player) then
		place(player)
	else
		SessionService.SetState(player, "Title")
	end
end

function MatchController.Init()
	Players.PlayerAdded:Connect(function(player: Player)
		task.defer(enter, player) -- after SessionService has read their join data
	end)
	-- PLAY on the title screen: the same join rules as arriving now.
	Remotes.Get("Play").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "Play", Config.Net.RateLimits.Play) then
			return
		end
		if SessionService.GetState(player) == "Title" then
			place(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local was = player:GetAttribute("SessionState")
		task.defer(function()
			if was == "Driver" then
				fillSeats()
			end
			onSlotsChanged:Fire()
		end)
	end)
	-- Studio: the seat cap moved; waiting people take any new seats like any that open.
	SessionService.OnSeatsChanged:Connect(function()
		fillSeats()
		onSlotsChanged:Fire()
	end)
	-- A ride just ended: its rider may be next in line for a seat.
	PassengerService.OnUnloaded:Connect(function(_driver: Player, npc: PassengerService.Npc)
		if npc.rider and racing() and freeSeats() > 0 then
			task.defer(fillSeats)
		end
	end)

	-- DepotChoice("stay" | "join"): sit the next match out (or come back), from the depot or the podium.
	Remotes.Get("DepotChoice").OnServerEvent:Connect(function(player: Player, choice: any)
		if not RateLimiter.Allow(player, "DepotChoice", Config.Net.RateLimits.DepotChoice) then
			return
		end
		if choice ~= "stay" and choice ~= "join" then
			return
		end
		local state = SessionService.GetState(player)
		if state == "Title" then
			return -- PLAY first
		end
		if choice == "stay" then
			if state == "Driver" and phase ~= "MatchEnd" then
				return -- mid-match drivers finish the match
			end
			SessionService.SetStayInDepot(player, true)
			if (state == "Passenger" or state == "Queued") and not isRiding(player) then
				SessionService.SetState(player, "Depot")
			end
		else
			SessionService.SetStayInDepot(player, false)
			if state == "Depot" and phase ~= "Waiting" and phase ~= "MatchEnd" then
				place(player)
			end
		end
		onSlotsChanged:Fire()
	end)
end

function MatchController.Start()
	for _, player in Players:GetPlayers() do
		if SessionService.GetState(player) == "" then
			enter(player)
		end
	end
end

return MatchController
