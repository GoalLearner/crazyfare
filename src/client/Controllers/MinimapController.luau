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
end

local function ensureNpcDot(id: number): Frame
	local existing = npcDots[id]
	if existing then
		return existing
	end
	local dot = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 0, ZIndex = 3 }, map)
	UI.Corner(4, dot)
	npcDots[id] = dot
	return dot
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
		dot.BackgroundColor3 = tierColor(npc.tier)
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
