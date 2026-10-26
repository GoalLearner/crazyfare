--!strict
-- Dev products (Gem packs, Starter Pack, premium vehicles) through ProcessReceipt with receipt-id idempotency,
-- game passes (VIP, Pit Stop Plus) checked on join and after a prompt, session counting for the Starter Pack offer.
-- Nothing sold here touches passenger HP, item damage, speed or quota.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local passes: { [Player]: { [string]: boolean } } = {}
local starterDismissed: { [Player]: boolean } = {}

local function checkPasses(player: Player)
	local owned: { [string]: boolean } = {}
	for key, def in Config.Monetization.GamePasses do
		if def.Id > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			owned[key] = ok and has == true
		else
			owned[key] = false
		end
	end
	passes[player] = owned
	player:SetAttribute("VIP", owned.VIP == true)
	DataService.Sync(player)
end

function MonetizationService.IsVip(player: Player): boolean
	local owned = passes[player]
	return owned ~= nil and owned.VIP == true
end

function MonetizationService.HasPitStopPlus(player: Player): boolean
	local owned = passes[player]
	return owned ~= nil and owned.PitStopPlus == true
end

function MonetizationService.ShowStarterPack(player: Player): boolean
	local d = DataService.Get(player)
	if not d or starterDismissed[player] then
		return false
	end
	local pack = Config.Monetization.Products.StarterPack
	return pack.Id > 0 and not d.StarterPackBought and d.Sessions <= Config.Monetization.StarterPackSessions
end

local function grant(player: Player, productId: number): boolean
	for key, def in Config.Monetization.Products do
		if def.Id == productId then
			DataService.AddGems(player, def.Gems)
			if def.Vehicle then
				local d = DataService.Get(player)
				if d then
					d.OwnedVehicles[def.Vehicle] = true
				end
			end
			if key == "StarterPack" then
				local d = DataService.Get(player)
				if d then
					d.StarterPackBought = true
				end
			end
			return true
		end
	end
	for vehicleId, id in Config.Monetization.VehicleProducts do
		if id == productId then
			local d = DataService.Get(player)
			if d then
				d.OwnedVehicles[vehicleId] = true
				return true
			end
		end
	end
	return false
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = DataService.Get(player)
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = tostring(receipt.PurchaseId)
	if d.Purchases[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not grant(player, receipt.ProductId) then
		warn("[Monetization] unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	d.Purchases[key] = true
	DataService.Sync(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.SetExtrasProvider(function(player: Player)
		return {
			vip = MonetizationService.IsVip(player),
			pitStopPlus = MonetizationService.HasPitStopPlus(player),
			showStarterPack = MonetizationService.ShowStarterPack(player),
		}
	end)

	DataService.OnLoaded:Connect(function(player: Player)
		local d = DataService.Get(player)
		if d then
			d.Sessions += 1
		end
		task.spawn(checkPasses, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _passId: number, purchased: boolean)
		if purchased then
			task.spawn(checkPasses, player)
		end
	end)

	Remotes.Get("ShopAction").OnServerEvent:Connect(function(player: Player, action: any)
		if not RateLimiter.Allow(player, "ShopAction", Config.Net.RateLimits.ShopAction) then
			return
		end
		if action == "Refresh" then
			task.spawn(checkPasses, player)
		elseif action == "DismissStarter" then
			starterDismissed[player] = true
			DataService.Sync(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		passes[player] = nil
		starterDismissed[player] = nil
	end)
end

function MonetizationService.Start() end

return MonetizationService
