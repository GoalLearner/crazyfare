--!strict
-- Persistent player data through ProfileStore. One profile per player, loaded on join, released on leave.
-- Everything persistent (Gems, owned vehicles, selection, paint, upgrades, stats) is read and written here only.
-- In Studio without DataStore access ProfileStore uses an in-memory mock on its own, so tests still work.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore) :: any

export type ProfileData = {
	Gems: number,
	Level: number,
	Xp: number,
	OwnedVehicles: { [string]: boolean },
	SelectedVehicle: string,
	Paint: string,
	Upgrades: { [string]: number },
	Quests: { [string]: any },
	Streak: { Days: number, LastDay: number },
	Stats: { [string]: number },
	Purchases: { [string]: boolean },
	Sessions: number,
	StarterPackBought: boolean,
	TotalGemsEarned: number,
	BestLicense: number,
	ArcadeBest: number,
	ArcadeBestLicense: number,
	CoachDone: boolean,
	ReferredBy: number,
	ReferralsPaid: number,
	Settings: { Music: number, Sfx: number, Shake: boolean, SpeedFx: boolean },
	DropCount: number,
	PityCounter: number,
	Inventory: { [string]: { [string]: number } },
}

local DataService = {}

local onLoaded: Signal.Signal<Player> = Signal.new()
local onVehicleSelected: Signal.Signal<Player> = Signal.new()
DataService.OnLoaded = onLoaded
DataService.OnVehicleSelected = onVehicleSelected -- selection or paint changed; the car may need a respawn

local store = ProfileStore.New(Config.Data.StoreName, Config.Data.Template)
type Extras = { vip: boolean, pitStopPlus: boolean, showStarterPack: boolean, passes: { [string]: boolean } }
local extrasProvider: ((Player) -> Extras)? = nil
local profiles: { [Player]: any } = {}
local syncEvent: RemoteEvent

local function data(player: Player): ProfileData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data :: ProfileData
	end
	return nil
end

function DataService.Get(player: Player): ProfileData?
	return data(player)
end

function DataService.IsLoaded(player: Player): boolean
	return data(player) ~= nil
end

local function applyUpgradeAttributes(player: Player, d: ProfileData)
	for _, name in Config.Upgrades.Order do
		local def = Config.Upgrades[name]
		local level = d.Upgrades[name] or 0
		player:SetAttribute("Up_" .. name, 1 + def.Per * level)
	end
end

-- MonetizationService supplies pass ownership and the Starter Pack flag for the sync payload.
function DataService.SetExtrasProvider(provider: (Player) -> Extras)
	extrasProvider = provider
end

function DataService.Sync(player: Player)
	local d = data(player)
	if not d then
		return
	end
	local extras: Extras = if extrasProvider then extrasProvider(player) else { vip = false, pitStopPlus = false, showStarterPack = false, passes = {} }
	local payload: Types.ProfilePayload = {
		gems = d.Gems,
		level = d.Level,
		xp = d.Xp,
		owned = d.OwnedVehicles,
		selected = d.SelectedVehicle,
		paint = d.Paint,
		upgrades = d.Upgrades,
		stats = d.Stats,
		vip = extras.vip,
		pitStopPlus = extras.pitStopPlus,
		showStarterPack = extras.showStarterPack,
		passes = extras.passes,
		xpToNext = Config.Progression.LevelBaseXp + (d.Level - 1) * Config.Progression.LevelStepXp,
		xpIntoLevel = d.Xp,
		bestLicense = d.BestLicense,
		arcadeBest = d.ArcadeBest,
		arcadeBestLicense = d.ArcadeBestLicense,
		coachDone = d.CoachDone,
		settings = { music = d.Settings.Music, sfx = d.Settings.Sfx, shake = d.Settings.Shake, speedFx = d.Settings.SpeedFx },
		inventory = d.Inventory,
		dropCount = d.DropCount,
		pity = d.PityCounter,
	}
	syncEvent:FireClient(player, payload)
end

function DataService.GetGems(player: Player): number
	local d = data(player)
	return if d then d.Gems else 0
end

function DataService.AddGems(player: Player, amount: number)
	local d = data(player)
	if not d then
		return
	end
	d.Gems = math.max(0, d.Gems + amount)
	DataService.Sync(player)
end

-- Returns false without touching the balance when it cannot afford it.
function DataService.SpendGems(player: Player, amount: number): boolean
	local d = data(player)
	if not d or d.Gems < amount then
		return false
	end
	d.Gems -= amount
	DataService.Sync(player)
	return true
end

function DataService.AddStat(player: Player, name: string, amount: number)
	local d = data(player)
	if d then
		d.Stats[name] = (d.Stats[name] or 0) + amount
	end
end

function DataService.SetStatMax(player: Player, name: string, value: number)
	local d = data(player)
	if d then
		d.Stats[name] = math.max(d.Stats[name] or 0, value)
	end
end

function DataService.GetSelectedVehicle(player: Player): string
	local d = data(player)
	local selected = if d then d.SelectedVehicle else Config.Vehicles.Default
	return if Config.Vehicles.Stats[selected] then selected else Config.Vehicles.Default
end

function DataService.GetPaint(player: Player): Color3?
	local d = data(player)
	if not d or d.Paint == "" then
		return nil
	end
	for _, entry in Config.Paint.Colors do
		if entry.Name == d.Paint then
			return entry.Color
		end
	end
	return nil
