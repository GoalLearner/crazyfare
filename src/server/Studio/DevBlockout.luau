--!strict
-- Studio-only: builds the blocked-out City from Parts, every gameplay part CollectionService-tagged, plus the
-- parts-built Yellow Cab template in ReplicatedStorage.VehicleTemplates. Deterministic from Config.Map.City.Blockout.Seed.
-- Main.server runs it in Studio when the place has no workspace.Map. To bake the map into a place, run from the command bar:
--   require(game.ServerScriptService.Server.Studio.DevBlockout).Generate()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)

local Tags = Config.Tags
local B = Config.Map.City.Blockout

local DevBlockout = {}

local PALETTE = {
	Color3.fromRGB(196, 170, 140),
	Color3.fromRGB(150, 160, 175),
	Color3.fromRGB(180, 120, 100),
	Color3.fromRGB(120, 140, 160),
	Color3.fromRGB(205, 190, 165),
	Color3.fromRGB(110, 110, 120),
	Color3.fromRGB(170, 150, 170),
	Color3.fromRGB(215, 160, 120),
	Color3.fromRGB(140, 175, 165),
}
local MATERIALS = { Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.SmoothPlastic, Enum.Material.Metal }
local SKYLINE_PALETTE = {
	Color3.fromRGB(70, 78, 96),
	Color3.fromRGB(84, 90, 108),
	Color3.fromRGB(62, 70, 88),
	Color3.fromRGB(96, 100, 118),
}
local COLOR_GROUND = Color3.fromRGB(88, 140, 70)
local COLOR_ROAD = Color3.fromRGB(52, 52, 56)
local COLOR_LINE = Color3.fromRGB(240, 200, 60)
local COLOR_CROSSWALK = Color3.fromRGB(230, 230, 225)
local COLOR_SIDEWALK = Color3.fromRGB(190, 190, 185)
local COLOR_PLAZA = Color3.fromRGB(215, 205, 190)
local COLOR_WALL = Color3.fromRGB(80, 80, 85)
local COLOR_PICKUP = Color3.fromRGB(60, 200, 90)
local COLOR_DROPOFF = Color3.fromRGB(70, 130, 240)
local COLOR_BOX = Color3.fromRGB(80, 230, 255)
local COLOR_RAMP = Color3.fromRGB(230, 120, 40)
local COLOR_TRUNK = Color3.fromRGB(110, 75, 45)
local COLOR_CROWN = Color3.fromRGB(60, 150, 70)
local COLOR_PAD = Color3.fromRGB(245, 245, 245)
local COLOR_WINDOW = Color3.fromRGB(170, 215, 240)
local COLOR_HYDRANT = Color3.fromRGB(220, 50, 50)
local COLOR_CONE = Color3.fromRGB(255, 130, 30)
local COLOR_BIN = Color3.fromRGB(70, 110, 80)

local PARK_CELLS: { [string]: boolean } = { ["-120,120"] = true, ["240,-240"] = true, ["-240,0"] = true }

type Spot = { position: Vector3, look: Vector3 }
type Lot = { x: number, z: number, w: number, d: number }

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance, tagName: string?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	if tagName then
		CollectionService:AddTag(part, tagName)
	end
	return part
end

-- Decoration that neither cars nor raycasts should notice.
local function decor(part: Part): Part
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function cellKey(cx: number, cz: number): string
	return string.format("%d,%d", cx, cz)
end

local function buildGround(map: Folder)
	local size = B.Half * 2
	local ground = makePart("Ground", Vector3.new(size + 500, 2, size + 500), CFrame.new(0, -1, 0), COLOR_GROUND, map, Tags.Ground)
	ground.Material = Enum.Material.Grass
end

