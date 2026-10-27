--!strict
-- Gems: the persistent currency, stored in the player's profile (DataService).
-- Awarded only at match end (placement + fares delivered + the session bonuses: a streak of matches, a friend in the
-- server), doubled for VIP and by a live event's multiplier. Never spendable mid-match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Events = require(ReplicatedStorage.Shared.Events)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local SessionService = require(script.Parent.SessionService)

local GemService = {}

function GemService.GetTotal(player: Player): number
	return DataService.GetGems(player)
end

function GemService.Add(player: Player, amount: number)
	DataService.AddGems(player, amount)
end

-- Pays every entry by placement and fares, writes the award into the entry, records match stats.
function GemService.AwardMatch(results: { Types.PodiumEntry }): { Types.PodiumEntry }
	local placement = Config.Gems.Placement
	local contested = #results >= 2 -- no rivals, no placement bonus
	local t = os.time()
	local eventMult = Events.GemMult(t)
	local eventKind = Events.Live(t)
	for i, entry in results do
		local byPlace = if contested then placement[math.min(i, #placement)] or 0 else 0
		local gems = byPlace + entry.fares * Config.Gems.PerFare
		local player = Players:GetPlayerByUserId(entry.id) -- nil for a bot: bots take places but earn nothing
		if player then
			local streak = SessionService.CountMatch(player)
			local streakGems = SessionService.StreakGems(streak)
			local friendGems = if SessionService.HasFriendHere(player) then Config.Session.FriendGems else 0
			gems += streakGems + friendGems
			entry.streak = if streakGems > 0 then streak else nil
			entry.streakGems = if streakGems > 0 then streakGems else nil
			entry.friendGems = if friendGems > 0 then friendGems else nil
			if eventMult > 1 and eventKind then
				gems *= eventMult
				entry.event = eventKind
			end
		end
		if player and MonetizationService.IsVip(player) then
			gems *= Config.Monetization.VipGemMult
		end
		if player then
			entry.gems = gems
			GemService.Add(player, gems)
			local d = DataService.Get(player)
			if d then
				d.TotalGemsEarned += gems
			end
			DataService.AddStat(player, "Matches", 1)
			DataService.AddStat(player, "Fares", entry.fares)
			DataService.SetStatMax(player, "BestTip", entry.bestTip)
			if i == 1 then
				DataService.AddStat(player, "Wins", 1)
			end
		end
	end
	return results
end

function GemService.Init() end

function GemService.Start() end

return GemService
