--!strict
-- Sessions: where each person is, and reasons to play the next match and to bring friends (Config.Session).
--
-- State (the single source of truth, also mirrored to the player's SessionState attribute for the client): "Title"
-- (just joined, on the title screen: holds no seat and counts nowhere until PLAY), "Driver"
-- (racing), "Passenger" (every seat taken: walking the city, hailing cabs), "Depot" (between matches, or sitting one
-- out, in the Taxi Depot), "Queued" (a seat is theirs at the next round; walking meanwhile). Only MatchController
-- changes it (SetState); everything that spawns cars, characters or UI listens to OnStateChanged.
-- Seat priority (Config.Join): a TeleportData roster, then a friend-join, then sat out last match, then waited longest.
--
-- Matches in a row pay a streak bonus
-- and a match with a Roblox friend in the server pays a friend bonus (GemService adds both to the match award). Someone
-- new who joins through a friend's invite pays them both once (Roblox's referral system: GetJoinData's
-- ReferredByPlayerId); an inviter who isn't in the server collects on their next join. The streak rides along to an
-- Arcade server and back in the teleport data.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)

local SessionService = {}

local onNotice: Signal.Signal<Player, string> = Signal.new()
SessionService.OnNotice = onNotice -- (player, text) one-shot messages for the HUD
local onStateChanged: Signal.Signal<Player, string, string> = Signal.new()
SessionService.OnStateChanged = onStateChanged -- (player, old state or "" on join, new state)
local onSeatsChanged: Signal.Signal<nil> = Signal.new()
SessionService.OnSeatsChanged = onSeatsChanged -- Studio: the grid's seat cap changed (MatchController fills them)

local states: { [Player]: string } = {}
local joinedAt: { [Player]: number } = {}
local satOut: { [Player]: boolean } = {} -- didn't drive the last match though they were here
local stayInDepot: { [Player]: boolean } = {} -- opted out of the next match
local rosterIds: { [number]: boolean } = {} -- UserIds pre-assigned as drivers (TeleportData.roster)
local debugMaxDrivers = 0 -- Studio: > 0 caps the grid lower, to test a full server with few test players
local skipTitle: { [Player]: boolean } = {} -- arrived by a teleport from our own servers (Arcade and back)

local streaks: { [Player]: number } = {} -- matches finished in a row in this sitting
local friendsHere: { [Player]: { [number]: boolean } } = {} -- UserIds of this player's Roblox friends in the server
local referralStore: DataStore? = nil

local function joinData(player: Player): { [string]: any }
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	return if ok and typeof(data) == "table" then data :: any else {}
end

-- A streak can't claim more matches than the bonus counts (the teleport data comes back through the client).
local function maxStreak(): number
	local s = Config.Session
	return math.ceil(s.StreakMaxGems / s.StreakGems) + 1
end

-- The state of a person here ("" before MatchController placed them).
function SessionService.GetState(player: Player): string
	return states[player] or ""
end

function SessionService.IsDriver(player: Player): boolean
	return states[player] == "Driver"
end

-- MatchController only. Fires OnStateChanged when it changes.
function SessionService.SetState(player: Player, state: Types.SessionState)
	local old = states[player] or ""
	if old == state or not player.Parent then
		return
	end
	states[player] = state
	-- wanting a seat and not getting one (riding along, waiting a round) earns priority for the next match's seats
	if state == "Driver" then
		satOut[player] = nil
	elseif state == "Passenger" or state == "Queued" then
		satOut[player] = true
	end
	player:SetAttribute("SessionState", state)
	onStateChanged:Fire(player, old, state)
end

-- People racing right now.
function SessionService.GetDrivers(): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if states[player] == "Driver" then
			table.insert(list, player)
		end
	end
	return list
end

function SessionService.CountDrivers(): number
	return #SessionService.GetDrivers()
end

