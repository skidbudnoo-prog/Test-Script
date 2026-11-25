
--==================================================
-- MULTI-ACCOUNT FARMING SYSTEM
-- HEARTBEAT HEALTH DETECTION
-- MAIN SKILL 4 / ALT RESET CYCLE
--==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Farm] LocalPlayer unavailable")
    return
end

local SharedEnv = (typeof(getgenv) == "function" and getgenv()) or _G

--==================================================
-- CONFIGURATION
--==================================================

local function CleanUsername(value)
    if typeof(value) ~= "string" then
        return nil
    end

    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local MainAccount = CleanUsername(SharedEnv.MainAccount) or ""

local AltAccounts = {}
local SeenAccounts = {}

if typeof(SharedEnv.AltAccounts) == "table" then
    for _, username in pairs(SharedEnv.AltAccounts) do
        local cleaned = CleanUsername(username)

        if cleaned and not SeenAccounts[cleaned:lower()] then
            SeenAccounts[cleaned:lower()] = true
            table.insert(AltAccounts, cleaned)
        end
    end
end

local Config = {
    MainAccount = MainAccount,
    AltAccounts = AltAccounts,

    MainPosition = Vector3.new(364, 440, 433),
    AltPosition = Vector3.new(361, 440, 428),

    DetectionDistance = 15,
    CharacterAvailabilityTimeout = 3,

    DisableAltCollisions = true,

    AutoEmoteAndSwitch = true,
    AutoScriptURL = "https://raw.githubusercontent.com/REES-oss/Loaders/refs/heads/main/auto.luau",

    KillCounter = true,
    PositionCheckInterval = 0.5,

    SkillKey = Enum.KeyCode.Four,
    SkillWaitBeforeReset = 1.5,
    AltCooldownWait = 3,
    KeyPressDuration = 0.12,
}

--==================================================
-- ACCOUNT IDENTIFICATION
--==================================================

local function FindPlayer(username)
    if not username or username == "" then
        return nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower() == username:lower() then
            return player
        end
    end

    return nil
end

local IsMain = MainAccount ~= ""
    and LocalPlayer.Name:lower() == MainAccount:lower()

local IsAlt = false

for _, username in ipairs(AltAccounts) do
    if LocalPlayer.Name:lower() == username:lower() then
        IsAlt = true
        break
    end
end

if not IsMain and not IsAlt then
    warn("[Farm] Account not configured:", LocalPlayer.Name)
    return
end

local AssignedPosition = IsMain
    and Config.MainPosition
    or Config.AltPosition

print("[Farm] Account:", LocalPlayer.Name)
print("[Farm] Role:", IsMain and "MAIN" or "ALT")

--==================================================
-- CHARACTER STATE
--==================================================

local Character
local Humanoid
local RootPart

local CharacterReady = false
local CharacterGeneration = 0

local function GetCharacterComponents()
    local char = LocalPlayer.Character
    if not char then
        return nil
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end

    return char, humanoid, root
end

local function WaitForCharacterReady(generation)
    while generation == CharacterGeneration do
        local char, humanoid, root = GetCharacterComponents()

        if char and humanoid and root and char == LocalPlayer.Character then
            Character = char
            Humanoid = humanoid
            RootPart = root
            CharacterReady = true
            return true
        end

        RunService.Heartbeat:Wait()
    end

    return false
end

local function WaitForLocalCharacter(timeout)
    local started = os.clock()

    repeat
        if CharacterReady
            and Character == LocalPlayer.Character
            and Humanoid
            and RootPart
            and Humanoid.Health > 0
        then
            return true
        end

        RunService.Heartbeat:Wait()
    until os.clock() - started >= timeout

    return false
end

--==================================================
-- RESET FUNCTION
--==================================================

local function RequestLocalReset()
    local character = LocalPlayer.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    print("[Farm] Reset requested:", LocalPlayer.Name)

    local success, err = pcall(function()
        humanoid.Health = 0
    end)

    if not success then
        warn("[Farm] Reset request failed:", err)
        return false
    end

    return true
