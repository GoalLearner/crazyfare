--!strict
-- Where the sidewalks are, from a map's Blockout spec (Config.Map.*.Blockout), so the server (walkers, hails) and the
-- client (the HAIL CAB button) always agree. A block is a CellSize square around each CellCenters pair; its outer
-- Sidewalk studs are the sidewalk and its edge is the curb. Everything between blocks, inside the outer road, is road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Blockout = typeof(Config.Map.City.Blockout)

local Sidewalk = {}

-- A map's Blockout spec by name (the City's for an unknown name).
function Sidewalk.Blockout(mapName: string?): Blockout
	local mapCfg = if mapName then (Config.Map :: any)[mapName] else nil
	return if typeof(mapCfg) == "table" and mapCfg.Blockout then mapCfg.Blockout else Config.Map.City.Blockout
end

-- The center of the block `position` stands on, or nil in the road.
function Sidewalk.BlockAt(B: Blockout, position: Vector3): Vector3?
	local half = B.CellSize / 2
	for _, cx in B.CellCenters do
		if math.abs(position.X - cx) <= half then
			for _, cz in B.CellCenters do
				if math.abs(position.Z - cz) <= half then
					return Vector3.new(cx, 0, cz)
				end
			end
		end
	end
	return nil
end

-- In a traffic lane: inside the outer road, off every block.
function Sidewalk.InRoad(B: Blockout, position: Vector3): boolean
	local outer = 0
	for _, c in B.RoadCoords do
		outer = math.max(outer, math.abs(c))
	end
	outer += B.RoadWidth / 2
	if math.abs(position.X) > outer or math.abs(position.Z) > outer then
		return false
	end
	return Sidewalk.BlockAt(B, position) == nil
end

-- The curb point nearest `position` on `block`, `inset` studs in from the edge, and the way out to the road.
local function edgeOf(B: Blockout, block: Vector3, position: Vector3, inset: number): (Vector3, Vector3)
	local half = B.CellSize / 2
	local dx, dz = position.X - block.X, position.Z - block.Z
	local edge = half - inset
	if math.abs(dx) >= math.abs(dz) then
		local side = if dx >= 0 then 1 else -1
		return Vector3.new(block.X + side * edge, position.Y, block.Z + math.clamp(dz, -edge, edge)), Vector3.new(side, 0, 0)
	end
	local side = if dz >= 0 then 1 else -1
	return Vector3.new(block.X + math.clamp(dx, -edge, edge), position.Y, block.Z + side * edge), Vector3.new(0, 0, side)
end

-- On a block: how far to its curb (nil in the road).
function Sidewalk.CurbDistance(B: Blockout, position: Vector3): number?
	local block = Sidewalk.BlockAt(B, position)
	if not block then
		return nil
	end
	local half = B.CellSize / 2
	return half - math.max(math.abs(position.X - block.X), math.abs(position.Z - block.Z))
end

-- Standing close enough to the curb to hail: the hail spot `inset` in from the curb, and the way to the road.
function Sidewalk.CurbSpot(B: Blockout, position: Vector3, inset: number): (Vector3?, Vector3?)
	local block = Sidewalk.BlockAt(B, position)
	if not block then
		return nil, nil
	end
	return edgeOf(B, block, position, inset)
end

-- The nearest sidewalk point to someone in the road (`inset` in from the curb of the closest block).
function Sidewalk.Nearest(B: Blockout, position: Vector3, inset: number): Vector3
	local best = position
	local bestDistance = math.huge
	local half = B.CellSize / 2
	for _, cx in B.CellCenters do
		for _, cz in B.CellCenters do
			local block = Vector3.new(cx, 0, cz)
			local clamped = Vector3.new(math.clamp(position.X, cx - half, cx + half), position.Y, math.clamp(position.Z, cz - half, cz + half))
			local d = (Vector3.new(clamped.X, 0, clamped.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if d < bestDistance then
				bestDistance = d
				best = (edgeOf(B, block, clamped, inset))
			end
		end
	end
	return best
end

return Sidewalk
