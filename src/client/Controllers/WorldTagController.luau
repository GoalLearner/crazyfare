--!strict
-- Over-the-roof tags on rival taxis: "$value" and an HP bar while they carry a passenger, visible within
-- Config.Hud.WorldTagDistance, and the name only within WorldTagNameDistance. Driven by the snapshot; attached to the
-- rival's chassis. Under the name, while they carry nobody: their lifetime fares (Config.Hud.LifetimeStat). Also: while you carry a passenger, every waiting passenger's badge, words and bubble are hidden on
-- your screen (you can't pick anyone up anyway; owner 2026-10-27: too many words at once).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

type Tag = { gui: BillboardGui, name: TextLabel, value: TextLabel, lifetime: TextLabel, hp: UI.Bar, model: Model }

local WorldTagController = {}

local tags: { [number]: Tag } = {}
local localPlayer = Players.LocalPlayer
local npcCheckAt = 0

local function findVehicle(userId: number): Model?
	for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerUserId") == userId and inst:IsDescendantOf(workspace) then
			return inst
		end
	end
	return nil
end

local function makeTag(model: Model): Tag?
	local chassis = model.PrimaryPart
	if not chassis then
		return nil
	end
	local gui = UI.New("BillboardGui", {
		Name = "WorldTag",
		Size = UDim2.fromOffset(120, 54),
		StudsOffset = Vector3.new(0, 5, 0),
		AlwaysOnTop = true,
		MaxDistance = Config.Hud.WorldTagDistance,
		LightInfluence = 0,
		Adornee = chassis,
	}, chassis) :: BillboardGui
	local name = UI.Label({ Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = UI.Muted, Font = UI.FontMedium }, gui)
	local value = UI.Label({ Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 26), Text = "", TextColor3 = UI.Cash }, gui)
	local lifetime = UI.Label({ Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 18), Text = "", TextColor3 = Config.Hud.LifetimeColor, Font = UI.FontMedium, TextScaled = false, TextSize = Config.Hud.LifetimeTextSize }, gui)
	local hp = UI.Bar({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(80, 6) }, UI.Danger, gui)
	return { gui = gui, name = name, value = value, lifetime = lifetime, hp = hp, model = model }
end

local function onSnapshot(snapshot: Types.Snapshot)
	local seen: { [number]: boolean } = {}
	for _, p in snapshot.players do
		if p.id == localPlayer.UserId then
			continue
		end
		local tag: Tag? = tags[p.id]
		if tag and not tag.model:IsDescendantOf(workspace) then
			tag.gui:Destroy()
			tags[p.id] = nil
			tag = nil
		end
		if not tag then
			local model = findVehicle(p.id)
			if model then
				tag = makeTag(model)
				if tag then
					tags[p.id] = tag
				end
			end
		end
		if tag then
			seen[p.id] = true
			local loaded = p.fare > 0
			tag.name.Text = if p.bot then "BOT " .. p.name else string.format("%s%s  ·  LV %d", if p.vip then "VIP " else "", p.name, p.level or 1)
			tag.name.TextColor3 = if p.vip then Config.Monetization.VipColor else UI.Muted -- the VIP pass's gold tag
			local camera = workspace.CurrentCamera
			local chassis = tag.model.PrimaryPart
			local close = camera ~= nil and chassis ~= nil and (chassis.Position - camera.CFrame.Position).Magnitude <= Config.Hud.WorldTagNameDistance
			tag.name.Visible = close
			tag.lifetime.Text = if p.lifetime then string.format(Config.Hud.LifetimeLine, UI.Count(p.lifetime)) else ""
			tag.lifetime.Visible = close and not loaded -- the fare's value takes the line while they carry someone
			tag.value.Text = if loaded then UI.Money(p.fare) else ""
			tag.value.TextColor3 = (Config.Fares.Tiers[p.tier] or Config.Fares.Tiers.Green).Color
			tag.hp.back.Visible = loaded
			UI.SetBar(tag.hp, if p.maxHp > 0 then p.hp / p.maxHp else 0)
			tag.gui.Enabled = true
		end
	end
	for id, tag in tags do
		if not seen[id] then
			tag.gui:Destroy()
			tags[id] = nil
		end
	end
end

-- Waiting passengers' billboards (badge, CARPOOL / TICK TOCK, speech) hide from you while you carry someone, and on
-- the title screen (a clean view of the city).
local function hideWaitingPassengers()
	local hideFrom = if State.fare or State.sessionState == "Title" then localPlayer else nil
	for _, model in CollectionService:GetTagged(Config.Tags.Npc) do
		for _, d in model:GetDescendants() do
			if d:IsA("BillboardGui") and d.PlayerToHideFrom ~= hideFrom then
				d.PlayerToHideFrom = hideFrom
			end
		end
	end
end

function WorldTagController.Init()
	State.SnapshotReceived:Connect(onSnapshot)
end

function WorldTagController.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= npcCheckAt then
			npcCheckAt = now + Config.Hud.NpcHideCheckSeconds
			hideWaitingPassengers()
		end
	end)
end

return WorldTagController
