--!strict
-- Gems: the persistent currency, stored in the player's profile (DataService).
-- Awarded only at match end (placement + fares delivered). Never spendable mid-match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

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
	for i, entry in results do
		local byPlace = if contested then placement[math.min(i, #placement)] or 0 else 0
		local gems = byPlace + entry.fares * Config.Gems.PerFare
		local player = Players:GetPlayerByUserId(entry.id) -- nil for a bot: bots take places but earn nothing
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
