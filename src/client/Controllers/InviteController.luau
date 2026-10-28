--!strict
-- INVITE in the side stack (under ARCADE), between matches and all the time in the Taxi Depot: Roblox's own
-- friend-invite prompt (Invite). Hidden where invites can't be sent and in Arcade (a server of your own).
-- Config.Session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local Invite = require(script.Parent.Parent.Invite)

local InviteController = {}

local button: TextButton

local function refresh()
	local round = State.round
	local phase = State.GetPhase()
	local between = phase == "Waiting" or phase == "PreCountdown" or phase == "MatchEnd" or State.sessionState == "Depot"
	button.Visible = Invite.CanInvite() and between and not (round ~= nil and round.mode == "Arcade")
end

function InviteController.Init()
	local screen = UI.Screen("CrazyFareInvite", 16)
	button = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + (34 + 8) * 4),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(150, 80, 210),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = Config.Session.InviteButton,
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, button)
	button.Activated:Connect(Invite.Prompt)
	State.RoundChanged:Connect(refresh)
	State.SessionChanged:Connect(refresh)
	Invite.Known:Connect(refresh)
end

function InviteController.Start() end

return InviteController