local function buildRoads(map: Folder)
	local size = B.Half * 2
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = map
	for i, r in B.RoadCoords do
		local ns = makePart("RoadNS_" .. i, Vector3.new(B.RoadWidth, 0.2, size), CFrame.new(r, 0.1, 0), COLOR_ROAD, roads, Tags.Road)
		ns.Material = Enum.Material.Asphalt
		local ew = makePart("RoadEW_" .. i, Vector3.new(size, 0.2, B.RoadWidth), CFrame.new(0, 0.11, r), COLOR_ROAD, roads, Tags.Road)
		ew.Material = Enum.Material.Asphalt
		decor(makePart("LineNS_" .. i, Vector3.new(0.6, 0.05, size), CFrame.new(r, 0.24, 0), COLOR_LINE, roads))
		decor(makePart("LineEW_" .. i, Vector3.new(size, 0.05, 0.6), CFrame.new(0, 0.245, r), COLOR_LINE, roads))
	end
	-- Crosswalk stripes on every side of every intersection.
	local half = B.RoadWidth / 2
	for _, rx in B.RoadCoords do
		for _, rz in B.RoadCoords do
			for _, side in { -1, 1 } do
				for stripe = -3, 3 do
					local x = rx + stripe * 3
					local z = rz + side * (half + 2.5)
					decor(makePart("Crosswalk", Vector3.new(1.6, 0.05, 4), CFrame.new(x, 0.25, z), COLOR_CROSSWALK, roads))
					local x2 = rx + side * (half + 2.5)
					local z2 = rz + stripe * 3
					decor(makePart("Crosswalk", Vector3.new(4, 0.05, 1.6), CFrame.new(x2, 0.255, z2), COLOR_CROSSWALK, roads))
				end
			end
		end
	end
end

local function buildStartPads(parent: Folder, cx: number, cz: number)
	local padIndex = 0
	for row = 0, 2 do
		for col = 0, 1 do
			padIndex += 1
			local x = cx + (if col == 0 then -10 else 10)
			local z = cz + 20 - row * 16
			local pad = decor(makePart("StartPad" .. padIndex, Vector3.new(7, 0.2, 12), CFrame.new(x, 0.6, z), COLOR_PAD, parent, Tags.StartPad))
			pad:SetAttribute("Index", padIndex)
		end
	end
end

local function buildTrees(parent: Folder, rng: Random, cx: number, cz: number)
	for _ = 1, 5 do
		local tx = cx + rng:NextNumber(-30, 30)
		local tz = cz + rng:NextNumber(-30, 30)
		local trunk = makePart("Trunk", Vector3.new(1.2, 6, 1.2), CFrame.new(tx, 3.5, tz), COLOR_TRUNK, parent)
		trunk.Material = Enum.Material.Wood
		local crown = makePart("Crown", Vector3.new(7, 7, 7), CFrame.new(tx, 9, tz), COLOR_CROWN, parent)
		crown.Shape = Enum.PartType.Ball
		crown.Material = Enum.Material.Grass
	end
end

-- Horizontal window bands every floor; glass so they read as windows by day and catch light at night.
local function buildWindows(parent: Folder, lot: Lot, height: number)
	local floorHeight = B.WindowFloorHeight
	local floors = math.floor((height - 4) / floorHeight)
	for f = 1, floors do
		local y = 0.5 + 3 + (f - 1) * floorHeight
		local band = decor(makePart("Windows", Vector3.new(lot.w + 0.3, 1.6, lot.d + 0.3), CFrame.new(lot.x, y, lot.z), COLOR_WINDOW, parent))
		band.Material = Enum.Material.Glass
		band.Transparency = 0.15
		band.Reflectance = 0.2
	end
end

