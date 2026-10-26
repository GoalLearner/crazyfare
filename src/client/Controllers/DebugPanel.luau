--!strict
-- Studio-only panel of debug buttons. The server refuses these commands outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = require(script.Parent.Parent.UI)

local DebugPanel = {}

type Button = { label: string, command: string, arg: any }

local BUTTONS: { Button } = {
	{ label = "Tomato", command = "GiveItem", arg = "Tomato" },
	{ label = "Banana", command = "GiveItem", arg = "Banana" },
	{ label = "Nitro", command = "GiveItem", arg = "LemonNitro" },
	{ label = "Oil", command = "GiveItem", arg = "OilSlick" },
	{ label = "Shield", command = "GiveItem", arg = "Shield" },
	{ label = "Seatbelt", command = "GiveItem", arg = "Seatbelt" },
	{ label = "HP -30", command = "Damage", arg = 30 },
	{ label = "HP full", command = "SetHp", arg = 999 },
	{ label = "Bail", command = "Bail", arg = nil },
	{ label = "+$10", command = "AddCash", arg = 10 },
	{ label = "+100 gems", command = "AddGems", arg = 100 },
	{ label = "Spawn NPC", command = "SpawnNpc", arg = nil },
	{ label = "End round", command = "ForceEnd", arg = nil },
}

function DebugPanel.Init()
	local debugRemote = Remotes.Get("Debug")
	local screen = UI.Screen("CrazyFareDebug", 30)
	local panel = UI.Frame({
		Position = UDim2.fromOffset(24, 190),
		Size = UDim2.fromOffset(120, #BUTTONS * 30 + 30),
		BackgroundTransparency = 0.4,
	}, screen)
	UI.Corner(8, panel)
	UI.Label({ Size = UDim2.new(1, 0, 0, 22), Text = "DEBUG", TextColor3 = UI.Muted, Font = UI.FontMedium }, panel)
	local list = UI.Frame({ Position = UDim2.fromOffset(6, 26), Size = UDim2.new(1, -12, 1, -30), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, spec in BUTTONS do
		local button = UI.New("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(40, 40, 50),
			BorderSizePixel = 0,
			Font = UI.FontMedium,
			TextSize = 14,
			TextColor3 = UI.White,
			Text = spec.label,
			AutoButtonColor = true,
		}, list) :: TextButton
		UI.Corner(6, button)
		button.Activated:Connect(function()
			debugRemote:FireServer(spec.command, spec.arg)
		end)
	end
end

function DebugPanel.Start() end

return DebugPanel
