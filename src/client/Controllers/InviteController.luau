--!strict
-- INVITE in the side stack (under ARCADE), between matches: Roblox's own friend-invite prompt (SocialService). Someone
-- new who joins through it pays you both once (SessionService). Hidden where invites can't be sent and in Arcade (a
-- server of your own). Config.Session.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local InviteController = {}

local button: TextButton
local canInvite = false

local function refresh()
	local round = State.round
	local phase = State.GetPhase()
	local between = phase == "Waiting" or phase == "PreCountdown" or phase == "MatchEnd"
	button.Visible = canInvite and between and not (round ~= nil and round.mode == "Arcade")
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
	button.Activated:Connect(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = Config.Session.InvitePrompt
		local ok, err = pcall(function()
			SocialService:PromptGameInvite(Players.LocalPlayer, options)
		end)
		if not ok and RunService:IsStudio() then
			warn("[InviteController] " .. tostring(err))
		end
	end)
	State.RoundChanged:Connect(refresh)
end

function InviteController.Start()
	task.spawn(function()
		local ok, result = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		canInvite = (ok and result == true) or RunService:IsStudio() -- Studio shows it so the layout can be checked
		refresh()
	end)
end

return InviteController
