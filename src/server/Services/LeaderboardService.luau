--!strict
-- Leaderboards on OrderedDataStores: weekly Gems (resets Monday 00:00 UTC), Biggest Tip Ever, Most Passengers
-- Knocked Out, plus a friends view of the weekly board. Falls back to in-memory boards when DataStores are
-- unavailable (Studio without API access). This week's top players get the exclusive trail (attribute WeeklyTrail).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)

local LeaderboardService = {}

type Board = {
	name: string,
	store: OrderedDataStore?,
	memory: { [number]: number }, -- userId -> value (fallback and local cache)
	top: { Types.BoardEntry },
}

local DAY = 86400
local WEEK = 7 * DAY
local WEEK_OFFSET = 4 * DAY

local boards: { [string]: Board } = {}
local syncEvent: RemoteEvent
local nameCache: { [number]: string } = {}
local friendsCache: { [Player]: { entries: { Types.BoardEntry }, at: number } } = {}
local lastRefresh = 0

local function weekKey(): string
	return "w" .. tostring(math.floor((os.time() - WEEK_OFFSET) / WEEK))
end

local function secondsToWeekReset(): number
	return WEEK - (os.time() - WEEK_OFFSET) % WEEK
end

local function openStore(name: string): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local function getBoard(key: string, storeName: string): Board
	local existing = boards[key]
	if existing and existing.name == storeName then
		return existing
	end
	local board: Board = { name = storeName, store = openStore(storeName), memory = {}, top = {} }
	boards[key] = board
	return board
end

local function weeklyBoard(): Board
	return getBoard("weekly", "CF_Weekly_" .. weekKey())
end

local function displayName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else nil
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok then result else "Player"
	end
	nameCache[userId] = name :: string
	return name :: string
end

-- Writes value for the player; "max" keeps the higher of old and new, "add" accumulates.
local function submit(board: Board, player: Player, value: number, mode: string)
	local current = board.memory[player.UserId] or 0
	local newValue = if mode == "add" then current + value else math.max(current, value)
	board.memory[player.UserId] = newValue
	local store = board.store
	if store then
		task.spawn(function()
			pcall(function()
				store:UpdateAsync(tostring(player.UserId), function(old: any)
					local oldValue = if typeof(old) == "number" then old else 0
					return if mode == "add" then oldValue + value else math.max(oldValue, value)
				end)
			end)
		end)
	end
end

local function refreshBoard(board: Board)
	local top: { Types.BoardEntry } = {}
	local store = board.store
	local ok = false
	if store then
		ok = pcall(function()
			local pages = store:GetSortedAsync(false, Config.Leaderboards.Top)
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.key)
				if id then
					table.insert(top, { id = id, name = displayName(id), value = item.value })
				end
			end
		end)
	end
	if not ok then
		top = {}
		local ids: { number } = {}
		for id in board.memory do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return (board.memory[a] or 0) > (board.memory[b] or 0)
		end)
		for i = 1, math.min(Config.Leaderboards.Top, #ids) do
			table.insert(top, { id = ids[i], name = displayName(ids[i]), value = board.memory[ids[i]] or 0 })
		end
	end
	board.top = top
end

local function applyTrails()
	local weekly = weeklyBoard()
	local winners: { [number]: boolean } = {}
	for i, entry in weekly.top do
		if i <= Config.Leaderboards.WeeklyTrailTop then
			winners[entry.id] = true
		end
	end
	for _, player in Players:GetPlayers() do
		local has = winners[player.UserId] == true
		if (player:GetAttribute("WeeklyTrail") == true) ~= has then
			player:SetAttribute("WeeklyTrail", has)
		end
	end
end

local function friendsFor(player: Player): { Types.BoardEntry }
	local cached = friendsCache[player]
	if cached and os.clock() - cached.at < Config.Leaderboards.RefreshSeconds then
		return cached.entries
	end
	local weekly = weeklyBoard()
	local entries: { Types.BoardEntry } = {}
	-- Everyone in the weekly memory/top who is a friend, plus the player themself.
	local candidates: { [number]: number } = {}
	for _, entry in weekly.top do
		candidates[entry.id] = entry.value
	end
	for id, value in weekly.memory do
		candidates[id] = math.max(candidates[id] or 0, value)
	end
	for id, value in candidates do
		if id == player.UserId then
			table.insert(entries, { id = id, name = player.DisplayName, value = value })
		else
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(id)
			end)
			if ok and isFriend then
				table.insert(entries, { id = id, name = displayName(id), value = value })
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	friendsCache[player] = { entries = entries, at = os.clock() }
	return entries
end

function LeaderboardService.Send(player: Player)
	local payload: Types.LeaderboardPayload = {
		weekly = weeklyBoard().top,
		friends = friendsFor(player),
		bestTip = getBoard("bestTip", "CF_BestTip").top,
		knockouts = getBoard("knockouts", "CF_Knockouts").top,
		weekResetsIn = secondsToWeekReset(),
	}
	syncEvent:FireClient(player, payload)
end

function LeaderboardService.AddWeeklyGems(player: Player, gems: number)
	if gems > 0 then
		submit(weeklyBoard(), player, gems, "add")
	end
end

function LeaderboardService.ReportTip(player: Player, tip: number)
	if tip > 0 then
		submit(getBoard("bestTip", "CF_BestTip"), player, tip, "max")
	end
end

function LeaderboardService.AddKnockout(player: Player)
	submit(getBoard("knockouts", "CF_Knockouts"), player, 1, "add")
end

local function refreshAll()
	refreshBoard(weeklyBoard())
	refreshBoard(getBoard("bestTip", "CF_BestTip"))
	refreshBoard(getBoard("knockouts", "CF_Knockouts"))
	applyTrails()
	for _, player in Players:GetPlayers() do
		LeaderboardService.Send(player)
	end
end

function LeaderboardService.Init()
	syncEvent = Remotes.Get("LeaderboardSync")
	Remotes.Get("RequestLeaderboards").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "RequestLeaderboards", Config.Net.RateLimits.RequestLeaderboards, 2) then
			return
		end
		LeaderboardService.Send(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		friendsCache[player] = nil
	end)
end

function LeaderboardService.Start()
	task.spawn(refreshAll)
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastRefresh >= Config.Leaderboards.RefreshSeconds then
			lastRefresh = os.clock()
			task.spawn(refreshAll)
		end
	end)
end

return LeaderboardService
