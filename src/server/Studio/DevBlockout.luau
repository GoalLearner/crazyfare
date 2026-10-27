--!strict
-- Builds a map from Parts, every gameplay part CollectionService-tagged, plus the parts-built Yellow Cab template in
-- ReplicatedStorage.VehicleTemplates. Deterministic from the map's Blockout.Seed. Two themes: "city" and "beach".
-- MapService.LoadMap calls this at match start (maps rotate); it also runs at server boot when the place has no Map.
-- To bake a map into a place from the command bar:
--   require(game.ServerScriptService.Server.Studio.DevBlockout).Generate("City")

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)

local Tags = Config.Tags

local DevBlockout = {}

type Blockout = typeof(Config.Map.City.Blockout)
type Ctx = { B: Blockout, theme: string, rng: Random, map: Folder, mapName: string }
type Spot = { position: Vector3, look: Vector3 }
type Lot = { x: number, z: number, w: number, d: number }

local CITY_PALETTE = {
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
local BEACH_PALETTE = {
	Color3.fromRGB(250, 220, 200),
	Color3.fromRGB(190, 230, 230),
	Color3.fromRGB(255, 200, 150),
	Color3.fromRGB(200, 240, 200),
	Color3.fromRGB(240, 180, 200),
	Color3.fromRGB(230, 230, 190),
}
local MATERIALS = { Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.SmoothPlastic, Enum.Material.Metal }
local SKYLINE_PALETTE = {
	Color3.fromRGB(70, 78, 96),
	Color3.fromRGB(84, 90, 108),
	Color3.fromRGB(62, 70, 88),
	Color3.fromRGB(96, 100, 118),
}
-- Storefront decoration. None share a destination's name (Config.Destinations), so a sign never points the wrong way.
-- Keep 16 entries: the seeded layout draws one number per sign either way.
local SIGN_NAMES = { "JOE'S DINER", "BAKERY", "NOODLE BAR", "LAUNDRO", "PAWN", "CAFE LUNA", "TACO 24", "VINYL", "KARAOKE", "FLOWERS", "PHARMA", "PET SHOP", "SUSHI GO", "BARBER", "BOOKS", "DONUT KING" }
local SIGN_COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(80, 230, 255),
	Color3.fromRGB(255, 220, 80),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(200, 120, 255),
}

local COLOR_GROUND = Color3.fromRGB(88, 140, 70)
local COLOR_SAND = Color3.fromRGB(226, 206, 150)
local COLOR_WATER = Color3.fromRGB(50, 140, 200)
local COLOR_ROAD = Color3.fromRGB(52, 52, 56)
local COLOR_BOARDWALK = Color3.fromRGB(190, 150, 100)
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
local COLOR_PALM = Color3.fromRGB(70, 170, 80)
local COLOR_PAD = Color3.fromRGB(245, 245, 245)
local COLOR_WINDOW = Color3.fromRGB(170, 215, 240)
local COLOR_HYDRANT = Color3.fromRGB(220, 50, 50)
local COLOR_CONE = Color3.fromRGB(255, 130, 30)
local COLOR_BIN = Color3.fromRGB(70, 110, 80)
local COLOR_POST = Color3.fromRGB(70, 72, 80)
local COLOR_LAMP = Color3.fromRGB(255, 240, 190)

local PARK_CELLS: { [string]: boolean } = { ["-120,120"] = true, ["240,-240"] = true, ["-240,0"] = true }
local ALLEY_CELLS: { [string]: boolean } = { ["-120,-120"] = true, ["120,120"] = true }
local LANDMARK_CELLS: { [string]: string } = { ["240,240"] = "hotel", ["-240,-240"] = "dome", ["0,-240"] = "antenna" }

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

