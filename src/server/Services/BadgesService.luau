--!strict
-- Roblox badges (Config.Badges): first delivery, first win, level 10, a LEGEND license, owning the Phantom. Awarded on
-- the server when it happens, and on join for anything an account already earned (so players who did it before the
-- badges existed get them too). Each is sent once per account (profile BadgesGiven). A badge whose Id is still 0 isn't
-- created in Creator Hub yet: nothing is sent (Studio prints what would have been).

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Racers = require(script.Parent.Parent.Racers)
local DataService = require(script.Parent.DataService)
local FareService = require(script.Parent.FareService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchController = require(script.Parent.MatchController)

local BadgesService = {}

local cfg = Config.Badges

local function award(player: Player, key: string)
	local def = cfg.List[key]
	local d = DataService.Get(player)
	if not def or not d or Racers.IsBot(player) or d.BadgesGiven[key] then
		return
	end
	if def.Id <= 0 or RunService:IsStudio() then
		if RunService:IsStudio() then
			-- Studio tests never award real badges
			print(string.format("[BadgesService] %s earned %s (%s)", player.Name, key, if def.Id > 0 then "Studio: not sent" else "no badge id yet, nothing sent"))
		end
		return
	end
	d.BadgesGiven[key] = true -- taken now so a second trigger can't send it twice
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, def.Id)
		end)
		if not ok then
			warn(string.format("[BadgesService] %s for %s failed: %s", key, player.Name, tostring(err)))
			local profile = DataService.Get(player)
			if profile then
				profile.BadgesGiven[key] = nil -- try again next time it's earned or on the next join
			end
		end
	end)
end

-- Anything this account already earned (on join).
local function catchUp(player: Player)
	local d = DataService.Get(player)
	if not d then
		return
	end
	if (d.Stats.Fares or 0) > 0 then
		award(player, "FirstFare")
	end
	if (d.Stats.Wins or 0) > 0 then
		award(player, "FirstWin")
	end
	if d.Level >= cfg.Level then
		award(player, "Level10")
	end
	if d.BestLicense >= #Config.License.Grades then
		award(player, "LegendLicense")
	end
	if d.OwnedVehicles[Config.Drops.PhantomRef] == true then
		award(player, "PhantomOwner")
	end
end

function BadgesService.Init()
	DataService.OnLoaded:Connect(catchUp)
	FareService.OnDelivered:Connect(function(player: Player)
		award(player, "FirstFare")
	end)
	LeaderboardService.OnPhantomRegistered:Connect(function(player: Player)
		award(player, "PhantomOwner")
	end)
	MatchController.OnMatchEnded:Connect(function(results: { Types.PodiumEntry })
		for place, entry in results do
			local player = Players:GetPlayerByUserId(entry.id)
			if not player then
				continue
			end
			if place == 1 and #results >= 2 then
				award(player, "FirstWin")
			end
			if entry.license == Config.License.Grades[#Config.License.Grades] then
				award(player, "LegendLicense")
			end
			local d = DataService.Get(player)
			if d and d.Level >= cfg.Level then
				award(player, "Level10")
			end
		end
	end)
end

function BadgesService.Start() end

return BadgesService
