--!strict
-- Every sound in the game, keyed by Config.Sounds.Ids. An id of 0 means "no asset yet" and plays nothing, so the
-- hooks are wired now and come alive the moment the owner pastes asset ids into Config.
-- Music rotates through Config.Sounds.Playlist; callout stings (combo, Golden Fare, new best, win) dip it briefly.
-- Two SoundGroups carry the OPTIONS volumes: the music, and every other sound (Config.Options).

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)

local SoundController = {}

local sounds: { [string]: Sound } = {}
local engine: Sound? = nil
local drift: Sound? = nil
local boostLoop: Sound? = nil
local music: Sound? = nil
local stings: { [string]: Sound } = {}
local track = 0 -- index into Config.Sounds.Playlist
local lastPhase = ""
local wasBoosting = false
local lastBeep = -1
local musicGroup: SoundGroup
local sfxGroup: SoundGroup

local function make(name: string, id: number, looped: boolean, volume: number): Sound?
	if id <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Looped = looped
	sound.Volume = volume
	sound.SoundGroup = if name == "Music" then musicGroup else sfxGroup
	sound.Parent = SoundService
	return sound
end

local function play(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

-- Plays its own copy of a sound, so quick repeats overlap instead of restarting (coins, counter ticks).
function SoundController.PlayOneShot(name: string, pitch: number?)
	local source = sounds[name]
	if not source then
		return
	end
	local sound = source:Clone()
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- The next track in the playlist, once through; when it ends the one after starts.
local function playNextTrack()
	local list = Config.Sounds.Playlist
	local sound = music
	if #list == 0 or not sound then
		return
	end
	track = track % #list + 1
	sound.SoundId = "rbxassetid://" .. tostring(list[track])
	sound.TimePosition = 0
	sound:Play()
end

-- A callout sting over the music, which dips under it and comes back.
local function sting(name: string)
	local sound = stings[name]
	if not sound then
		return
	end
	sound:Play()
	local m = music
	if m then
		local full = Config.Sounds.MusicVolume
		m.Volume = full * Config.Sounds.MusicDuck
		TweenService:Create(m, TweenInfo.new(Config.Sounds.MusicDuckSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = full }):Play()
	end
end

local function onFare(payload: Types.FareEventPayload)
	if payload.kind == "Stunt" then
		if (payload.amount or 0) > 0 then
			-- one coin per paid stunt; pitch climbs with the chain
			SoundController.PlayOneShot("Coin", 1 + math.max(0, (payload.chain or 1) - 1) * Config.Stunts.CoinPitchPerChain)
		end
		if table.find(Config.Sounds.ComboStingChains, payload.chain or 0) then
			sting("Combo")
		end
	elseif payload.kind == "Cash" then
		SoundController.PlayOneShot("Coin", 1.25)
	elseif payload.kind == "Request" and payload.done then
		sting(Config.Chaos.Requests.Sting)
	elseif payload.kind == "Claimed" then
		play("Pickup")
		play("Board")
	elseif payload.kind == "Delivered" then
		play("Deliver")
		play("Thanks")
		if payload.grade then
			task.delay(Config.Hud.StampDelay, play, "Stamp")
		end
	elseif payload.kind == "Bailed" then
		play("Bail")
		play("Angry")
	elseif payload.kind == "Hurt" and (payload.source == "crash" or payload.source == "pedestrian") then
		play("Crash")
	elseif payload.kind == "Golden" then
		-- a shimmer of coins: three quick pings climbing, under the chime
		sting("Golden")
		for i = 0, 2 do
			task.delay(i * 0.09, SoundController.PlayOneShot, "Coin", 1.3 + i * 0.15)
		end
	end
end

local function onItem(payload: Types.ItemEventPayload)
	if payload.kind == "Splat" then
		play("Splat")
	elseif payload.kind == "Spinout" then
		play("Spinout")
	elseif payload.kind == "Rammed" or payload.kind == "Ram" then
		play("Crash")
	end -- Lemon Nitro's whoosh plays when the boost starts (Heartbeat), like Shift and Dash
end

local frenzyOn = false
local eventHeard: string? = nil

-- Frenzy: the music speeds up (pitch and tempo) and a sting marks the start.
local function setFrenzy(on: boolean)
	if on == frenzyOn then
		return
	end
	frenzyOn = on
	local m = music
	if m then
		m.PlaybackSpeed = if on then Config.Chaos.Frenzy.MusicSpeed else 1
	end
	if on then
		sting(Config.Chaos.Frenzy.Sting)
	end
end

local function onRound(payload: Types.RoundStatePayload)
	setFrenzy(payload.frenzy == true and payload.phase == "Playing")
	local event = if payload.phase == "Playing" then payload.event else nil
	if event and event ~= eventHeard then
		sting(Config.Chaos.Events.Sting)
	end
	eventHeard = event
	if payload.phase == lastPhase then
		return
	end
	lastPhase = payload.phase
	lastBeep = -1
	if payload.phase == "Countdown" then
		play("Countdown")
	elseif payload.phase == "Playing" then
		play("Go")
	elseif payload.phase == "RoundEnd" then
		play("RoundEnd")
	elseif payload.phase == "MatchEnd" then
		-- your own result picks the sting: a new best, a win (beating someone), or the plain fanfare
		local results: { Types.PodiumEntry } = payload.results or {}
		local me = Players.LocalPlayer.UserId
		local mine: Types.PodiumEntry? = nil
		for _, entry in results do
			if entry.id == me then
				mine = entry
			end
		end
		local first = results[1]
		if mine and mine.newBest then
			sting("NewBest")
		elseif first and first.id == me and #results > 1 and payload.mode ~= "Arcade" then
			sting("Win")
		else
			play("RoundEnd")
		end
	end
end

local function onHonk()
	local profile = State.profile
	if profile and profile.vip and sounds.HonkVip then
		play("HonkVip")
	else
		play("Honk")
	end
end

-- OPTIONS: each volume is a step (Config.Options.VolumeSteps) times the base volumes set on each sound.
local function applySettings()
	local steps = Config.Options.VolumeSteps
	musicGroup.Volume = steps[State.settings.music] or 1
	sfxGroup.Volume = steps[State.settings.sfx] or 1
end

function SoundController.Init()
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = Config.Options.MusicGroup
	musicGroup.Parent = SoundService
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = Config.Options.SfxGroup
	sfxGroup.Parent = SoundService
	applySettings()
	State.SettingsChanged:Connect(applySettings)
	local ids = Config.Sounds.Ids
	local volume = Config.Sounds.Volume
	for name, id in ids do
		if name ~= "Engine" and name ~= "Drift" and name ~= "BoostLoop" then
			local sound = make(name, id, false, volume)
			if sound then
				sounds[name] = sound
			end
		end
	end
	for name, id in Config.Sounds.PassengerLines do
		local sound = make("Voice" .. name, id, false, volume)
		if sound then
			sounds[name] = sound
		end
	end
	engine = make("Engine", ids.Engine, true, volume * 0.6)
	drift = make("Drift", ids.Drift, true, volume * 0.8)
	boostLoop = make("BoostLoop", ids.BoostLoop or 0, true, volume * 0.7)
	if boostLoop then
		local region = Config.Sounds.BoostLoopRegion
		boostLoop.PlaybackRegionsEnabled = true
		boostLoop.PlaybackRegion = NumberRange.new(region[1], region[2])
		boostLoop.PlaybackSpeed = Config.Sounds.BoostLoopPitch
	end
	for name, id in Config.Sounds.Stings do
		local sound = make("Sting" .. name, id, false, Config.Sounds.StingVolume)
		if sound then
			stings[name] = sound
		end
	end
	local playlist = Config.Sounds.Playlist
	if #playlist > 0 then
		local sound = make("Music", playlist[1], false, Config.Sounds.MusicVolume) :: Sound
		music = sound
		track = math.random(1, #playlist) - 1
		sound.Ended:Connect(playNextTrack)
		playNextTrack()
	end

	State.FareEvent:Connect(onFare)
	State.ItemEvent:Connect(onItem)
	State.RoundChanged:Connect(onRound)
	State.Honk:Connect(onHonk)
	-- post-match drops: a chime for an Epic or better, a coin otherwise, when the prize shows (Config.Drops.Reveal); a
	-- Mythic pull anywhere in the server rings for everyone
	State.DropEvent:Connect(function(payload: Types.DropEventPayload)
		local r = Config.Drops.Reveal
		local at = r.Delay + r.DropSeconds + r.ShakeSeconds
		if payload.kind == "Mythic" then
			task.delay(at, sting, "Mythic")
		elseif payload.kind == "Drop" then
			local rarity = table.find(Config.Drops.Rarities, payload.rarity or "") or 1
			if rarity >= (table.find(Config.Drops.Rarities, "Epic") or 3) and payload.rarity ~= "Mythic" then
				task.delay(at, sting, "DropReveal")
			elseif payload.rarity ~= "Mythic" then
				task.delay(at, SoundController.PlayOneShot, "Coin", 1.1)
			end
		end
	end)
	State.Hopped:Connect(function()
		SoundController.PlayOneShot(Config.Chaos.Hop.Sound, Config.Chaos.Hop.SoundPitch)
	end)
	State.Landed:Connect(function(airSeconds: number)
		SoundController.PlayOneShot("Land", math.clamp(1.15 - airSeconds * 0.15, 0.8, 1.15)) -- bigger air, deeper thump
	end)
end

function SoundController.Start()
	RunService.Heartbeat:Connect(function()
		local eng = engine
		if eng then
			local frac = math.clamp(State.speed / State.stats.TopSpeed, 0, 1.2)
			eng.PlaybackSpeed = 0.7 + frac * 0.8
			if State.chassis and not eng.IsPlaying then
				eng:Play()
			end
		end
		local dr = drift
		if dr then
			if State.drifting and not dr.IsPlaying then
				dr:Play()
			elseif not State.drifting and dr.IsPlaying then
				dr:Stop()
			end
		end
		-- Boost (Shift, Lemon Nitro, Dash): a whoosh as it lights, the flame roar while it lasts
		local boosting = State.boosting
		if boosting and not wasBoosting then
			SoundController.PlayOneShot("Boost", if State.dashing then 1.2 else 1)
		end
		wasBoosting = boosting
		-- the last seconds of the clock tick down out loud
		local round = State.round
		if round and State.GetPhase() == "Playing" and round.endsAt > 0 then
			local n = math.ceil(round.endsAt - workspace:GetServerTimeNow())
			if n >= 1 and n <= Config.Sounds.FinalBeeps and n ~= lastBeep then
				lastBeep = n
				SoundController.PlayOneShot("Countdown", Config.Sounds.FinalBeepPitch)
			elseif n > Config.Sounds.FinalBeeps then
				lastBeep = -1
			end
		end
		local loop = boostLoop
		if loop then
			if boosting and not loop.IsPlaying then
				loop:Play()
			elseif not boosting and loop.IsPlaying then
				loop:Stop()
			end
		end
	end)
end

return SoundController
