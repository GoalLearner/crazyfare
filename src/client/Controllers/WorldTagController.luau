--!strict
-- Over-the-roof tags on rival taxis: name, "$value" and an HP bar while they carry a passenger,
-- visible within Config.Hud.WorldTagDistance. Driven by the snapshot; attached to the rival's chassis.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

type Tag = { gui: BillboardGui, name: TextLabel, value: TextLabel, hp: UI.Bar, model: Model }

local WorldTagController = {}

local tags: { [number]: Tag } = {}
local localPlayer = Players.LocalPlayer

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
	local hp = UI.Bar({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(80, 6) }, UI.Danger, gui)
	return { gui = gui, name = name, value = value, hp = hp, model = model }
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
			tag.name.Text = p.name
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

function WorldTagController.Init()
	State.SnapshotReceived:Connect(onSnapshot)
end

function WorldTagController.Start() end

return WorldTagController
