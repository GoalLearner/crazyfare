--!strict
-- Robux: dev products (Gem packs, the Starter Pack, premium cars, in-match boosts) through ProcessReceipt with
-- receipt-id idempotency, and game passes checked on join and after a prompt (each owned pass is also a Pass_<Key>
-- attribute on the player, which the client's driving code reads). Pay-to-win by owner decision (2026-10-27): what's
-- sold here changes matches. Boosts are applied by StoreService, which registers a handler per boost (it sits above the
-- services a boost touches; this service stays low so they can ask it about passes).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local onVehicleGranted: Signal.Signal<Player, string> = Signal.new()
MonetizationService.OnVehicleGranted = onVehicleGranted -- (player, vehicleId) a Robux car product was granted

local passes: { [Player]: { [string]: boolean } } = {}
local debugPasses: { [Player]: { [string]: boolean } } = {} -- Studio: passes granted by the Debug remote
local starterDismissed: { [Player]: boolean } = {}
local boostHandlers: { [string]: (Player) -> () } = {}

local function setPasses(player: Player, owned: { [string]: boolean })
	passes[player] = owned
	for key in Config.Monetization.GamePasses do
		player:SetAttribute("Pass_" .. key, owned[key] == true)
	end
	player:SetAttribute("VIP", owned.VIP == true)
	DataService.Sync(player)
end

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
		local granted = debugPasses[player]
		if granted and granted[key] then
			owned[key] = true
		end
	end
	if player.Parent then
		setPasses(player, owned)
	end
end

-- Does this player own the pass (Config.Monetization.GamePasses key)? Bots never do.
function MonetizationService.HasPass(player: Player, key: string): boolean
	local owned = passes[player]
	return owned ~= nil and owned[key] == true
end

function MonetizationService.IsVip(player: Player): boolean
	return MonetizationService.HasPass(player, "VIP")
end

function MonetizationService.HasPitStopPlus(player: Player): boolean
	return MonetizationService.HasPass(player, "PitStopPlus")
end

function MonetizationService.GetPasses(player: Player): { [string]: boolean }
	return passes[player] or {}
end

function MonetizationService.ShowStarterPack(player: Player): boolean
	local d = DataService.Get(player)
	if not d or starterDismissed[player] then
		return false
	end
	local pack = Config.Monetization.Products.StarterPack
	local live = pack.Id > 0 or RunService:IsStudio()
	return live and not d.StarterPackBought and d.Sessions <= Config.Monetization.StarterPackSessions
end

-- StoreService: what a boost does when it's bought (it always gives something: the boost, or Gems instead).
function MonetizationService.SetBoostHandler(key: string, handler: (Player) -> ())
	boostHandlers[key] = handler
end

-- Everything a product key gives. False for an unknown key (or a boost nobody handles yet).
local function grantKey(player: Player, key: string): boolean
	local d = DataService.Get(player)
	if not d then
		return false
	end
	local product = Config.Monetization.Products[key]
	if product then
		DataService.AddGems(player, product.Gems, "IAP", key)
		if product.Vehicle then
			d.OwnedVehicles[product.Vehicle] = true
		end
		if product.UpgradeLevel then
			DataService.RaiseUpgrades(player, product.UpgradeLevel)
		end
		if key == "StarterPack" then
			d.StarterPackBought = true
		end
		return true
	end
	if Config.Monetization.VehicleProducts[key] ~= nil and Config.Vehicles.Stats[key] then
		d.OwnedVehicles[key] = true
		onVehicleGranted:Fire(player, key)
		return true
	end
	if Config.Monetization.Boosts[key] then
		local handler = boostHandlers[key]
		if not handler then
			return false
		end
		handler(player)
		return true
	end
	return false
end

-- The key behind a Roblox product id ("" when none matches).
local function keyFor(productId: number): string
	if productId <= 0 then
		return ""
	end
	for key, def in Config.Monetization.Products do
		if def.Id == productId then
			return key
		end
	end
	for key, id in Config.Monetization.VehicleProducts do
		if id == productId then
			return key
		end
	end
	for key, def in Config.Monetization.Boosts do
		if def.Id == productId then
			return key
		end
	end
	return ""
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
	local purchase = tostring(receipt.PurchaseId)
	if d.Purchases[purchase] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = keyFor(receipt.ProductId)
	if key == "" or not grantKey(player, key) then
		warn("[Monetization] unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	d.Purchases[purchase] = true
	DataService.Sync(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio only (DebugService): act as if this pass or product was just bought.
function MonetizationService.DebugGrant(player: Player, key: string)
	if not RunService:IsStudio() then
		return
	end
	if Config.Monetization.GamePasses[key] then
		local granted = debugPasses[player] or {}
		granted[key] = true
		debugPasses[player] = granted
		local owned = table.clone(passes[player] or {})
		owned[key] = true
		setPasses(player, owned)
		print("[Monetization] Studio: granted pass " .. key)
	elseif grantKey(player, key) then
		DataService.Sync(player)
		print("[Monetization] Studio: granted product " .. key)
	end
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.SetExtrasProvider(function(player: Player)
		return {
			vip = MonetizationService.IsVip(player),
			pitStopPlus = MonetizationService.HasPitStopPlus(player),
			showStarterPack = MonetizationService.ShowStarterPack(player),
			passes = MonetizationService.GetPasses(player),
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
		debugPasses[player] = nil
		starterDismissed[player] = nil
	end)
end

function MonetizationService.Start() end

return MonetizationService
