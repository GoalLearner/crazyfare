--!strict
-- Whole-map minimap (top-right): roads from the blockout spec, NPC dots by tier, every rival with its fare $
-- and a mini HP bar (grey when empty), your own arrow, your destination. Reads only the 10 Hz snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

type RivalMarker = { frame: Frame, label: TextLabel, hp: Frame }

local MinimapController = {}

local B = Config.Map.City.Blockout
local roadStrips: { Frame } = {}
local currentMap = ""
local SIZE = Config.Hud.MinimapSize
local map: Frame
local selfArrow: TextLabel
local destMarker: Frame
local npcDots: { [number]: Frame } = {}
local rivals: { [number]: RivalMarker } = {}
local localPlayer = Players.LocalPlayer

local function toMap(x: number, z: number): UDim2
	local px = (x + B.Half) / (2 * B.Half) * SIZE
	local py = (z + B.Half) / (2 * B.Half) * SIZE
	return UDim2.fromOffset(math.round(px), math.round(py))
end

local function tierColor(tier: string): Color3
	local def = Config.Fares.Tiers[tier]
	return if def then def.Color else UI.Muted
end

local function build()
	local screen = UI.Screen("CrazyFareMinimap", 5)
	map = UI.Frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(26, 34, 26),
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
	}, screen)
	UI.Corner(10, map)
	UI.Stroke(Color3.fromRGB(70, 70, 80), 2, map)


	destMarker = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, map)
	UI.Corner(7, destMarker)
	UI.Stroke(UI.Accent, 3, destMarker)

	selfArrow = UI.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Text = "▲", TextColor3 = UI.White, ZIndex = 6 }, map)
end


-- The city's set pieces (Config.MapFeatures), drawn over the roads: alleys and the park path as roads, the jump lane
-- and humps in ramp orange, the hill a lighter road, the tunnel darker. A strip from (x0, z0) to (x1, z1), `width` studs.
local ROAD = Color3.fromRGB(70, 70, 76)
local RAMP = Color3.fromRGB(230, 120, 40)
local HILL = Color3.fromRGB(105, 105, 112)
local TUNNEL = Color3.fromRGB(34, 34, 40)

local function addStrip(x0: number, z0: number, x1: number, z1: number, width: number, color: Color3, z: number)
	local scale = SIZE / (2 * B.Half)
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	local frame = UI.Frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap((x0 + x1) / 2, (z0 + z1) / 2),
		Size = UDim2.fromOffset(math.max(2, math.round(length * scale)), math.max(2, math.round(width * scale))),
		Rotation = math.deg(math.atan2(dz, dx)),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = z,
	}, map)
	table.insert(roadStrips, frame)
end

local function drawFeatures(f: Config.MapFeatures?)
	if not f then
		return
	end
	local half = B.CellSize / 2
	for _, alley in f.Alleys do
		addStrip(alley.X, alley.Z - half, alley.X, alley.Z + half, f.AlleyWidth, ROAD, 1)
	end
	local park = f.DiagonalPark
	addStrip(park.X + half, park.Z - half, park.X - half, park.Z + half, park.Width, ROAD, 1)
	local runout = f.Runout
	addStrip(runout.X, runout.Z - half, runout.X, runout.Z + half, runout.Width, ROAD, 1)
	local jump = f.JumpBlock
	addStrip(jump.X, jump.Z - half, jump.X, jump.Z + half, jump.Width, ROAD, 1)
	addStrip(jump.X, jump.Z + jump.Dir * jump.LaunchStart, jump.X, jump.Z + jump.Dir * jump.LandEnd, jump.Width, RAMP, 2)
	local hill = f.Hill
	addStrip(hill.X, hill.ZFrom, hill.X, hill.ZTo, B.RoadWidth, HILL, 2)
	for _, hump in f.BigHumps do
		local axis = CFrame.Angles(0, math.rad(hump.Yaw), 0).LookVector * (hump.Length / 2)
		addStrip(hump.X - axis.X, hump.Z - axis.Z, hump.X + axis.X, hump.Z + axis.Z, hump.Width, RAMP, 2)
	end
	for _, pad in f.BoostPads do
		local axis = CFrame.Angles(0, math.rad(pad.Yaw), 0).LookVector * (pad.Length / 2)
		addStrip(pad.X - axis.X, pad.Z - axis.Z, pad.X + axis.X, pad.Z + axis.Z, pad.Width, Color3.fromRGB(60, 230, 255), 3)
	end
	local tunnel = f.Tunnel
	addStrip(tunnel.X, tunnel.ZFrom, tunnel.X, tunnel.ZTo, B.RoadWidth + 4, TUNNEL, 2)
end