local function buildBuildings(parent: Folder, rng: Random, cx: number, cz: number)
	local inner = B.CellSize - 2 * B.Sidewalk
	local layout = rng:NextInteger(1, 3)
	local lots: { Lot } = {}
	if layout == 1 then
		lots = { { x = cx, z = cz, w = inner - 10, d = inner - 10 } }
	elseif layout == 2 then
		if rng:NextNumber() < 0.5 then
			lots = { { x = cx - 20, z = cz, w = 32, d = inner - 10 }, { x = cx + 20, z = cz, w = 32, d = inner - 10 } }
		else
			lots = { { x = cx, z = cz - 20, w = inner - 10, d = 32 }, { x = cx, z = cz + 20, w = inner - 10, d = 32 } }
		end
	else
		for _, ox in { -20, 20 } do
			for _, oz in { -20, 20 } do
				table.insert(lots, { x = cx + ox, z = cz + oz, w = 30, d = 30 })
			end
		end
	end
	for li, lot in lots do
		local h = rng:NextNumber(B.BuildingMinHeight, B.BuildingMaxHeight)
		local color = PALETTE[rng:NextInteger(1, #PALETTE)]
		local building = makePart(
			string.format("Building_%s_%d", cellKey(cx, cz), li),
			Vector3.new(lot.w, h, lot.d),
			CFrame.new(lot.x, 0.5 + h / 2, lot.z),
			color,
			parent,
			Tags.Building
		)
		building.Material = MATERIALS[rng:NextInteger(1, #MATERIALS)]
		buildWindows(parent, lot, h)
		-- A roof cap in a darker tone gives the box a top edge.
		local cap = decor(makePart("Roof", Vector3.new(lot.w + 1, 0.8, lot.d + 1), CFrame.new(lot.x, 0.5 + h + 0.4, lot.z), Color3.fromRGB(60, 60, 68), parent))
		cap.Material = Enum.Material.Concrete
	end
end

-- Small street objects on the sidewalk corners: pushed by cars, launched by tomatoes. Unanchored, server-owned.
local function buildProps(parent: Folder, rng: Random, cx: number, cz: number)
	local corner = B.CellSize / 2 - B.Sidewalk / 2
	local corners = {
		Vector3.new(cx + corner, 0, cz + corner),
		Vector3.new(cx - corner, 0, cz + corner),
		Vector3.new(cx + corner, 0, cz - corner),
		Vector3.new(cx - corner, 0, cz - corner),
	}
	for i = #corners, 2, -1 do
		local j = rng:NextInteger(1, i)
		corners[i], corners[j] = corners[j], corners[i]
	end
	for i = 1, math.min(B.PropsPerCell, #corners) do
		local at = corners[i]
		local kind = rng:NextInteger(1, 3)
		local prop: Part
		if kind == 1 then
			prop = makePart("Hydrant", Vector3.new(1.2, 2.4, 1.2), CFrame.new(at.X, 0.5 + 1.2, at.Z), COLOR_HYDRANT, parent, Tags.Prop)
			prop.Shape = Enum.PartType.Cylinder
			prop.CFrame = prop.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		elseif kind == 2 then
			prop = makePart("Cone", Vector3.new(1.6, 2.2, 1.6), CFrame.new(at.X, 0.5 + 1.1, at.Z), COLOR_CONE, parent, Tags.Prop)
		else
			prop = makePart("Bin", Vector3.new(2, 3, 2), CFrame.new(at.X, 0.5 + 1.5, at.Z), COLOR_BIN, parent, Tags.Prop)
			prop.Shape = Enum.PartType.Cylinder
			prop.CFrame = prop.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		end
		prop.Anchored = false
		prop.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.5, 0.2, 1, 1)
	end
end

local function buildCells(map: Folder, rng: Random): { Spot }
	local cells = Instance.new("Folder")
	cells.Name = "Blocks"
	cells.Parent = map
	local spots: { Spot } = {}
	for _, cx in B.CellCenters do
		for _, cz in B.CellCenters do
			local isPlaza = cx == 0 and cz == 0
			local key = cellKey(cx, cz)
			local slab = makePart(
				"Cell_" .. key,
				Vector3.new(B.CellSize, 0.5, B.CellSize),
				CFrame.new(cx, 0.25, cz),
				if isPlaza then COLOR_PLAZA else COLOR_SIDEWALK,
				cells,
				Tags.Sidewalk
			)
			slab.Material = Enum.Material.Concrete
			if isPlaza then
				buildStartPads(cells, cx, cz)
			elseif PARK_CELLS[key] then
				buildTrees(cells, rng, cx, cz)
			else
				buildBuildings(cells, rng, cx, cz)
			end
			if not isPlaza then
				buildProps(cells, rng, cx, cz)
				local e = B.CellSize / 2 - 3
				table.insert(spots, { position = Vector3.new(cx + e, 0.5, cz), look = Vector3.new(1, 0, 0) })
				table.insert(spots, { position = Vector3.new(cx - e, 0.5, cz), look = Vector3.new(-1, 0, 0) })
				table.insert(spots, { position = Vector3.new(cx, 0.5, cz + e), look = Vector3.new(0, 0, 1) })
				table.insert(spots, { position = Vector3.new(cx, 0.5, cz - e), look = Vector3.new(0, 0, -1) })
			end
		end
	end
	return spots
end

-- Greedy spread pick from a shuffled list; relaxes the separation until `count` are found.
-- `initial` seeds the chosen set (they count toward `count` and keep their spacing).
local function pickSpread(spots: { Spot }, count: number, minSep: number, avoid: { Spot }, avoidSep: number, initial: { Spot }?): { Spot }
	local sep = minSep
	while sep >= 10 do
		local chosen: { Spot } = {}
		if initial then
			for _, s in initial do
				table.insert(chosen, s)
			end
		end
		for _, s in spots do
			if #chosen >= count then
				break
			end
			local ok = true
			for _, c in chosen do
				if (c.position - s.position).Magnitude < sep then
					ok = false
					break
				end
			end
			if ok then
				for _, a in avoid do
					if (a.position - s.position).Magnitude < avoidSep then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(chosen, s)
			end
		end
		if #chosen >= count then
			return chosen
		end
		sep -= 10
	end
	return {}
end

local function buildPoints(map: Folder, rng: Random, spots: { Spot })
	for i = #spots, 2, -1 do
		local j = rng:NextInteger(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	-- Guarantee some pickups near the start grid so green fares exist from the first second.
	local nearRadius = Config.Fares.TierWeightsByDistance[1].MaxDistance
	local nearSpots: { Spot } = {}
	for _, s in spots do
		if Vector3.new(s.position.X, 0, s.position.Z).Magnitude <= nearRadius then
			table.insert(nearSpots, s)
		end
	end
	local nearPicks = pickSpread(nearSpots, B.NearStartPickups, 60, {}, 0)
	local pickupSpots = pickSpread(spots, B.PickupPoints, 70, {}, 0, nearPicks)
	local dropoffSpots = pickSpread(spots, B.DropoffPoints, 60, pickupSpots, 30)

	local points = Instance.new("Folder")
	points.Name = "Points"
	points.Parent = map

	local function marker(prefix: string, spot: Spot, index: number, color: Color3, tagName: string)
		local pos = spot.position + Vector3.new(0, 0.15, 0)
		local cf = CFrame.lookAt(pos, pos + spot.look) * CFrame.Angles(0, 0, math.pi / 2)
		local part = decor(makePart(prefix .. index, Vector3.new(0.3, 7, 7), cf, color, points, tagName))
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Transparency = 0.2
		part:SetAttribute("Index", index)
	end
	for i, spot in pickupSpots do
		marker("PickupPoint", spot, i, COLOR_PICKUP, Tags.PickupPoint)
	end
	for i, spot in dropoffSpots do
		marker("DropoffPoint", spot, i, COLOR_DROPOFF, Tags.DropoffPoint)
	end
end

local function buildItemBoxes(map: Folder)
	local items = Instance.new("Folder")
	items.Name = "ItemBoxes"
	items.Parent = map
	local boxSpots = {
		Vector3.new(-180, 4, -180),
		Vector3.new(180, 4, -180),
		Vector3.new(-180, 4, 180),
		Vector3.new(180, 4, 180),
		Vector3.new(-300, 4, 0),
		Vector3.new(300, 4, 0),
	}
	for i = 1, math.min(B.ItemBoxes, #boxSpots) do
		local pos = boxSpots[i]
		local box = decor(makePart("ItemBox" .. i, Vector3.new(4, 4, 4), CFrame.new(pos), COLOR_BOX, items, Tags.ItemBox))
		box.Material = Enum.Material.Neon
		box:SetAttribute("Index", i)
		box:SetAttribute("Active", true)
	end
end

-- A hump: one tilted slab up, a mirrored slab down, so it works from both directions and has no wall to wedge against.
local function buildRamps(map: Folder)
	local length, height, width = 24, 6, 12
	local angle = math.asin(height / length)
	local run = length * math.cos(angle) -- horizontal extent of one slab

	local function slab(name: string, x: number, z: number, yaw: number)
		local cf = CFrame.new(x, 0.2 + height / 2, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(angle, 0, 0)
		makePart(name, Vector3.new(width, 0.6, length), cf, COLOR_RAMP, map, Tags.Ramp)
	end

	local function hump(name: string, x: number, z: number, yaw: number)
		-- The up slab climbs toward its local -Z; the down slab sits one run further along and faces back.
		local look = CFrame.Angles(0, yaw, 0).LookVector
		slab(name .. "Up", x, z, yaw)
		slab(name .. "Down", x + look.X * run, z + look.Z * run, yaw + math.pi)
	end

	hump("RampNorth", -180, -120, 0)
	hump("RampSouth", 180, 120, math.pi)
	hump("RampWest", 120, 180, math.pi / 2)
	hump("RampEast", -120, -180, -math.pi / 2)
end

-- Invisible barrier at the playable edge; the grass and skyline carry on behind it.
local function buildWalls(map: Folder)
	local size = B.Half * 2
	local h = B.WallHeight
	local walls = {
		makePart("WallN", Vector3.new(size + 8, h, 4), CFrame.new(0, h / 2, -B.Half - 2), COLOR_WALL, map, Tags.Wall),
		makePart("WallS", Vector3.new(size + 8, h, 4), CFrame.new(0, h / 2, B.Half + 2), COLOR_WALL, map, Tags.Wall),
		makePart("WallE", Vector3.new(4, h, size + 8), CFrame.new(B.Half + 2, h / 2, 0), COLOR_WALL, map, Tags.Wall),
		makePart("WallW", Vector3.new(4, h, size + 8), CFrame.new(-B.Half - 2, h / 2, 0), COLOR_WALL, map, Tags.Wall),
	}
	for _, wall in walls do
		wall.Transparency = 1
	end
	-- A low curb so the edge still reads as an edge.
	for _, wall in walls do
		local curb = makePart("Curb", Vector3.new(math.max(wall.Size.X, 4), 1, math.max(wall.Size.Z, 4)), CFrame.new(wall.Position.X, 0.5, wall.Position.Z), COLOR_SIDEWALK, map)
		curb.Material = Enum.Material.Concrete
		curb.CanQuery = false
	end
end

-- Background skyline beyond the barrier: unreachable, untagged, pure horizon.
local function buildSkyline(map: Folder, rng: Random)
	local skyline = Instance.new("Folder")
	skyline.Name = "Skyline"
	skyline.Parent = map
	local inner, outer = B.SkylineInner, B.SkylineOuter
	for _, radius in { inner, (inner + outer) / 2, outer } do
		local step = 52
		for t = -radius, radius, step do
			local jitter = rng:NextNumber(-10, 10)
			for _, pos in {
				Vector3.new(t + jitter, 0, -radius),
				Vector3.new(t + jitter, 0, radius),
				Vector3.new(-radius, 0, t + jitter),
				Vector3.new(radius, 0, t + jitter),
			} do
				local w = rng:NextNumber(28, 46)
				local h = rng:NextNumber(B.SkylineMinHeight, B.SkylineMaxHeight)
				local color = SKYLINE_PALETTE[rng:NextInteger(1, #SKYLINE_PALETTE)]
				local tower = makePart("Skyline", Vector3.new(w, h, w), CFrame.new(pos.X, h / 2, pos.Z), color, skyline)
				tower.Material = Enum.Material.Concrete
				tower.CanQuery = false
			end
		end
	end
end

local function buildVehicleTemplate()
	local templates = ReplicatedStorage:FindFirstChild("VehicleTemplates")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "VehicleTemplates"
		templates.Parent = ReplicatedStorage
	end
	local old = templates:FindFirstChild("YellowCab")
	if old then
		old:Destroy()
	end
	local cab = VehicleBuilder.Build("YellowCab")
	CollectionService:AddTag(cab, Tags.VehicleTemplate)
	cab.Parent = templates
end

function DevBlockout.Generate(): Folder
	for _, name in { "Map", "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local rng = Random.new(B.Seed)
	local map = Instance.new("Folder")
	map.Name = "Map"

	buildGround(map)
	buildRoads(map)
	local spots = buildCells(map, rng)
	buildPoints(map, rng, spots)
	buildItemBoxes(map)
	buildRamps(map)
	buildWalls(map)
	buildSkyline(map, rng)
	buildVehicleTemplate()

	map.Parent = workspace
	print(string.format("[DevBlockout] City built: %d parts", #map:GetDescendants()))
	return map
end

return DevBlockout
