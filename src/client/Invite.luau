--!strict
-- Roblox's friend-invite prompt (SocialService), shared by the side stack's INVITE, the podium and the depot. Someone
-- new who joins through it pays you both once (SessionService); a friend who follows you in gets the next free seat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Invite = {}

local known: Signal.Signal<nil> = Signal.new()
Invite.Known = known -- fires once Roblox has said whether invites can be sent from here

local canInvite = RunService:IsStudio() -- Studio shows the buttons so the layout can be checked

task.spawn(function()
	local ok, result = pcall(function()
		return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
	end)
	canInvite = (ok and result == true) or RunService:IsStudio()
	known:Fire()
end)

function Invite.CanInvite(): boolean
	return canInvite
end

function Invite.Prompt()
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = Config.Session.InvitePrompt
	local ok, err = pcall(function()
		SocialService:PromptGameInvite(Players.LocalPlayer, options)
	end)
	if not ok and RunService:IsStudio() then
		warn("[Invite] " .. tostring(err))
	end
end

return Invite
