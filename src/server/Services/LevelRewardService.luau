--!strict
-- Levels that unlock something (Config.Levels): reaching a level hands over its reward once per account, through the
-- drop grant (a car or horn you already own pays DuplicateGems instead). Accounts already past a level (players from
-- before the rewards existed) get it on their next join. Profile LevelRewardsTo marks how far it has paid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Prizes = require(ReplicatedStorage.Shared.Prizes)
local DataService = require(script.Parent.DataService)
local DropService = require(script.Parent.DropService)
local ProgressionService = require(script.Parent.ProgressionService)
local SessionService = require(script.Parent.SessionService)

local LevelRewardService = {}

local cfg = Config.Levels

type Paid = { reward: Config.LevelReward, duplicateGems: number }

-- Every reward between the last paid level and the current one, then one notice for all of it.
local function payOut(player: Player)
	local d = DataService.Get(player)
	if not d or d.Level <= d.LevelRewardsTo then
		return
	end
	local paid: { Paid } = {}
	for _, reward in cfg.Rewards do
		if reward.Level > d.LevelRewardsTo and reward.Level <= d.Level then
			table.insert(paid, { reward = reward, duplicateGems = DropService.GrantPrize(player, reward, "Level") })
		end
	end
	d.LevelRewardsTo = d.Level
	DataService.Sync(player)
	if #paid == 0 then
		return
	end
	local text = string.format(cfg.CatchUpNotice, #paid)
	if #paid == 1 then
		local one = paid[1]
		local name = Prizes.Name(one.reward)
		text = if one.duplicateGems > 0 then string.format(cfg.DuplicateNotice, one.reward.Level, one.duplicateGems, name) else string.format(cfg.Notice, one.reward.Level, name)
	end
	SessionService.OnNotice:Fire(player, text)
	if RunService:IsStudio() then
		local ids: { string } = {}
		for _, p in paid do
			table.insert(ids, if p.duplicateGems > 0 then string.format("%s (duplicate +%d)", p.reward.Id, p.duplicateGems) else p.reward.Id)
		end
		print(string.format("[LevelRewardService] %s level %d: %s", player.Name, d.Level, table.concat(ids, ", ")))
	end
end

function LevelRewardService.Init()
	ProgressionService.OnLevelUp:Connect(function(player: Player)
		payOut(player)
	end)
	-- older accounts catch up after the streak toast
	DataService.OnLoaded:Connect(function(player: Player)
		task.delay(cfg.CatchUpDelay, payOut, player)
	end)
end

function LevelRewardService.Start() end

return LevelRewardService
