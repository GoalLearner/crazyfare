--!strict
-- CREDITS from the title screen (Config.Title.Credits): who made the game (its Roblox creator, looked up once) and the
-- art and audio it uses.

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(script.Parent.Parent.UI)

local CreditsController = {}

local panel: Frame
local creatorLabels: { { label: TextLabel, format: string } } = {}
local isOpen = false
local creatorAsked = false

-- The game's creator by name, from Roblox (a user or a group); a fallback in an unpublished Studio place.
local function fillCreator()
	if creatorAsked then
		return
	end
	creatorAsked = true
	task.spawn(function()
		local name = Config.Title.CreatorFallback
		local ok, found = pcall(function(): string?
			if game.CreatorId <= 0 then
				return nil
			elseif game.CreatorType == Enum.CreatorType.Group then
				return (GroupService:GetGroupInfoAsync(game.CreatorId) :: any).Name
			end
			return Players:GetNameFromUserIdAsync(game.CreatorId)
		end)
		if ok and typeof(found) == "string" and found ~= "" then
			name = found
		end
		for _, entry in creatorLabels do
			entry.label.Text = string.format(entry.format, name)
		end
	end)
end

function CreditsController.Open()
	isOpen = true
	panel.Visible = true
	fillCreator()
end

function CreditsController.Close()
	isOpen = false
	panel.Visible = false
end

function CreditsController.IsOpen(): boolean
	return isOpen
end

local function build()
	local screen = UI.Screen("CrazyFareCredits", 45)
	screen:SetAttribute(Config.Title.KeepAttribute, true) -- opened from the title screen
	local lines = Config.Title.Credits
	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 84 + #lines * 54), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(240, 36), Text = Config.Title.CreditsTitle, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local close = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(80, 50, 50),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "X",
	}, panel) :: TextButton
	UI.Corner(8, close)
	close.Activated:Connect(CreditsController.Close)

	local list = UI.Frame({ Position = UDim2.fromOffset(24, 66), Size = UDim2.new(1, -48, 0, #lines * 54), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, entry in lines do
		local block = UI.Frame({ Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = i }, list)
		local heading, line = entry[1], entry[2]
		UI.Label({ Size = UDim2.new(1, 0, 0, if line == "" then 30 else 18), Text = heading, TextColor3 = if line == "" then UI.Warn else UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, block)
		if line ~= "" then
			local label = UI.Label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 24), Text = string.format(line, Config.Title.CreatorFallback), TextXAlignment = Enum.TextXAlignment.Left }, block)
			if string.find(line, "%%s") then
				table.insert(creatorLabels, { label = label, format = line })
			end
		end
	end
end

function CreditsController.Init()
	build()
end

function CreditsController.Start() end

return CreditsController
