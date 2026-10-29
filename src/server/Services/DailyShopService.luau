--!strict
-- The daily rotating shop (Config.DailyShop, Shared/DailyShop): DailyBuy(id) buys one of today's cosmetics for Gems,
-- handed over like any prize (DropService.GrantPrize). Dropped when it isn't for sale today, is already yours, or you
-- can't afford it (a warning in Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyShop = require(ReplicatedStorage.Shared.DailyShop)
local Prizes = require(ReplicatedStorage.Shared.Prizes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local DropService = require(script.Parent.DropService)
local SessionService = require(script.Parent.SessionService)

local DailyShopService = {}

local isStudio = RunService:IsStudio()

local function refuse(player: Player, id: string, why: string)
	if isStudio then
		warn(string.format("[DailyShopService] %s can't buy %s: %s", player.Name, id, why))
	end
end

local function buy(player: Player, id: string)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local item = DailyShop.Find(DailyShop.Day(workspace:GetServerTimeNow()), id)
	if not item then
		refuse(player, id, "not for sale today")
		return
	end
	local owned = d.Inventory[item.Kind .. "s"]
	if owned ~= nil and (owned[item.Ref or ""] or 0) > 0 then
		refuse(player, id, "already owned")
		return
	end
	local price = DailyShop.Price(item)
	if not DataService.SpendGems(player, price, "Daily:" .. item.Id) then
		refuse(player, id, "not enough Gems")
		return
	end
	DropService.GrantPrize(player, item, "Daily")
	DataService.Sync(player)
	SessionService.OnNotice:Fire(player, string.format(Config.DailyShop.BoughtLine, Prizes.Name(item)))
	if isStudio then
		print(string.format("[DailyShopService] %s bought %s for %d Gems", player.Name, item.Id, price))
	end
end

function DailyShopService.Init()
	Remotes.Get("DailyBuy").OnServerEvent:Connect(function(player: Player, id: any)
		if not RateLimiter.Allow(player, "DailyBuy", Config.Net.RateLimits.DailyBuy) then
			return
		end
		if typeof(id) == "string" then
			buy(player, id)
		end
	end)
end

function DailyShopService.Start() end

return DailyShopService
