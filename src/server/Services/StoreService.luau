--!strict
-- What the in-match boosts do (Config.Monetization.Boosts), registered with MonetizationService, which calls them once
-- Roblox confirms a purchase. Each goes through the service that owns what it touches: items (ItemService), the boost
-- tank (the client, told by an ItemEvent), passenger HP (PassengerService), round cash (FareService), upgrades
-- (DataService). A boost that can't apply right then (not driving a round, no passenger, already maxed) pays its
-- FallbackGems instead, so a purchase always gives something.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local SessionService = require(script.Parent.SessionService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)

local StoreService = {}

local cfg = Config.Monetization

-- Driving a live round with a car on the road.
local function racing(player: Player): boolean
	return SessionService.IsDriver(player) and VehicleService.GetEntry(player) ~= nil and FareService.IsEnabled()
end

local function applied(player: Player, key: string)
	SessionService.OnNotice:Fire(player, string.format(cfg.BoughtLine, cfg.Boosts[key].Label))
end

local function fallback(player: Player, key: string)
	local def = cfg.Boosts[key]
	DataService.AddGems(player, def.FallbackGems)
	SessionService.OnNotice:Fire(player, string.format(cfg.FallbackLine, def.Label, def.FallbackGems))
end

local handlers: { [string]: (Player) -> boolean } = {
	ItemDrop = function(player: Player): boolean
		if not racing(player) or not ItemService.IsEnabled() then
			return false
		end
		ItemService.GiveExtra(player, ItemService.Roll(player), 1)
		return true
	end,
	TomatoBarrage = function(player: Player): boolean
		if not racing(player) or not ItemService.IsEnabled() then
			return false
		end
		ItemService.GiveExtra(player, "Tomato", cfg.BarrageCount)
		return true
	end,
	NitroRefill = function(player: Player): boolean
		if not racing(player) then
			return false
		end
		Remotes.Get("ItemEvent"):FireClient(player, { kind = "Refill" }) -- the tank lives on the client
		return true
	end,
	PatchUp = function(player: Player): boolean
		local npc = PassengerService.GetLoaded(player)
		if not racing(player) or not npc or npc.hp >= npc.maxHp then
			return false
		end
		PassengerService.SetHp(player, npc.maxHp)
		return true
	end,
	CashBoost = function(player: Player): boolean
		if not racing(player) then
			return false
		end
		local cents = Money.Cents(cfg.CashBoostDollars)
		FareService.AddCash(player, cents)
		Remotes.Get("FareEvent"):FireClient(player, { kind = "Cash", payout = cents })
		return true
	end,
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
