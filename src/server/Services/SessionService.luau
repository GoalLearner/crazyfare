--!strict
-- Sessions: reasons to play the next match and to bring friends (Config.Session). Matches in a row pay a streak bonus
-- and a match with a Roblox friend in the server pays a friend bonus (GemService adds both to the match award). Someone
-- new who joins through a friend's invite pays them both once (Roblox's referral system: GetJoinData's
-- ReferredByPlayerId); an inviter who isn't in the server collects on their next join. The streak rides along to an
-- Arcade server and back in the teleport data.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local DataService = require(script.Parent.DataService)

local SessionService = {}

local onNotice: Signal.Signal<Player, string> = Signal.new()
SessionService.OnNotice = onNotice -- (player, text) one-shot messages for the HUD

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
	DataService.AddGems(player, n * cfg.InviterGems)
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
		DataService.AddGems(player, cfg.InviteeGems)
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
		local teleport = joinData(player).TeleportData
		if typeof(teleport) == "table" and typeof((teleport :: any).streak) == "number" then
			streaks[player] = math.clamp(math.floor((teleport :: any).streak), 0, maxStreak())
		end
		task.spawn(checkFriends, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		streaks[player] = nil
		friendsHere[player] = nil
	end)
	DataService.OnLoaded:Connect(onLoaded)
end

function SessionService.Start()
	for _, player in Players:GetPlayers() do
		if not friendsHere[player] then
			task.spawn(checkFriends, player)
		end
	end
end

return SessionService