end

--==================================================
-- MAIN: SKILL 4 INPUT
--==================================================

local MainCycleBusy = false
local MainCycleUsed = false

local function PressSkill4()
    if not IsMain then
        return false
    end

    local success, err = pcall(function()
        VirtualInputManager:SendKeyEvent(
            true,
            Config.SkillKey,
            false,
            game
        )

        task.wait(Config.KeyPressDuration)

        VirtualInputManager:SendKeyEvent(
            false,
            Config.SkillKey,
            false,
            game
        )
    end)

    if not success then
        warn("[Farm] Skill 4 input failed:", err)
        return false
    end

    print("[Farm] MAIN PRESSED SKILL 4")
    return true
end

local function StartMainCycle()
    if not IsMain or MainCycleBusy or MainCycleUsed then
        return
    end

    if not WaitForLocalCharacter(2) then
        warn("[Farm] Main is not alive; cannot activate Skill 4")
        return
    end

    MainCycleBusy = true
    MainCycleUsed = true

    local cycleCharacter = LocalPlayer.Character

    task.spawn(function()
        print("[Farm] ALT HEALTH REACHED ZERO")
        print("[Farm] ACTIVATING SKILL 4 NOW")

        PressSkill4()

        task.wait(Config.SkillWaitBeforeReset)

        if LocalPlayer.Character == cycleCharacter
            and CharacterReady
            and Humanoid
            and Humanoid.Health > 0
        then
            print("[Farm] Main resetting after 1.5 seconds")
            RequestLocalReset()
        else
            warn("[Farm] Main character changed before reset")
        end

        MainCycleBusy = false
    end)
end

--==================================================
-- ALT COLLISION HANDLING
--==================================================

local CollisionConnection

local function DisableCollisions(char)
    if not IsAlt or not Config.DisableAltCollisions then
        return
    end

    if CollisionConnection then
        CollisionConnection:Disconnect()
        CollisionConnection = nil
    end

    local function ApplyCollision(part)
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end

    for _, descendant in ipairs(char:GetDescendants()) do
        ApplyCollision(descendant)
    end

    CollisionConnection = char.DescendantAdded:Connect(ApplyCollision)
end

--==================================================
-- CHARACTER SPAWN HANDLING
--==================================================

local function HandleCharacterSpawn(char)
    CharacterGeneration += 1
    local generation = CharacterGeneration

    CharacterReady = false
    Character = char
    Humanoid = nil
    RootPart = nil

    if CollisionConnection then
        CollisionConnection:Disconnect()
        CollisionConnection = nil
    end

    task.spawn(function()
        if not WaitForCharacterReady(generation) then
            return
        end

        if generation ~= CharacterGeneration then
            return
        end

        print("[Farm] Character ready:", LocalPlayer.Name)

        if IsAlt then
            DisableCollisions(Character)
        end

        if RootPart then
            RootPart.CFrame = CFrame.new(AssignedPosition)
        end

        if IsMain then
            MainCycleUsed = false
            print("[Farm] Main ready for next cycle")
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(HandleCharacterSpawn)

LocalPlayer.CharacterRemoving:Connect(function()
    CharacterGeneration += 1
    CharacterReady = false

    Character = nil
    Humanoid = nil
    RootPart = nil

    if CollisionConnection then
        CollisionConnection:Disconnect()
        CollisionConnection = nil
    end
end)

if LocalPlayer.Character then
    HandleCharacterSpawn(LocalPlayer.Character)
end

--==================================================
-- KILL COUNTER
--==================================================

if Config.KillCounter then
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")

        local oldGui = playerGui:FindFirstChild("FarmKillCounter")
        if oldGui then
            oldGui:Destroy()
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "FarmKillCounter"
        gui.ResetOnSpawn = false
        gui.Parent = playerGui

        local label = Instance.new("TextLabel")
        label.Name = "KillCounter"
        label.AnchorPoint = Vector2.new(1, 0)
        label.Position = UDim2.new(1, -20, 0, 20)
        label.Size = UDim2.new(0, 220, 0, 35)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextSize = 18
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Right
        label.Text = "Farmed Kills: 0"
        label.Parent = gui

        local kills

        while not kills do
            local stats = LocalPlayer:FindFirstChild("leaderstats")
            kills = stats and stats:FindFirstChild("Kills")
            RunService.Heartbeat:Wait()
        end

        local startingKills = kills.Value

        local function UpdateCounter()
            label.Text = "Farmed Kills: "
                .. tostring(math.max(0, kills.Value - startingKills))
        end

        UpdateCounter()
        kills:GetPropertyChangedSignal("Value"):Connect(UpdateCounter)
    end)
