--!strict
-- The daily rotating shop (Config.DailyShop, Shared/DailyShop): DailyBuy(id) buys one of today's cosmetics for Gems,
-- handed over like any prize (DropService.GrantPrize). DailyBuy(id, true) is the Robux path: it remembers the pick
-- while the client opens Roblox's prompt for that rarity's product (Config.Monetization.DailyProducts); the receipt
-- hands the pick over, or its Gem price if it's somehow already yours. Dropped when it isn't for sale today, is already
-- yours, or (Gems) you can't afford it (a warning in Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyShop = require(ReplicatedStorage.Shared.DailyShop)
local Prizes = require(ReplicatedStorage.Shared.Prizes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local DropService = require(script.Parent.DropService)
local MonetizationService = require(script.Parent.MonetizationService)
local SessionService = require(script.Parent.SessionService)

local DailyShopService = {}

local isStudio = RunService:IsStudio()
local pending: { [Player]: { id: string, day: number } } = {} -- the Robux pick waiting for its receipt

local function refuse(player: Player, id: string, why: string)
	if isStudio then
		warn(string.format("[DailyShopService] %s can't buy %s: %s", player.Name, id, why))
	end
end

local function owns(d: DataService.ProfileData, item: Config.Prize): boolean
	local owned = d.Inventory[item.Kind .. "s"]
	return owned ~= nil and (owned[item.Ref or ""] or 0) > 0
end

local function handOver(player: Player, item: Config.Prize, source: string)
	DropService.GrantPrize(player, item, source)
	DataService.Sync(player)
	SessionService.OnNotice:Fire(player, string.format(Config.DailyShop.BoughtLine, Prizes.Name(item)))
end

local function buy(player: Player, id: string, withRobux: boolean)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local day = DailyShop.Day(workspace:GetServerTimeNow())
	local item = DailyShop.Find(day, id)
	if not item then
		refuse(player, id, "not for sale today")
		return
	end
	if owns(d, item) then
		refuse(player, id, "already owned")
		return
	end
	if withRobux then
		pending[player] = { id = id, day = day } -- the prompt opens next; its receipt hands this over
		return
	end
	local price = DailyShop.Price(item)
	if not DataService.SpendGems(player, price, "Daily:" .. item.Id) then
		refuse(player, id, "not enough Gems")
		return
	end
	handOver(player, item, "Daily")
	if isStudio then
		print(string.format("[DailyShopService] %s bought %s for %d Gems", player.Name, item.Id, price))
	end
end

-- A daily-shop product's receipt: the pick (still the day it was shown, so a purchase across midnight still counts),
-- or that rarity's Gem price when there's no matching pick or it's already owned.
local function onRobuxPurchase(player: Player, rarity: string)
	local d = DataService.Get(player)
	local pick = pending[player]
	pending[player] = nil
	local item = if pick then DailyShop.Find(pick.day, pick.id) else nil
	if d and item and item.Rarity == rarity and not owns(d, item) then
		handOver(player, item, "DailyRobux")
		if isStudio then
			print(string.format("[DailyShopService] %s bought %s for Robux", player.Name, item.Id))
		end
		return
	end
	local gems = Config.DailyShop.Prices[rarity] or 0
	DataService.AddGems(player, gems, "IAP", "DailyFallback")
	SessionService.OnNotice:Fire(player, string.format(Config.DailyShop.FallbackLine, gems))
	if isStudio then
		print(string.format("[DailyShopService] %s paid for a %s daily item with nothing to hand over: +%d Gems", player.Name, rarity, gems))
	end
end

function DailyShopService.Init()
	MonetizationService.SetDailyHandler(onRobuxPurchase)
	Remotes.Get("DailyBuy").OnServerEvent:Connect(function(player: Player, id: any, withRobux: any)
		if not RateLimiter.Allow(player, "DailyBuy", Config.Net.RateLimits.DailyBuy) then
			return
		end
		if typeof(id) == "string" then
			buy(player, id, withRobux == true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

function DailyShopService.Start() end

return DailyShopService
