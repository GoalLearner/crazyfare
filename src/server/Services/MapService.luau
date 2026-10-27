--!strict
-- Discovers the map by CollectionService tag and answers spatial questions. Nothing is looked up by name.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local DevBlockout = require(script.Parent.Parent.Studio.DevBlockout)
local Lighting = game:GetService("Lighting")

export type Point = {
	index: number,
	position: Vector3,
	cframe: CFrame, -- LookVector faces the road
	part: BasePart,
	name: string, -- drop-offs: the destination name given out by the map build ("THE STADIUM"); "" otherwise
}

local MapService = {}

local onMapLoaded: Signal.Signal<nil> = Signal.new()
MapService.OnMapLoaded = onMapLoaded -- after LoadMap swapped the world (traffic respawns on it)

local pickups: { Point } = {}
local dropoffs: { Point } = {}
local startPads: { Point } = {}
local itemBoxes: { BasePart } = {}
local props: { { part: BasePart, cframe: CFrame } } = {}
local center = Vector3.zero
local currentMap = Config.Map.Current

local function collectPoints(tagName: string): { Point }
	local list: { Point } = {}
	for _, inst in CollectionService:GetTagged(tagName) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local idx = inst:GetAttribute("Index")
			local name = inst:GetAttribute("Destination")
			table.insert(list, {
				index = if typeof(idx) == "number" then idx else #list + 1,
				position = inst.Position,
				cframe = inst.CFrame,
				part = inst,
				name = if typeof(name) == "string" then name else "",
			})
		end
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

function MapService.GetRuntimeFolder(name: string): Folder
	local existing = workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

local function discover()
	pickups = collectPoints(Config.Tags.PickupPoint)
	dropoffs = collectPoints(Config.Tags.DropoffPoint)
	startPads = collectPoints(Config.Tags.StartPad)
	itemBoxes = {}
	for _, inst in CollectionService:GetTagged(Config.Tags.ItemBox) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(itemBoxes, inst)
		end
	end
	props = {}
	for _, inst in CollectionService:GetTagged(Config.Tags.Prop) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(props, { part = inst, cframe = inst.CFrame })
		end
	end
	if #startPads > 0 then
		local sum = Vector3.zero
		for _, pad in startPads do
			sum += pad.position
		end
		center = sum / #startPads
	end
	if #pickups == 0 or #dropoffs == 0 or #startPads == 0 then
		warn(string.format("[MapService] map incomplete: %d pickups, %d dropoffs, %d start pads", #pickups, #dropoffs, #startPads))
	end
end

function MapService.GetCurrentMap(): string
	return currentMap
end

-- The current map's blockout spec: road grid, cell layout.
function MapService.GetBlockout(): typeof(Config.Map.City.Blockout)
	local mapCfg = (Config.Map :: any)[currentMap]
	if typeof(mapCfg) == "table" and mapCfg.Blockout then
		return mapCfg.Blockout
	end
	return Config.Map.City.Blockout
end

-- Replace the world with another map from Config.Map and rediscover its points. Callers respawn cars and clear NPCs.
function MapService.LoadMap(name: string)
	local mapCfg = (Config.Map :: any)[name]
	if typeof(mapCfg) ~= "table" or not mapCfg.Blockout then
		name = Config.Map.Current
		mapCfg = Config.Map.City
	end
	DevBlockout.Generate(name)
	currentMap = name
	if typeof(mapCfg.ClockTime) == "number" then
		Lighting.ClockTime = mapCfg.ClockTime
	end
	discover()
	onMapLoaded:Fire()
end

function MapService.Init()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		local baked = existing:GetAttribute("MapName")
		currentMap = if typeof(baked) == "string" then baked else Config.Map.Current
	end
	discover()
	MapService.GetRuntimeFolder("Vehicles")
	MapService.GetRuntimeFolder("NPCs")
	MapService.GetRuntimeFolder("Items")
end

function MapService.Start() end

function MapService.GetPickups(): { Point }
	return pickups
end

function MapService.GetDropoffs(): { Point }
	return dropoffs
end

function MapService.GetStartPads(): { Point }
	return startPads
end

function MapService.GetItemBoxes(): { BasePart }
	return itemBoxes
end

function MapService.GetCenter(): Vector3
	return center
end

-- Put every tagged prop back where the map placed it (round reset).
function MapService.ResetProps()
	for _, entry in props do
		if entry.part.Parent then
			entry.part.AssemblyLinearVelocity = Vector3.zero
			entry.part.AssemblyAngularVelocity = Vector3.zero
			entry.part.CFrame = entry.cframe
		end
	end
end

function MapService.GetPickup(index: number): Point?
	for _, p in pickups do
		if p.index == index then
			return p
		end
	end
	return nil
end

function MapService.GetDropoff(index: number): Point?
	for _, p in dropoffs do
		if p.index == index then
			return p
		end
	end
	return nil
end

-- Nearest pickup point by flat distance, skipping indices in `exclude` (falls back to the nearest of all).
function MapService.NearestPickup(position: Vector3, exclude: { [number]: boolean }?): Point?
	local best: Point? = nil
	local bestDist = math.huge
	local bestAny: Point? = nil
	local bestAnyDist = math.huge
	for _, p in pickups do
		local d = VecUtil.FlatDistance(p.position, position)
		if d < bestAnyDist then
			bestAnyDist = d
			bestAny = p
		end
		if not (exclude and exclude[p.index]) and d < bestDist then
			bestDist = d
			best = p
		end
	end
	return best or bestAny
end

function MapService.GetMapFolder(): Instance?
	return workspace:FindFirstChild("Map")
end

-- RaycastParams that only see static map geometry.
function MapService.StaticRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local map = MapService.GetMapFolder()
	params.FilterDescendantsInstances = if map then { map } else {}
	return params
end

-- Ground height under a flat position, or `fallback` when nothing is below.
function MapService.GroundY(position: Vector3, fallback: number): number
	local origin = Vector3.new(position.X, position.Y + 60, position.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -200, 0), MapService.StaticRaycastParams())
	if result then
		return result.Position.Y
	end
	return fallback
end

return MapService
