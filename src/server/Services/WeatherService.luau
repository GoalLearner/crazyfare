--!strict
-- Per-round weather (Config.Chaos.Weather): RoundService rolls one at every race round's setup and goes back to Clear
-- for Arcade and between matches. The server owns the sky, so everyone (late joiners too) sees the same: Lighting's
-- clock and brightness, the Atmosphere's fog, and a WeatherTint color correction. The rules ride along: fares (Night
-- pays more), traffic speed, bot speed. Each client adds the rain or snow around its camera and the grip change.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local MapService = require(script.Parent.MapService)
local FareService = require(script.Parent.FareService)
local TrafficService = require(script.Parent.TrafficService)
local BotService = require(script.Parent.BotService)

local WeatherService = {}

local onChanged: Signal.Signal<nil> = Signal.new()
WeatherService.OnChanged = onChanged -- the weather changed outside a round setup (Studio debug): RoundService tells everyone

local current = "Clear"
local rng = Random.new()
local atmosphere: Atmosphere
local tint: ColorCorrectionEffect
local base = { brightness = 2, density = 0.3, haze = 0 } -- the place's own sky, captured at boot

local function find(id: string): Config.WeatherDef?
	for _, def in Config.Chaos.Weather.List do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function apply(def: Config.WeatherDef)
	current = def.Id
	local mapCfg = (Config.Map :: any)[MapService.GetCurrentMap()]
	local mapClock = if typeof(mapCfg) == "table" and typeof(mapCfg.ClockTime) == "number" then mapCfg.ClockTime else Lighting.ClockTime
	Lighting.ClockTime = if def.ClockTime >= 0 then def.ClockTime else mapClock
	Lighting.Brightness = base.brightness * def.Brightness
	atmosphere.Density = if def.FogDensity >= 0 then def.FogDensity else base.density
	atmosphere.Haze = if def.Haze >= 0 then def.Haze else base.haze
	tint.TintColor = def.Tint
	tint.Saturation = def.Saturation
	FareService.SetWeatherPay(def.PayMult, if def.PayLine ~= "" then def.PayLine else nil)
	TrafficService.SetSpeedMult(def.TrafficSpeedMult)
	BotService.SetSpeedMult(def.BotSpeedMult)
end

-- The weather right now (Config.Chaos.Weather.List Id).
function WeatherService.Get(): string
	return current
end

function WeatherService.Set(id: string)
	local def = find(id) or find("Clear")
	if def then
		apply(def)
	end
end

-- A new race round: one weather by Weight among those this map allows (Maps nil = any map).
function WeatherService.Roll()
	local map = MapService.GetCurrentMap()
	local pool: { Config.WeatherDef } = {}
	local total = 0
	for _, def in Config.Chaos.Weather.List do
		local maps = def.Maps
		if not maps or maps[map] then
			table.insert(pool, def)
			total += def.Weight
		end
	end
	local pick = rng:NextNumber() * total
	for _, def in pool do
		pick -= def.Weight
		if pick <= 0 then
			apply(def)
			return
		end
	end
	WeatherService.Set("Clear")
end

-- Studio: the next weather in the list, right now.
function WeatherService.DebugNext()
	if not RunService:IsStudio() then
		return
	end
	local list = Config.Chaos.Weather.List
	local index = 0
	for i, def in list do
		if def.Id == current then
			index = i
		end
	end
	apply(list[index % #list + 1])
	onChanged:Fire()
end

function WeatherService.Init()
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing
	else
		local made = Instance.new("Atmosphere")
		made.Parent = Lighting
		atmosphere = made
	end
	base.brightness = Lighting.Brightness
	base.density = atmosphere.Density
	base.haze = atmosphere.Haze
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WeatherTint"
	cc.Parent = Lighting
	tint = cc
	WeatherService.Set("Clear")
end

function WeatherService.Start() end

return WeatherService
