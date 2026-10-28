--!strict
-- What the Robux upgrades do (Config.Monetization.Boosts), registered with MonetizationService, which calls them once
-- Roblox confirms a purchase. Max Upgrades raises every upgrade to the top through DataService; when there's nothing
-- left to raise it pays its FallbackGems instead, so a purchase always gives something.
-- (The in-match boosts were cut 2026-10-28: the owner wants no temporary upgrades.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local SessionService = require(script.Parent.SessionService)

local StoreService = {}

local cfg = Config.Monetization

local function applied(player: Player, key: string)
	SessionService.OnNotice:Fire(player, string.format(cfg.BoughtLine, cfg.Boosts[key].Label))
end

local function fallback(player: Player, key: string)
	local def = cfg.Boosts[key]
	DataService.AddGems(player, def.FallbackGems, "IAP", key)
	SessionService.OnNotice:Fire(player, string.format(cfg.FallbackLine, def.Label, def.FallbackGems))
end

local handlers: { [string]: (Player) -> boolean } = {
	MaxUpgrades = function(player: Player): boolean
		local top = 0
		for _, name in Config.Upgrades.Order do
			top = math.max(top, Config.Upgrades[name].Max)
		end
		return DataService.RaiseUpgrades(player, top)
	end,
}

function StoreService.Init()
	for key, handler in handlers do
		MonetizationService.SetBoostHandler(key, function(player: Player)
			if handler(player) then
				applied(player, key)
			else
				fallback(player, key)
			end
		end)
	end
end

function StoreService.Start() end

return StoreService