local function isOuterCell(ctx: Ctx, cx: number, cz: number): boolean
	local centers = ctx.B.CellCenters
	local edge = math.max(math.abs(centers[1]), math.abs(centers[#centers]))
	return math.abs(cx) == edge or math.abs(cz) == edge
end

-- What a block holds: "plaza" | "sand" | "park" | a landmark kind | "alley" | "buildings". buildCells builds from this
-- and drop-off naming reads it, so both always agree.
local function cellKind(ctx: Ctx, cx: number, cz: number): string
	local key = cellKey(cx, cz)
	if cx == 0 and cz == 0 then
		return "plaza"
	elseif ctx.theme == "beach" and isOuterCell(ctx, cx, cz) then
		return "sand"
	elseif PARK_CELLS[key] then
		return "park"
	elseif ctx.theme == "city" and LANDMARK_CELLS[key] then
		return LANDMARK_CELLS[key]
	elseif ctx.theme == "city" and ALLEY_CELLS[key] then
		return "alley"
	end
	return "buildings"
end

local function buildGround(ctx: Ctx)
	local size = ctx.B.Half * 2
	if ctx.theme == "beach" then
		local sand = makePart("Ground", Vector3.new(size + 140, 2, size + 140), CFrame.new(0, -1, 0), COLOR_SAND, ctx.map, Tags.Ground)
		sand.Material = Enum.Material.Sand
		local water = makePart("Water", Vector3.new(4000, 1, 4000), CFrame.new(0, -1.6, 0), COLOR_WATER, ctx.map, Tags.Water)
		water.Material = Enum.Material.Glass
		water.Transparency = 0.15
		water.Reflectance = 0.3
		water.CanQuery = false
	else
		local ground = makePart("Ground", Vector3.new(size + 500, 2, size + 500), CFrame.new(0, -1, 0), COLOR_GROUND, ctx.map, Tags.Ground)
		ground.Material = Enum.Material.Grass
	end
end

local function buildRoads(ctx: Ctx)
	local B = ctx.B
	local size = B.Half * 2
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = ctx.map
	local outer = math.max(math.abs(B.RoadCoords[1]), math.abs(B.RoadCoords[#B.RoadCoords]))
	for i, r in B.RoadCoords do
		local boardwalk = ctx.theme == "beach" and math.abs(r) == outer
		local color = if boardwalk then COLOR_BOARDWALK else COLOR_ROAD
		local material = if boardwalk then Enum.Material.WoodPlanks else Enum.Material.Asphalt
		local tag = if boardwalk then Tags.Boardwalk else Tags.Road
		local ns = makePart("RoadNS_" .. i, Vector3.new(B.RoadWidth, 0.2, size), CFrame.new(r, 0.1, 0), color, roads, tag)
		ns.Material = material
		local ew = makePart("RoadEW_" .. i, Vector3.new(size, 0.2, B.RoadWidth), CFrame.new(0, 0.11, r), color, roads, tag)
		ew.Material = material
		if not boardwalk then
			decor(makePart("LineNS_" .. i, Vector3.new(0.6, 0.05, size), CFrame.new(r, 0.24, 0), COLOR_LINE, roads))
			decor(makePart("LineEW_" .. i, Vector3.new(size, 0.05, 0.6), CFrame.new(0, 0.245, r), COLOR_LINE, roads))
		end
	end
	-- Crosswalk stripes on every side of every intersection.
	local half = B.RoadWidth / 2
	for _, rx in B.RoadCoords do
		for _, rz in B.RoadCoords do
			for _, side in { -1, 1 } do
				for stripe = -3, 3 do
					decor(makePart("Crosswalk", Vector3.new(1.6, 0.05, 4), CFrame.new(rx + stripe * 3, 0.25, rz + side * (half + 2.5)), COLOR_CROSSWALK, roads))
					decor(makePart("Crosswalk", Vector3.new(4, 0.05, 1.6), CFrame.new(rx + side * (half + 2.5), 0.255, rz + stripe * 3), COLOR_CROSSWALK, roads))
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

local function buildTree(parent: Folder, tx: number, tz: number)
	local trunk = makePart("Trunk", Vector3.new(1.2, 6, 1.2), CFrame.new(tx, 3.5, tz), COLOR_TRUNK, parent)
	trunk.Material = Enum.Material.Wood
	local crown = makePart("Crown", Vector3.new(7, 7, 7), CFrame.new(tx, 9, tz), COLOR_CROWN, parent)
	crown.Shape = Enum.PartType.Ball
	crown.Material = Enum.Material.Grass
end

local function buildPalm(parent: Folder, rng: Random, tx: number, tz: number)
	local lean = rng:NextNumber(-0.18, 0.18)
	local trunk = makePart("PalmTrunk", Vector3.new(1, 11, 1), CFrame.new(tx, 6, tz) * CFrame.Angles(lean, 0, lean), COLOR_TRUNK, parent)
	trunk.Material = Enum.Material.Wood
	for k = 0, 5 do
		local a = k * math.pi / 3 + rng:NextNumber(-0.2, 0.2)
		local leaf = decor(makePart("PalmLeaf", Vector3.new(1.2, 0.2, 6), CFrame.new(tx, 11.3, tz) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -3) * CFrame.Angles(-0.35, 0, 0), COLOR_PALM, parent))
		leaf.Material = Enum.Material.Grass
	end
end

local function buildTrees(ctx: Ctx, parent: Folder, cx: number, cz: number)
	for _ = 1, 5 do
		local tx = cx + ctx.rng:NextNumber(-30, 30)
		local tz = cz + ctx.rng:NextNumber(-30, 30)
		if ctx.theme == "beach" then
			buildPalm(parent, ctx.rng, tx, tz)
		else
			buildTree(parent, tx, tz)
		end
	end
end

-- Horizontal window bands every floor; glass so they read as windows by day and catch light at night.
local function buildWindows(ctx: Ctx, parent: Folder, lot: Lot, height: number)
	local floorHeight = ctx.B.WindowFloorHeight
	local floors = math.floor((height - 4) / floorHeight)
	for f = 1, floors do
		local y = 0.5 + 3 + (f - 1) * floorHeight
		local band = decor(makePart("Windows", Vector3.new(lot.w + 0.3, 1.6, lot.d + 0.3), CFrame.new(lot.x, y, lot.z), COLOR_WINDOW, parent))
		band.Material = Enum.Material.Glass
		band.Transparency = 0.15
		band.Reflectance = 0.2
	end
end

-- A storefront sign on the road-facing side of a lot (city only).
local function buildSign(ctx: Ctx, parent: Folder, lot: Lot, cx: number, cz: number)
	local rng = ctx.rng
	-- Face the nearest road: pick the lot edge farthest from the cell centre.
	local dx, dz = lot.x - cx, lot.z - cz
	local faceX = math.abs(dx) >= math.abs(dz)
	local dir = if faceX then (if dx >= 0 then 1 else -1) else (if dz >= 0 then 1 else -1)
	if dx == 0 and dz == 0 then
		faceX = false
		dir = 1
	end
	local width = (if faceX then lot.d else lot.w) * 0.7
	local pos = if faceX
		then Vector3.new(lot.x + dir * (lot.w / 2 + 0.3), 4.2, lot.z)
		else Vector3.new(lot.x, 4.2, lot.z + dir * (lot.d / 2 + 0.3))
	local cf = CFrame.new(pos) * (if faceX then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new())
	local sign = decor(makePart("Sign", Vector3.new(width, 2.4, 0.5), cf, Color3.fromRGB(20, 20, 26), parent))
	local color = SIGN_COLORS[rng:NextInteger(1, #SIGN_COLORS)]
	local gui = Instance.new("SurfaceGui")
	gui.Face = if dir > 0 then Enum.NormalId.Back else Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = SIGN_NAMES[rng:NextInteger(1, #SIGN_NAMES)]
	label.Parent = gui
	local glow = decor(makePart("SignGlow", Vector3.new(width + 0.6, 0.3, 0.6), cf * CFrame.new(0, -1.5, 0), color, parent))
	glow.Material = Enum.Material.Neon
end

-- Imported building meshes (ReplicatedStorage.MapModels.Buildings.*) replace the boxes when present.
local function buildingTemplates(): { Model }
	local list: { Model } = {}
	local folder = ReplicatedStorage:FindFirstChild("MapModels")
	local buildings = if folder then folder:FindFirstChild("Buildings") else nil
	if buildings then
		for _, child in buildings:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function placeBuildingMesh(ctx: Ctx, parent: Folder, lot: Lot, templates: { Model }): boolean
	local template = templates[ctx.rng:NextInteger(1, #templates)]
	local clone = template:Clone()
	local _, bounds = clone:GetBoundingBox()
	local scale = math.min(lot.w / math.max(bounds.X, 0.01), lot.d / math.max(bounds.Z, 0.01))
	clone:ScaleTo(clone:GetScale() * scale)
	local _, scaled = clone:GetBoundingBox()
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			CollectionService:AddTag(part, Tags.Building)
		end
	end
	clone:PivotTo(CFrame.new(lot.x, 0.5 + scaled.Y / 2, lot.z))
	clone.Parent = parent
	return true
end

local function buildBuildingLot(ctx: Ctx, parent: Folder, lot: Lot, cx: number, cz: number, li: number)
	local B = ctx.B
	local rng = ctx.rng
	if ctx.theme == "city" then
		local templates = buildingTemplates()
		if #templates > 0 and placeBuildingMesh(ctx, parent, lot, templates) then
			return
		end
	end
	local h = rng:NextNumber(B.BuildingMinHeight, B.BuildingMaxHeight)
	local palette = if ctx.theme == "beach" then BEACH_PALETTE else CITY_PALETTE
	local color = palette[rng:NextInteger(1, #palette)]
	local building = makePart(
		string.format("Building_%s_%d", cellKey(cx, cz), li),
		Vector3.new(lot.w, h, lot.d),
		CFrame.new(lot.x, 0.5 + h / 2, lot.z),
		color,
		parent,
		Tags.Building
	)
	building.Material = if ctx.theme == "beach" then Enum.Material.SmoothPlastic else MATERIALS[rng:NextInteger(1, #MATERIALS)]
	buildWindows(ctx, parent, lot, h)
	local cap = decor(makePart("Roof", Vector3.new(lot.w + 1, 0.8, lot.d + 1), CFrame.new(lot.x, 0.5 + h + 0.4, lot.z), Color3.fromRGB(60, 60, 68), parent))
	cap.Material = Enum.Material.Concrete
	if ctx.theme == "city" and rng:NextNumber() < 0.45 then
		buildSign(ctx, parent, lot, cx, cz)
	end
end

local function buildBuildings(ctx: Ctx, parent: Folder, cx: number, cz: number)
	local B = ctx.B
	local rng = ctx.rng
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
		buildBuildingLot(ctx, parent, lot, cx, cz, li)
	end
end

-- Alley cell: two buildings with a narrow road between them, so you can cut straight through the block.
local function buildAlley(ctx: Ctx, parent: Folder, cx: number, cz: number)
	local inner = ctx.B.CellSize - 2 * ctx.B.Sidewalk
	local alley = makePart("Alley", Vector3.new(12, 0.6, ctx.B.CellSize + 2), CFrame.new(cx, 0.3, cz), COLOR_ROAD, parent, Tags.Road)
	alley.Material = Enum.Material.Asphalt
	buildBuildingLot(ctx, parent, { x = cx - 22, z = cz, w = 30, d = inner - 10 }, cx, cz, 1)
	buildBuildingLot(ctx, parent, { x = cx + 22, z = cz, w = 30, d = inner - 10 }, cx, cz, 2)
end

-- Landmarks: one-of-a-kind shapes you can steer by from across the map.
local function buildLandmark(ctx: Ctx, parent: Folder, kind: string, cx: number, cz: number)
	if kind == "hotel" then
		local h = 110
		local tower = makePart("Hotel", Vector3.new(56, h, 56), CFrame.new(cx, 0.5 + h / 2, cz), Color3.fromRGB(230, 220, 200), parent, Tags.Building)
		tower.Material = Enum.Material.Concrete
		buildWindows(ctx, parent, { x = cx, z = cz, w = 56, d = 56 }, h)
		local crown = decor(makePart("HotelCrown", Vector3.new(60, 2, 60), CFrame.new(cx, h + 1.5, cz), Color3.fromRGB(255, 200, 80), parent))
		crown.Material = Enum.Material.Neon
		for _, dir in { -1, 1 } do
			local sign = decor(makePart("HotelSign", Vector3.new(40, 10, 0.8), CFrame.new(cx, h - 8, cz + dir * 28.6), Color3.fromRGB(20, 20, 26), parent))
			local gui = Instance.new("SurfaceGui")
			gui.Face = if dir > 0 then Enum.NormalId.Back else Enum.NormalId.Front
			gui.LightInfluence = 0
			gui.Parent = sign
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 90, 140)
			label.Text = "HOTEL"
			label.Parent = gui
		end
	elseif kind == "dome" then
		local base = makePart("Arena", Vector3.new(26, 72, 72), CFrame.new(cx, 13.5, cz) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 140, 160), parent, Tags.Building)
		base.Shape = Enum.PartType.Cylinder
		base.Material = Enum.Material.Concrete
		local dome = makePart("ArenaDome", Vector3.new(66, 66, 66), CFrame.new(cx, 26, cz), Color3.fromRGB(200, 210, 230), parent, Tags.Building)
		dome.Shape = Enum.PartType.Ball
		dome.Material = Enum.Material.Glass
		dome.Transparency = 0.25
		dome.Reflectance = 0.2
	elseif kind == "antenna" then
		local base = makePart("TowerBase", Vector3.new(24, 20, 24), CFrame.new(cx, 10.5, cz), Color3.fromRGB(110, 110, 120), parent, Tags.Building)
		base.Material = Enum.Material.Concrete
		local mast = makePart("Mast", Vector3.new(5, 130, 5), CFrame.new(cx, 20.5 + 65, cz), Color3.fromRGB(200, 60, 60), parent, Tags.Building)
		mast.Material = Enum.Material.Metal
		local tip = decor(makePart("MastTip", Vector3.new(3, 3, 3), CFrame.new(cx, 152, cz), Color3.fromRGB(255, 60, 60), parent))
		tip.Shape = Enum.PartType.Ball
		tip.Material = Enum.Material.Neon
	end
end

-- Small street objects on the sidewalk corners: pushed by cars, launched by tomatoes. Unanchored, server-owned.
local function buildProps(ctx: Ctx, parent: Folder, cx: number, cz: number)
	local B = ctx.B
	local rng = ctx.rng
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
		if ctx.theme == "beach" then
			if kind == 1 then
				prop = makePart("BeachBall", Vector3.new(2.2, 2.2, 2.2), CFrame.new(at.X, 0.5 + 1.1, at.Z), Color3.fromRGB(255, 120, 80), parent, Tags.Prop)
				prop.Shape = Enum.PartType.Ball
			elseif kind == 2 then
				prop = makePart("Cooler", Vector3.new(2.2, 1.6, 1.4), CFrame.new(at.X, 0.5 + 0.8, at.Z), Color3.fromRGB(80, 140, 230), parent, Tags.Prop)
			else
				prop = makePart("Surfboard", Vector3.new(1.4, 6, 0.4), CFrame.new(at.X, 0.5 + 3, at.Z) * CFrame.Angles(0, 0, 0.15), Color3.fromRGB(250, 230, 90), parent, Tags.Prop)
			end
		elseif kind == 1 then
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

local function buildCells(ctx: Ctx): { Spot }
	local B = ctx.B
	local cells = Instance.new("Folder")
	cells.Name = "Blocks"
	cells.Parent = ctx.map
	local spots: { Spot } = {}
	for _, cx in B.CellCenters do
		for _, cz in B.CellCenters do
			local kind = cellKind(ctx, cx, cz)
			local isPlaza = kind == "plaza"
			local key = cellKey(cx, cz)
			local sandCell = kind == "sand"
			local slab = makePart(
				"Cell_" .. key,
				Vector3.new(B.CellSize, 0.5, B.CellSize),
				CFrame.new(cx, 0.25, cz),
				if isPlaza then COLOR_PLAZA elseif sandCell then COLOR_SAND else COLOR_SIDEWALK,
				cells,
				if sandCell then Tags.Sand else Tags.Sidewalk
			)
			slab.Material = if sandCell then Enum.Material.Sand else Enum.Material.Concrete
			if isPlaza then
				buildStartPads(cells, cx, cz)
			elseif sandCell then
				for _ = 1, 3 do
					buildPalm(cells, ctx.rng, cx + ctx.rng:NextNumber(-36, 36), cz + ctx.rng:NextNumber(-36, 36))
				end
			elseif kind == "park" then
				buildTrees(ctx, cells, cx, cz)
			elseif LANDMARK_CELLS[key] and kind == LANDMARK_CELLS[key] then
				buildLandmark(ctx, cells, kind, cx, cz)
			elseif kind == "alley" then
				buildAlley(ctx, cells, cx, cz)
			else
				buildBuildings(ctx, cells, cx, cz)
			end
			if not isPlaza then
				buildProps(ctx, cells, cx, cz)
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

-- Streetlights on two corners and a traffic light on a third, at every inner intersection (city only).
local function buildStreetFurniture(ctx: Ctx)
	local B = ctx.B
	local folder = Instance.new("Folder")
	folder.Name = "Street"
	folder.Parent = ctx.map
	local outer = math.max(math.abs(B.RoadCoords[1]), math.abs(B.RoadCoords[#B.RoadCoords]))
	local offset = B.RoadWidth / 2 + 2
	for _, rx in B.RoadCoords do
		for _, rz in B.RoadCoords do
			if math.abs(rx) == outer or math.abs(rz) == outer then
				continue
			end
			for _, s in { -1, 1 } do
				local px, pz = rx + s * offset, rz + s * offset
				local post = decor(makePart("LampPost", Vector3.new(0.6, 11, 0.6), CFrame.new(px, 6, pz), COLOR_POST, folder))
				post.Material = Enum.Material.Metal
				local arm = decor(makePart("LampArm", Vector3.new(4, 0.4, 0.4), CFrame.new(px - s * 2, 11.2, pz), COLOR_POST, folder))
				arm.Material = Enum.Material.Metal
				local lamp = decor(makePart("Lamp", Vector3.new(1.6, 0.6, 1.4), CFrame.new(px - s * 4, 11, pz), COLOR_LAMP, folder))
				lamp.Material = Enum.Material.Neon
			end
			local tx, tz = rx + offset, rz - offset
			local post = decor(makePart("SignalPost", Vector3.new(0.5, 9, 0.5), CFrame.new(tx, 5, tz), COLOR_POST, folder))
			post.Material = Enum.Material.Metal
			local box = decor(makePart("SignalBox", Vector3.new(1.2, 3.6, 1.2), CFrame.new(tx, 9, tz), Color3.fromRGB(30, 30, 34), folder))
			box.Material = Enum.Material.Metal
			local lights = { Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 60), Color3.fromRGB(80, 230, 110) }
			local lit = ctx.rng:NextInteger(1, 3)
			for k, color in lights do
				local lightPart = decor(makePart("SignalLight", Vector3.new(0.8, 0.8, 0.3), CFrame.new(tx, 10.1 - (k - 1) * 1.1, tz - 0.6), color, folder))
				lightPart.Shape = Enum.PartType.Ball
				lightPart.Material = if k == lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
				if k ~= lit then
					lightPart.Color = color:Lerp(Color3.new(0, 0, 0), 0.6)
				end
			end
		end
	end
end

-- Greedy spread pick from a shuffled list; relaxes the separation until `count` are found.
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

local function buildPoints(ctx: Ctx, spots: { Spot })
	local B = ctx.B
	local rng = ctx.rng
	for i = #spots, 2, -1 do
		local j = rng:NextInteger(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
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
	points.Parent = ctx.map

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
	-- Name every drop-off: a landmark or park block lends its name, the rest take the map's list in order.
	local dest = Config.Destinations
	local list = dest.Names[ctx.mapName] or dest.Names.City
	local used: { [string]: boolean } = {}
	local nextName = 1
	local edge = B.CellSize / 2 - 3
	for i, spot in dropoffSpots do
		marker("DropoffPoint", spot, i, COLOR_DROPOFF, Tags.DropoffPoint)
		local center = spot.position - spot.look * edge
		local kind = cellKind(ctx, math.round(center.X), math.round(center.Z))
		local name = if kind == "park" then dest.Parks[ctx.mapName] else dest.Landmarks[kind]
		if not name or used[name] then
			while list[nextName] and used[list[nextName]] do
				nextName += 1
			end
			name = list[nextName] or string.format("STOP %d", i)
			nextName += 1
		end
		used[name] = true
		local part = points:FindFirstChild("DropoffPoint" .. i)
		if part then
			part:SetAttribute("Destination", name)
		end
	end
end

local function buildItemBoxes(ctx: Ctx)
	local items = Instance.new("Folder")
	items.Name = "ItemBoxes"
	items.Parent = ctx.map
	local boxSpots = {
		Vector3.new(-180, 4, -180),
		Vector3.new(180, 4, -180),
		Vector3.new(-180, 4, 180),
		Vector3.new(180, 4, 180),
		Vector3.new(-300, 4, 0),
		Vector3.new(300, 4, 0),
	}
	for i = 1, math.min(ctx.B.ItemBoxes, #boxSpots) do
		local pos = boxSpots[i]
		local box = decor(makePart("ItemBox" .. i, Vector3.new(4, 4, 4), CFrame.new(pos), COLOR_BOX, items, Tags.ItemBox))
		box.Material = Enum.Material.Neon
		box:SetAttribute("Index", i)
		box:SetAttribute("Active", true)
	end
end

-- A hump: one tilted slab up, a mirrored slab down, so it works from both directions and has no wall to wedge against.
local function buildRamps(ctx: Ctx)
	local length, height, width = 24, 6, 12
	local angle = math.asin(height / length)
	local run = length * math.cos(angle)
	local function slab(name: string, x: number, z: number, yaw: number)
		local cf = CFrame.new(x, 0.2 + height / 2, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(angle, 0, 0)
		makePart(name, Vector3.new(width, 0.6, length), cf, COLOR_RAMP, ctx.map, Tags.Ramp)
	end
	local function hump(name: string, x: number, z: number, yaw: number)
		local look = CFrame.Angles(0, yaw, 0).LookVector
		slab(name .. "Up", x, z, yaw)
		slab(name .. "Down", x + look.X * run, z + look.Z * run, yaw + math.pi)
	end
	hump("RampNorth", -180, -120, 0)
	hump("RampSouth", 180, 120, math.pi)
	hump("RampWest", 120, 180, math.pi / 2)
	hump("RampEast", -120, -180, -math.pi / 2)
end

-- Invisible barrier at the playable edge; the ground and skyline carry on behind it.
local function buildWalls(ctx: Ctx)
	local B = ctx.B
	local size = B.Half * 2
	local h = B.WallHeight
	local walls = {
		makePart("WallN", Vector3.new(size + 8, h, 4), CFrame.new(0, h / 2, -B.Half - 2), COLOR_WALL, ctx.map, Tags.Wall),
		makePart("WallS", Vector3.new(size + 8, h, 4), CFrame.new(0, h / 2, B.Half + 2), COLOR_WALL, ctx.map, Tags.Wall),
		makePart("WallE", Vector3.new(4, h, size + 8), CFrame.new(B.Half + 2, h / 2, 0), COLOR_WALL, ctx.map, Tags.Wall),
		makePart("WallW", Vector3.new(4, h, size + 8), CFrame.new(-B.Half - 2, h / 2, 0), COLOR_WALL, ctx.map, Tags.Wall),
	}
	for _, wall in walls do
		wall.Transparency = 1
		local curb = makePart("Curb", Vector3.new(math.max(wall.Size.X, 4), 1, math.max(wall.Size.Z, 4)), CFrame.new(wall.Position.X, 0.5, wall.Position.Z), if ctx.theme == "beach" then COLOR_BOARDWALK else COLOR_SIDEWALK, ctx.map)
		curb.Material = if ctx.theme == "beach" then Enum.Material.WoodPlanks else Enum.Material.Concrete
		curb.CanQuery = false
	end
end

-- Background beyond the barrier: skyline towers for the city, a palm fringe and open water for the beach.
local function buildHorizon(ctx: Ctx)
	local B = ctx.B
	local rng = ctx.rng
	local folder = Instance.new("Folder")
	folder.Name = "Skyline"
	folder.Parent = ctx.map
	if ctx.theme == "beach" then
		local radius = B.Half + 40
		for t = -radius, radius, 46 do
			for _, pos in { Vector3.new(t, 0, -radius), Vector3.new(t, 0, radius), Vector3.new(-radius, 0, t), Vector3.new(radius, 0, t) } do
				if rng:NextNumber() < 0.7 then
					buildPalm(folder, rng, pos.X + rng:NextNumber(-12, 12), pos.Z + rng:NextNumber(-12, 12))
				end
			end
		end
		return
	end
	local inner, outer = B.SkylineInner, B.SkylineOuter
	for _, radius in { inner, (inner + outer) / 2, outer } do
		for t = -radius, radius, 52 do
			local jitter = rng:NextNumber(-10, 10)
			for _, pos in { Vector3.new(t + jitter, 0, -radius), Vector3.new(t + jitter, 0, radius), Vector3.new(-radius, 0, t + jitter), Vector3.new(radius, 0, t + jitter) } do
				local w = rng:NextNumber(28, 46)
				local h = rng:NextNumber(B.SkylineMinHeight, B.SkylineMaxHeight)
				local color = SKYLINE_PALETTE[rng:NextInteger(1, #SKYLINE_PALETTE)]
				local tower = makePart("Skyline", Vector3.new(w, h, w), CFrame.new(pos.X, h / 2, pos.Z), color, folder)
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
	-- Never replace an imported (mesh) template; only refresh our own parts build.
	local old = templates:FindFirstChild("YellowCab")
	if old then
		if old:GetAttribute("PartsBuilt") == true then
			old:Destroy()
		else
			return
		end
	end
	local cab = VehicleBuilder.Build("YellowCab")
	cab:SetAttribute("PartsBuilt", true)
	CollectionService:AddTag(cab, Tags.VehicleTemplate)
	cab.Parent = templates
end

function DevBlockout.Generate(mapName: string?): Folder
	local name = mapName or Config.Map.Current
	local mapCfg = (Config.Map :: any)[name]
	if typeof(mapCfg) ~= "table" or not mapCfg.Blockout then
		name = Config.Map.City.DisplayName
		mapCfg = Config.Map.City
	end
	for _, existing in { "Map", "Baseplate", "SpawnLocation" } do
		local inst = workspace:FindFirstChild(existing)
		if inst then
			inst:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("MapName", name)
	local ctx: Ctx = {
		B = mapCfg.Blockout,
		theme = mapCfg.Theme or "city",
		rng = Random.new(mapCfg.Blockout.Seed),
		map = map,
		mapName = name,
	}

	buildGround(ctx)
	buildRoads(ctx)
	local spots = buildCells(ctx)
	buildPoints(ctx, spots)
	buildItemBoxes(ctx)
	buildRamps(ctx)
	buildWalls(ctx)
	buildHorizon(ctx)
	if ctx.theme == "city" then
		buildStreetFurniture(ctx)
	end
	buildVehicleTemplate()

	map.Parent = workspace
	print(string.format("[DevBlockout] %s built: %d parts", name, #map:GetDescendants()))
	return map
end

return DevBlockout