end

--==================================================
-- AUTOMATIC EMOTE / CHARACTER SWITCH
--==================================================

if Config.AutoEmoteAndSwitch then
    task.spawn(function()
        local success, result = pcall(function()
            local source = game:HttpGet(Config.AutoScriptURL)

            if not source or source == "" then
                error("Auto script source is empty")
            end

            local loaded = loadstring(source)

            if not loaded then
                error("Could not compile auto script")
            end

            loaded()
        end)

        if not success then
            warn("[Farm] Auto script error:", result)
        end
    end)
end

--==================================================
-- MAIN: HEARTBEAT ALT HEALTH MONITOR
--==================================================

local WatchedAltCharacters = {}

local function IsConfiguredAlt(player)
    for _, username in ipairs(AltAccounts) do
        if player.Name:lower() == username:lower() then
            return true
        end
    end

    return false
end

local function WatchAltCharacter(player, char)
    if not IsMain or not IsConfiguredAlt(player) then
        return
    end

    local humanoid = char:WaitForChild("Humanoid", 10)

    if not humanoid then
        warn("[Farm] Could not find alt Humanoid:", player.Name)
        return
    end

    local state = {
        Character = char,
        Humanoid = humanoid,
        Triggered = false,
    }

    WatchedAltCharacters[player] = state

    local function CheckAltHealth()
        if state.Triggered then
            return
        end

        if player.Character ~= char then
            return
        end

        if humanoid.Health <= 0 then
            state.Triggered = true

            print(
                "[Farm] ALT HEALTH ZERO:",
                player.Name,
                "Health:",
                humanoid.Health
            )

            StartMainCycle()
        end
    end

    -- Immediate health-change detection.
    humanoid.HealthChanged:Connect(CheckAltHealth)

    -- Death event backup.
    humanoid.Died:Connect(CheckAltHealth)

    -- Initial check in case health already reached zero.
    CheckAltHealth()
end

local BoundAltPlayers = {}

local function BindAltPlayer(player)
    if not IsMain or not IsConfiguredAlt(player) then
        return
    end

    if BoundAltPlayers[player] then
        return
    end

    BoundAltPlayers[player] = true

    player.CharacterAdded:Connect(function(char)
        task.spawn(WatchAltCharacter, player, char)
    end)

    if player.Character then
        task.spawn(WatchAltCharacter, player, player.Character)
    end

    print("[Farm] Health monitoring enabled:", player.Name)
end

if IsMain then
    for _, player in ipairs(Players:GetPlayers()) do
        BindAltPlayer(player)
    end

    Players.PlayerAdded:Connect(BindAltPlayer)

    Players.PlayerRemoving:Connect(function(player)
        BoundAltPlayers[player] = nil
        WatchedAltCharacters[player] = nil
    end)
end

--==================================================
-- ALT: MONITOR MAIN HEALTH
--==================================================

local MainCharacterWatched = nil
local MainDeathTriggered = false
local AltResetTaskRunning = false