local function drawRoads(mapName: string)
	local mapCfg = (Config.Map :: any)[mapName]
	if typeof(mapCfg) ~= "table" or not mapCfg.Blockout then
		mapCfg = Config.Map.City
	end
	B = mapCfg.Blockout
	currentMap = mapName
	for _, strip in roadStrips do
		strip:Destroy()
	end
	roadStrips = {}
	map.BackgroundColor3 = if mapCfg.Theme == "beach" then Color3.fromRGB(60, 54, 34) else Color3.fromRGB(26, 34, 26)
	local scale = SIZE / (2 * B.Half)
	local roadPx = math.max(2, math.round(B.RoadWidth * scale))
	for _, r in B.RoadCoords do
		local c = (r + B.Half) * scale
		table.insert(roadStrips, UI.Frame({ Position = UDim2.fromOffset(math.round(c - roadPx / 2), 0), Size = UDim2.fromOffset(roadPx, SIZE), BackgroundColor3 = Color3.fromRGB(70, 70, 76), BackgroundTransparency = 0, ZIndex = 1 }, map))
		table.insert(roadStrips, UI.Frame({ Position = UDim2.fromOffset(0, math.round(c - roadPx / 2)), Size = UDim2.fromOffset(SIZE, roadPx), BackgroundColor3 = Color3.fromRGB(70, 70, 76), BackgroundTransparency = 0, ZIndex = 1 }, map))
	end
	drawFeatures(B.Features)
end

local function ensureNpcDot(id: number): Frame
	local existing = npcDots[id]
	if existing then
		return existing
	end
	local dot = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 0, ZIndex = 3 }, map)
	UI.Corner(4, dot)
	UI.Stroke(UI.White, 0, dot)
	npcDots[id] = dot
	return dot
end

-- Passenger kinds read at a glance: regulars are round, Thrill Seekers diamonds, Nervous ones squares; the Golden Fare
-- is a big gold dot with a white rim.
local function styleNpcDot(dot: Frame, npc: Types.NpcSnap)
	local corner = dot:FindFirstChildOfClass("UICorner")
	local stroke = dot:FindFirstChildOfClass("UIStroke")
	local size = if npc.golden then 13 else 8
	dot.Size = UDim2.fromOffset(size, size)
	dot.Rotation = if npc.kind == "ThrillSeeker" and not npc.golden then 45 else 0
	if corner then
		corner.CornerRadius = UDim.new(0, if npc.golden or npc.kind == "Regular" then size / 2 else 1)
	end
	if stroke then
		stroke.Thickness = if npc.golden then 2 else 0
	end
	dot.BackgroundColor3 = if npc.golden then Config.Golden.Color else tierColor(npc.tier)
	dot.ZIndex = if npc.golden then 4 else 3
end

local function ensureRival(id: number): RivalMarker
	local existing = rivals[id]
	if existing then
		return existing
	end
	local frame = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0, ZIndex = 5 }, map)
	UI.Corner(3, frame)
	UI.Stroke(UI.Black, 1, frame)
	local label = UI.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(44, 14), Text = "", ZIndex = 6 }, frame)
	local hpBack = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(18, 3), BackgroundColor3 = UI.Black, BackgroundTransparency = 0.2, ZIndex = 6 }, frame)
	local hp = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Danger, BackgroundTransparency = 0, ZIndex = 7 }, hpBack)
	local marker: RivalMarker = { frame = frame, label = label, hp = hp }
	rivals[id] = marker
	return marker
end

local function onSnapshot(snapshot: Types.Snapshot)
	-- NPCs
	local seenNpc: { [number]: boolean } = {}
	for _, npc in snapshot.npcs do
		seenNpc[npc.id] = true
		local dot = ensureNpcDot(npc.id)
		dot.Position = toMap(npc.x, npc.z)
		styleNpcDot(dot, npc)
		dot.BackgroundTransparency = if npc.state == 0 then 0 else 0.65
	end
	for id, dot in npcDots do
		if not seenNpc[id] then
			dot:Destroy()
			npcDots[id] = nil
		end
	end

	-- Taxis
	local seenRival: { [number]: boolean } = {}
	for _, p in snapshot.players do
		if p.id == localPlayer.UserId then
			selfArrow.Position = toMap(p.x, p.z)
			selfArrow.Rotation = math.deg(p.yaw)
			continue
		end
		seenRival[p.id] = true
		local marker = ensureRival(p.id)
		marker.frame.Position = toMap(p.x, p.z)
		local loaded = p.fare > 0
		marker.frame.BackgroundColor3 = if loaded then tierColor(p.tier) else Color3.fromRGB(120, 120, 130)
		marker.label.Text = if loaded then UI.Money(p.fare) else ""
		local hpParent = marker.hp.Parent
		if hpParent and hpParent:IsA("Frame") then
			hpParent.Visible = loaded
		end
		marker.hp.Size = UDim2.fromScale(if p.maxHp > 0 then p.hp / p.maxHp else 0, 1)
	end
	for id, marker in rivals do
		if not seenRival[id] then
			marker.frame:Destroy()
			rivals[id] = nil
		end
	end

	-- Destination
	local fare = State.fare
	if fare then
		destMarker.Visible = true
		destMarker.Position = toMap(fare.destination.X, fare.destination.Z)
	else
		destMarker.Visible = false
	end
end

function MinimapController.Init()
	build()
	drawRoads(Config.Map.Current)
	State.SnapshotReceived:Connect(onSnapshot)
	State.RoundChanged:Connect(function(payload: Types.RoundStatePayload)
		if payload.map and payload.map ~= currentMap then
			drawRoads(payload.map)
		end
	end)
end

function MinimapController.Start() end

return MinimapController