-- Seats on the grid. Studio only: the Seats debug button, or a DebugSeats number attribute on workspace (set it in
-- edit mode to start a multi-client test with fewer seats than players), caps it lower. Live servers ignore both.
function SessionService.MaxDrivers(): number
	if RunService:IsStudio() then
		local seats = workspace:GetAttribute("DebugSeats")
		if debugMaxDrivers > 0 then
			return debugMaxDrivers
		elseif typeof(seats) == "number" and seats > 0 then
			return math.min(math.floor(seats), Config.Server.MaxDrivers)
		end
	end
	return Config.Server.MaxDrivers
end

function SessionService.DebugSetMaxDrivers(n: number)
	debugMaxDrivers = math.clamp(math.floor(n), 0, Config.Server.MaxDrivers)
	onSeatsChanged:Fire()
end

function SessionService.WantsMatch(player: Player): boolean
	return not stayInDepot[player]
end

-- Straight past the title screen: back from (or off to) our own Arcade server, or Studio's SkipTitle attribute.
function SessionService.SkipsTitle(player: Player): boolean
	return skipTitle[player] == true or (RunService:IsStudio() and workspace:GetAttribute("SkipTitle") == true)
end

function SessionService.SetStayInDepot(player: Player, stay: boolean)
	if stay then
		stayInDepot[player] = true
	else
		stayInDepot[player] = nil
	end
end

-- After a match: whoever drove, rode or waited is ready for the next one (the depot's own choices stand).
function SessionService.ReadyAll()
	for player in stayInDepot do
		if states[player] ~= "Depot" then
			stayInDepot[player] = nil
		end
	end
end

-- Lower sorts first: who gets the next free seat.
local function priority(player: Player): number
	if rosterIds[player.UserId] then
		return 0
	end
	local follow = player.FollowUserId
	local invitedBy = tonumber(joinData(player).ReferredByPlayerId) or 0
	if (follow ~= 0 and Players:GetPlayerByUserId(follow)) or (invitedBy ~= 0 and Players:GetPlayerByUserId(invitedBy)) then
		return 1
	end
	if satOut[player] then
		return 2
	end
	return 3
end

-- People who want a seat, best claim first (roster, friend, sat out, then longest here). `among` limits it; anyone
-- still on the title screen is left out.
function SessionService.SeatOrder(among: { Player }): { Player }
	local list: { Player } = {}
	for _, player in among do
		if player.Parent and states[player] ~= "Title" and SessionService.WantsMatch(player) then
			table.insert(list, player)
		end
	end
	local keys: { [Player]: number } = {}
	for _, player in list do
		keys[player] = priority(player)
	end
	table.sort(list, function(a: Player, b: Player): boolean
		if keys[a] ~= keys[b] then
			return keys[a] < keys[b]
		end
		local ta, tb = joinedAt[a] or 0, joinedAt[b] or 0
		if ta ~= tb then
			return ta < tb
		end
		return a.UserId < b.UserId
	end)
	return list
end

function SessionService.GetStreak(player: Player): number
	return streaks[player] or 0
end

-- One more match finished in a row; returns the new streak (1 for the first).
function SessionService.CountMatch(player: Player): number
	local streak = math.min((streaks[player] or 0) + 1, maxStreak())
	streaks[player] = streak
	return streak
end

-- Bonus Gems for the match that made this streak.
function SessionService.StreakGems(streak: number): number
	local s = Config.Session
	return math.clamp((streak - 1) * s.StreakGems, 0, s.StreakMaxGems)
end

function SessionService.HasFriendHere(player: Player): boolean
	local set = friendsHere[player]
	if not set then
		return false
	end
	for userId in set do
		if Players:GetPlayerByUserId(userId) then
			return true
		end
	end
	return false
end

local function checkFriends(player: Player)
	local mine: { [number]: boolean } = {}
	friendsHere[player] = mine
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				mine[other.UserId] = true
				local theirs = friendsHere[other]
				if theirs then
					theirs[player.UserId] = true
				end
			end
		end
	end
end

local function payInviter(player: Player, count: number)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local cfg = Config.Session.Referral
	local n = math.min(count, cfg.MaxPerInviter - d.ReferralsPaid)
	if n <= 0 then
		return
	end
	d.ReferralsPaid += n
	d.TotalGemsEarned += n * cfg.InviterGems
	DataService.AddGems(player, n * cfg.InviterGems, "Gameplay", "ReferralInviter")
	onNotice:Fire(player, string.format(cfg.InviterNotice, n * cfg.InviterGems))
end

-- The inviter is paid now if they're here, otherwise the invite waits for them in the DataStore.
local function creditInviter(inviterId: number)
	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and DataService.IsLoaded(inviter) then
		payInviter(inviter, 1)
		return
	end
	local store = referralStore
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync("i_" .. tostring(inviterId), function(old: any)
			return math.min((tonumber(old) or 0) + 1, Config.Session.Referral.MaxPerInviter)
		end)
	end)
	if not ok then
		warn("[SessionService] referral not saved: " .. tostring(err))
	end