local function StartAltResetAfterMainDeath()
    if not IsAlt or AltResetTaskRunning then
        return
    end

    AltResetTaskRunning = true

    task.spawn(function()
        print("[Farm] MAIN HEALTH ZERO")
        print("[Farm] Waiting 3 seconds before alt reset")

        task.wait(Config.AltCooldownWait)

        if WaitForLocalCharacter(5) then
            print("[Farm] Cooldown finished. Alt resetting now.")
            RequestLocalReset()
        else
            warn("[Farm] Alt character not ready after cooldown")
        end

        -- The next alt character spawn re-arms the cycle.
    end)
end

local function WatchMainCharacter(char)
    if not IsAlt then
        return
    end

    if MainCharacterWatched == char then
        return
    end

    MainCharacterWatched = char
    MainDeathTriggered = false

    local humanoid = char:WaitForChild("Humanoid", 10)

    if not humanoid then
        warn("[Farm] Main Humanoid not found")
        return
    end

    local function CheckMainHealth()
        if MainDeathTriggered then
            return
        end

        if humanoid.Health <= 0 then
            MainDeathTriggered = true
            StartAltResetAfterMainDeath()
        end
    end

    humanoid.HealthChanged:Connect(CheckMainHealth)
    humanoid.Died:Connect(CheckMainHealth)

    CheckMainHealth()
end

if IsAlt then
    local main = FindPlayer(Config.MainAccount)

    if main then
        main.CharacterAdded:Connect(function(char)
            task.spawn(WatchMainCharacter, char)
        end)

        if main.Character then
            task.spawn(WatchMainCharacter, main.Character)
        end
    else
        Players.PlayerAdded:Connect(function(player)
            if player.Name:lower() == Config.MainAccount:lower() then
                player.CharacterAdded:Connect(function(char)
                    task.spawn(WatchMainCharacter, char)
                end)

                if player.Character then
                    task.spawn(WatchMainCharacter, player.Character)
                end
            end
        end)
    end

    -- Re-arm alt's next cycle after it respawns.
    LocalPlayer.CharacterAdded:Connect(function()
        AltResetTaskRunning = false
        print("[Farm] Alt respawned and ready for next cycle")
    end)
end

--==================================================
-- HEARTBEAT FALLBACK MONITOR
--==================================================

RunService.Heartbeat:Connect(function()
    if IsMain then
        -- Poll every watched alt each frame.
        for player, state in pairs(WatchedAltCharacters) do
            if player.Parent == Players
                and state.Character
                and state.Humanoid
                and not state.Triggered
            then
                if state.Humanoid.Health <= 0 then
                    state.Triggered = true

                    print(
                        "[Farm] HEARTBEAT DETECTED ALT ZERO:",
                        player.Name
                    )

                    StartMainCycle()
                end
            end
        end
    end

    if IsAlt then
        -- Poll the main character every frame.
        local main = FindPlayer(Config.MainAccount)

        if main and main.Character then
            local mainCharacter = main.Character

            if MainCharacterWatched ~= mainCharacter then
                task.spawn(WatchMainCharacter, mainCharacter)
            end

            local mainHumanoid =
                mainCharacter:FindFirstChildOfClass("Humanoid")

            if mainHumanoid and mainHumanoid.Health <= 0 then
                if not MainDeathTriggered then
                    MainDeathTriggered = true
                    StartAltResetAfterMainDeath()
                end
            end
        end
    end
end)

--==================================================
-- POSITION MAINTENANCE
--==================================================

task.spawn(function()
    while true do
        if CharacterReady
            and Character == LocalPlayer.Character
            and Humanoid
            and RootPart
            and Humanoid.Health > 0
        then
            if IsAlt then
                if (RootPart.Position - AssignedPosition).Magnitude > 2 then
                    RootPart.CFrame = CFrame.new(AssignedPosition)
                end
            end
        end

        task.wait(Config.PositionCheckInterval)
    end
end)

--==================================================
-- INITIALIZATION
--==================================================

print("[Farm] System initialized:", LocalPlayer.Name)
print("[Farm] Role:", IsMain and "MAIN" or "ALT")
print("[Farm] Heartbeat health detection enabled")
print("[Farm] Skill 4 cycle:", IsMain and "ENABLED" or "ALT RESET MODE")