end

function DataService.Owns(player: Player, vehicleId: string): boolean
	local stats = Config.Vehicles.Stats[vehicleId]
	if not stats then
		return false
	end
	if stats.GemPrice <= 0 and not stats.RobuxOnly then
		return true
	end
	local d = data(player)
	return d ~= nil and d.OwnedVehicles[vehicleId] == true
end

function DataService.SelectVehicle(player: Player, vehicleId: string): boolean
	local d = data(player)
	if not d or not DataService.Owns(player, vehicleId) or d.SelectedVehicle == vehicleId then
		return false
	end
	d.SelectedVehicle = vehicleId
	DataService.Sync(player)
	onVehicleSelected:Fire(player)
	return true
end

function DataService.BuyVehicle(player: Player, vehicleId: string): boolean
	local stats = Config.Vehicles.Stats[vehicleId]
	local d = data(player)
	if not stats or not d or stats.RobuxOnly or DataService.Owns(player, vehicleId) then
		return false -- Robux-only cars come through MonetizationService
	end
	if not DataService.SpendGems(player, stats.GemPrice) then
		return false
	end
	d.OwnedVehicles[vehicleId] = true
	DataService.Sync(player)
	return true
end

function DataService.BuyUpgrade(player: Player, name: string): boolean
	local def = Config.Upgrades[name]
	local d = data(player)
	if not def or not d or typeof(def) ~= "table" then
		return false
	end
	local level = d.Upgrades[name] or 0
	if level >= def.Max then
		return false
	end
	local cost = def.Costs[level + 1]
	if not cost or not DataService.SpendGems(player, cost) then
		return false
	end
	d.Upgrades[name] = level + 1
	applyUpgradeAttributes(player, d)
	DataService.Sync(player)
	return true
end

-- Every upgrade to at least this level (the Starter Pack, Max Upgrades). False when nothing went up.
function DataService.RaiseUpgrades(player: Player, level: number): boolean
	local d = data(player)
	if not d then
		return false
	end
	local raised = false
	for _, name in Config.Upgrades.Order do
		local def = Config.Upgrades[name]
		local target = math.min(level, def.Max)
		if (d.Upgrades[name] or 0) < target then
			d.Upgrades[name] = target
			raised = true
		end
	end
	if raised then
		applyUpgradeAttributes(player, d)
		DataService.Sync(player)
	end
	return raised
end

function DataService.BuyPaint(player: Player, colorName: string): boolean
	local d = data(player)
	if not d then
		return false
	end
	local found = false
	local dropOnly = false
	for _, entry in Config.Paint.Colors do
		if entry.Name == colorName then
			found = true
			dropOnly = entry.DropOnly == true
			break
		end
	end
	if colorName ~= "" and not found then
		return false
	end
	if d.Paint == colorName then
		return false
	end
	-- a paint won from a drop applies free; drop-only colors can't be bought at all
	local owned = colorName ~= "" and (d.Inventory.Paints[colorName] or 0) > 0
	if colorName ~= "" and not owned and (dropOnly or not DataService.SpendGems(player, Config.Paint.Price)) then
		return false
	end
	d.Paint = colorName
	DataService.Sync(player)
	onVehicleSelected:Fire(player)
	return true
end

local function loadProfile(player: Player)
	local profile = store:StartSessionAsync("p_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	applyUpgradeAttributes(player, profile.Data :: ProfileData)
	DataService.Sync(player)
	onLoaded:Fire(player)
end

function DataService.Init()
	syncEvent = Remotes.Get("ProfileSync")
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadProfile, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		if profile then
			profile:EndSession()
		end
	end)
	Remotes.Get("CoachDone").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "CoachDone", Config.Net.RateLimits.CoachDone) then
			return
		end
		local d = data(player)
		if d and not d.CoachDone then
			d.CoachDone = true
			DataService.Sync(player)
		end
	end)
	-- OPTIONS: two volume steps and two switches, checked and saved (the client has already applied them).
	Remotes.Get("SaveSettings").OnServerEvent:Connect(function(player: Player, settings: any)
		if not RateLimiter.Allow(player, "SaveSettings", Config.Net.RateLimits.SaveSettings, 3) then
			return
		end
		local d = data(player)
		if not d or typeof(settings) ~= "table" then
			return
		end
		local steps = #Config.Options.VolumeSteps
		local music, sfx, shake, speedFx = settings.music, settings.sfx, settings.shake, settings.speedFx
		local function isStep(v: any): boolean
			return typeof(v) == "number" and v == math.floor(v) and v >= 1 and v <= steps
		end
		if not isStep(music) or not isStep(sfx) or typeof(shake) ~= "boolean" or typeof(speedFx) ~= "boolean" then
			return
		end
		d.Settings.Music = music :: number
		d.Settings.Sfx = sfx :: number
		d.Settings.Shake = shake :: boolean
		d.Settings.SpeedFx = speedFx :: boolean
	end)
	Remotes.Get("ClientReady").OnServerEvent:Connect(function(player: Player)
		DataService.Sync(player)
	end)
end

function DataService.Start()
	for _, player in Players:GetPlayers() do
		if not profiles[player] then
			task.spawn(loadProfile, player)
		end
	end
end

return DataService
