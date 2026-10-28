--!strict
-- Leaderboards on OrderedDataStores: weekly Gems (resets Monday 00:00 UTC), Biggest Tip Ever, Most Passengers
-- Knocked Out, plus a friends view of the weekly board. Falls back to in-memory boards when DataStores are
-- unavailable (Studio without API access). This week's top players get the exclusive trail (attribute WeeklyTrail).
-- The Phantom Owners board: every new owner (a Mythic drop or the Robux offer) gets the next serial number, #1 first;
-- the count of owners is a workspace attribute every client reads (Config.Vehicles.Phantom).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Metrics = require(script.Parent.Parent.Metrics)
local Racers = require(script.Parent.Parent.Racers)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local LeaderboardService = {}

local onPhantomRegistered: Signal.Signal<Player, number> = Signal.new()
LeaderboardService.OnPhantomRegistered = onPhantomRegistered -- (player, serial) a new Phantom owner got their number

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
local serialStore: DataStore? = nil
local memorySerial = 0 -- Studio / no DataStores: serials handed out this server
local lastOwnerCount = 0
local PHANTOM = Config.Vehicles.Phantom

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

local function refreshBoard(board: Board, ascending: boolean?)
	local top: { Types.BoardEntry } = {}
	local store = board.store
	local ok = false
	if store then
		ok = pcall(function()
			local pages = store:GetSortedAsync(ascending == true, Config.Leaderboards.Top)
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
			if ascending then
				return (board.memory[a] or 0) < (board.memory[b] or 0)
			end
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
		arcade = getBoard("arcade", "CF_ArcadeBest").top,
		phantom = getBoard("phantom", PHANTOM.OwnersStore).top,
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
	if tip > 0 and not Racers.IsBot(player) then
		submit(getBoard("bestTip", "CF_BestTip"), player, tip, "max")
	end
end

function LeaderboardService.ReportArcade(player: Player, cents: number)
	if cents > 0 and not Racers.IsBot(player) then
		submit(getBoard("arcade", "CF_ArcadeBest"), player, cents, "max")
	end
end

function LeaderboardService.AddKnockout(player: Player)
	if Racers.IsBot(player) then
		return
	end
	submit(getBoard("knockouts", "CF_Knockouts"), player, 1, "add")
end

local function setOwnerCount(count: number)
	lastOwnerCount = math.max(lastOwnerCount, count)
	workspace:SetAttribute(PHANTOM.CountAttribute, lastOwnerCount)
end

-- The owners so far (the last serial handed out).
local function readOwnerCount()
	local store = serialStore
	if not store then
		setOwnerCount(memorySerial)
		return
	end
	local ok, value = pcall(function()
		return store:GetAsync("count")
	end)
	setOwnerCount(if ok and typeof(value) == "number" then value else memorySerial)
end

-- A new Phantom owner: the next serial, saved on their profile and the board. Does nothing if they already have one.
function LeaderboardService.RegisterPhantom(player: Player)
	local d = DataService.Get(player)
	if not d or d.PhantomSerial > 0 or Racers.IsBot(player) then
		return
	end
	d.PhantomSerial = -1 -- taken while the number is fetched (a second grant can't ask twice)
	task.spawn(function()
		local serial = 0
		local store = serialStore
		if store then
			pcall(function()
				store:UpdateAsync("count", function(old: any)
					serial = (if typeof(old) == "number" then old else 0) + 1
					return serial
				end)
			end)
		end
		if serial <= 0 then
			memorySerial += 1
			serial = memorySerial
		end
		local profile = DataService.Get(player)
		if profile then
			profile.PhantomSerial = serial
			DataService.Sync(player)
		end
		submit(getBoard("phantom", PHANTOM.OwnersStore), player, serial, "max")
		setOwnerCount(serial)
		Metrics.Event(player, Config.Metrics.Events.PhantomOwned, serial)
		onPhantomRegistered:Fire(player, serial)
		if RunService:IsStudio() then
			print(string.format("[LeaderboardService] %s is Phantom owner #%d", player.Name, serial))
		end
	end)
end

-- Owners who got theirs before serials existed (or whose number never saved) get one when they join.
local function checkPhantomOwner(player: Player)
	local d = DataService.Get(player)
	if d and d.OwnedVehicles[Config.Drops.PhantomRef] == true and d.PhantomSerial <= 0 then
		d.PhantomSerial = 0
		LeaderboardService.RegisterPhantom(player)
	end
end

local function refreshAll()
	readOwnerCount()
	refreshBoard(getBoard("phantom", PHANTOM.OwnersStore), true)
	refreshBoard(weeklyBoard())
	refreshBoard(getBoard("bestTip", "CF_BestTip"))
	refreshBoard(getBoard("knockouts", "CF_Knockouts"))
	refreshBoard(getBoard("arcade", "CF_ArcadeBest"))
	applyTrails()
	for _, player in Players:GetPlayers() do
		LeaderboardService.Send(player)
	end
end

function LeaderboardService.Init()
	syncEvent = Remotes.Get("LeaderboardSync")
	-- Studio tests never take a real serial or touch the real owners board
	if RunService:IsStudio() then
		getBoard("phantom", PHANTOM.OwnersStore).store = nil
	else
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(PHANTOM.SerialStore)
		end)
		serialStore = if ok then store else nil
	end
	DataService.OnLoaded:Connect(checkPhantomOwner)
	-- the Robux offer's Phantom
	MonetizationService.OnVehicleGranted:Connect(function(player: Player, vehicleId: string)
		local stats = Config.Vehicles.Stats[vehicleId]
		if stats and stats.Mythic then
			LeaderboardService.RegisterPhantom(player)
		end
	end)
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
	workspace:SetAttribute(PHANTOM.CountAttribute, 0)
	task.spawn(refreshAll)
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastRefresh >= Config.Leaderboards.RefreshSeconds then
			lastRefresh = os.clock()
			task.spawn(refreshAll)
		end
	end)
end

return LeaderboardService
