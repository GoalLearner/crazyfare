--!strict
-- The ARCADE / RACE button in the side stack (under SHOP), shown only between matches: ARCADE asks for a solo clock run,
-- RACE (inside Arcade) goes back to racing. The server decides what happens (a reserved server live, a switch in
-- Studio). Config.Arcade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local ArcadeController = {}

local button: TextButton
local mode = "Race"

local function onRound(payload: Types.RoundStatePayload)
	mode = payload.mode or "Race"
	local between = payload.phase == "Waiting" or payload.phase == "PreCountdown" or payload.phase == "MatchEnd"
	button.Visible = between
	button.Text = if mode == "Arcade" then Config.Arcade.LeaveButton else Config.Arcade.Button
	button.BackgroundColor3 = if mode == "Arcade" then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(200, 120, 40)
end

function ArcadeController.Init()
	local screen = UI.Screen("CrazyFareArcade", 16)
	button = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + (34 + 8) * 3),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(200, 120, 40),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = Config.Arcade.Button,
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, button)
	button.Activated:Connect(function()
		Remotes.Get("ArcadeRequest"):FireServer(if mode == "Arcade" then "leave" else "start")
	end)
	State.RoundChanged:Connect(onRound)
end

function ArcadeController.Start() end

return ArcadeController