end

-- Invites that brought friends in while this player was away.
local function collectWaiting(player: Player)
	local store = referralStore
	if not store then
		return
	end
	local waiting = 0
	local ok = pcall(function()
		store:UpdateAsync("i_" .. tostring(player.UserId), function(old: any)
			waiting = tonumber(old) or 0
			return if waiting > 0 then 0 else nil -- nil: nothing to write
		end)
	end)
	if ok and waiting > 0 then
		payInviter(player, waiting)
	end
end

local function onLoaded(player: Player)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local inviterId = tonumber(joinData(player).ReferredByPlayerId) or 0
	local isNew = d.Sessions <= 1 and (d.Stats.Matches or 0) == 0
	if inviterId > 0 and inviterId ~= player.UserId and d.ReferredBy == 0 and isNew then
		local cfg = Config.Session.Referral
		d.ReferredBy = inviterId
		d.TotalGemsEarned += cfg.InviteeGems
		DataService.AddGems(player, cfg.InviteeGems, "Onboarding", "ReferralInvitee")
		onNotice:Fire(player, string.format(cfg.InviteeNotice, cfg.InviteeGems))
		task.spawn(creditInviter, inviterId)
	end
	task.spawn(collectWaiting, player)
end

function SessionService.Init()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.Session.Referral.Store)
	end)
	referralStore = if ok then store else nil

	Players.PlayerAdded:Connect(function(player: Player)
		joinedAt[player] = os.clock()
		local teleport = joinData(player).TeleportData
		if typeof(teleport) == "table" and ((teleport :: any).streak ~= nil or (teleport :: any).mode ~= nil) then
			skipTitle[player] = true
		end
		if typeof(teleport) == "table" and typeof((teleport :: any).streak) == "number" then
			streaks[player] = math.clamp(math.floor((teleport :: any).streak), 0, maxStreak())
		end
		-- The upgrade seam (docs/SCALING.md): a lobby server would send the match's drivers as a roster of UserIds.
		local roster = if typeof(teleport) == "table" then (teleport :: any).roster else nil
		if typeof(roster) == "table" then
			for _, id in roster :: { any } do
				if typeof(id) == "number" then
					rosterIds[id] = true
				end
			end
		end
		task.spawn(checkFriends, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		streaks[player] = nil
		friendsHere[player] = nil
		states[player] = nil
		joinedAt[player] = nil
		satOut[player] = nil
		stayInDepot[player] = nil
		skipTitle[player] = nil
	end)
	DataService.OnLoaded:Connect(onLoaded)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("DebugSeats"):Connect(function()
			onSeatsChanged:Fire()
		end)
	end
end

function SessionService.Start()
	for _, player in Players:GetPlayers() do
		if not friendsHere[player] then
			task.spawn(checkFriends, player)
		end
	end
end

return SessionService
