--!strict
-- Discovers the map by CollectionService tag and answers spatial questions. Nothing is looked up by name.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)

export type Point = {
	index: number,
	position: Vector3,
	cframe: CFrame, -- LookVector faces the road
	part: BasePart,
}

local MapService = {}

local pickups: { Point } = {}
local dropoffs: { Point } = {}
local startPads: { Point } = {}
local itemBoxes: { BasePart } = {}
local center = Vector3.zero

local function collectPoints(tagName: string): { Point }
	local list: { Point } = {}
	for _, inst in CollectionService:GetTagged(tagName) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local idx = inst:GetAttribute("Index")
			table.insert(list, {
				index = if typeof(idx) == "number" then idx else #list + 1,
				position = inst.Position,
				cframe = inst.CFrame,
				part = inst,
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

function MapService.Init()
	pickups = collectPoints(Config.Tags.PickupPoint)
	dropoffs = collectPoints(Config.Tags.DropoffPoint)
	startPads = collectPoints(Config.Tags.StartPad)
	itemBoxes = {}
	for _, inst in CollectionService:GetTagged(Config.Tags.ItemBox) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(itemBoxes, inst)
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
