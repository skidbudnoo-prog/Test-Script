
--==================================================
-- MULTI-ACCOUNT FARMING SYSTEM
-- MAIN + ALT CONTROLLER
-- SYNCHRONIZED SKILL 4 / RESET CYCLE
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
    if value == "" then
        return nil
    end

    return value
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

if IsMain and #AltAccounts == 0 then
    warn("[Farm] No alt accounts configured")
end

print("[Farm] Account:", LocalPlayer.Name)
print("[Farm] Role:", IsMain and "MAIN" or "ALT")

local AssignedPosition = IsMain
    and Config.MainPosition
    or Config.AltPosition

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

        task.wait(0.05)
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
local MainCycleCharacter = nil
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

    print("[Farm] MAIN: Skill 4 pressed")
    return true
end

--==================================================
-- MAIN: ALT RESET START DETECTION
--==================================================

local function OnAltResetStarted(player)
    if not IsMain then
        return
    end

    if MainCycleBusy or MainCycleUsed then
        return
    end

    if not player or player.Parent ~= Players then
        return
    end

    MainCycleBusy = true
    MainCycleUsed = true

    print("[Farm] Alt reset started:", player.Name)
    print("[Farm] Main activating Skill 4")

    task.spawn(function()
        -- Wait until the main character is alive.
        if not WaitForLocalCharacter(5) then
            warn("[Farm] Main character unavailable")
            MainCycleBusy = false
            return
        end

        MainCycleCharacter = LocalPlayer.Character

        -- Skill 4 happens immediately when the alt starts removing.
        PressSkill4()

        -- Wait 1.5 seconds before resetting the main.
        task.wait(Config.SkillWaitBeforeReset)

        -- Do not reset an unexpected replacement character.
        if LocalPlayer.Character == MainCycleCharacter
            and CharacterReady
            and Humanoid
            and Humanoid.Health > 0
        then
            print("[Farm] Main resetting after Skill 4")
            RequestLocalReset()
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

        -- A new main character can begin the next cycle.
        if IsMain then
            MainCycleUsed = false
            MainCycleCharacter = nil
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
-- MAIN: BIND ALT RESET EVENTS
--==================================================

local BoundAltPlayers = {}

local function IsConfiguredAlt(player)
    for _, username in ipairs(AltAccounts) do
        if player.Name:lower() == username:lower() then
            return true
        end
    end

    return false
end

local function BindAltPlayer(player)
    if not IsMain or not IsConfiguredAlt(player) then
        return
    end

    if BoundAltPlayers[player] then
        return
    end

    BoundAltPlayers[player] = true

    -- Listen for the START of the alt reset.
    -- This fires before the alt's next CharacterAdded.
    player.CharacterRemoving:Connect(function(oldCharacter)
        if not IsMain then
            return
        end

        if player.Parent ~= Players then
            return
        end

        if not oldCharacter then
            return
        end

        OnAltResetStarted(player)
    end)

    print("[Farm] Watching alt reset:", player.Name)
end

if IsMain then
    for _, player in ipairs(Players:GetPlayers()) do
        BindAltPlayer(player)
    end

    Players.PlayerAdded:Connect(BindAltPlayer)

    Players.PlayerRemoving:Connect(function(player)
        BoundAltPlayers[player] = nil
    end)
end

--==================================================
-- ALT: RESET AFTER MAIN RESET STARTS
--==================================================

local MainResetPending = false
local BoundMainPlayer = nil

local function BindMainPlayer(player)
    if not IsAlt or not player then
        return
    end

    if player.Name:lower() ~= Config.MainAccount:lower() then
        return
    end

    if BoundMainPlayer == player then
        return
    end

    BoundMainPlayer = player

    print("[Farm] Watching main reset:", player.Name)

    player.CharacterRemoving:Connect(function()
        if MainResetPending then
            return
        end

        MainResetPending = true

        print("[Farm] Main reset started. Alt cooldown:", Config.AltCooldownWait)

        task.spawn(function()
            -- Wait 3 seconds after the main begins resetting.
            task.wait(Config.AltCooldownWait)

            if WaitForLocalCharacter(5) then
                print("[Farm] Alt cooldown finished. Resetting alt.")
                RequestLocalReset()
            else
                warn("[Farm] Alt character was not ready")
            end

            MainResetPending = false
        end)
    end)
end

if IsAlt then
    local main = FindPlayer(Config.MainAccount)

    if main then
        BindMainPlayer(main)
    end

    Players.PlayerAdded:Connect(BindMainPlayer)
end

--==================================================
-- MAIN: ALT AVAILABILITY MONITOR
--==================================================

local AltStates = {}

local function GetAltState(username)
    local key = username:lower()

    if not AltStates[key] then
        AltStates[key] = {
            Available = false,
            Character = nil,
            Humanoid = nil,
            RootPart = nil,
            LastSeen = 0,
        }
    end

    return AltStates[key]
end

local function MonitorAlt(username)
    local state = GetAltState(username)
    local player = FindPlayer(username)

    if not player then
        state.Available = false
        state.Character = nil
        state.Humanoid = nil
        state.RootPart = nil
        return
    end

    local char = player.Character

    if not char then
        state.Available = false
        return
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then
        state.Available = false
        return
    end

    state.Available = true
    state.Character = char
    state.Humanoid = humanoid
    state.RootPart = root
    state.LastSeen = os.clock()
end

local function GetAvailableAlt()
    for _, username in ipairs(AltAccounts) do
        local state = GetAltState(username)

        if state.Available
            and state.Character
            and state.RootPart
            and state.Humanoid
            and state.Humanoid.Health > 0
        then
            return username, state.RootPart
        end
    end

    return nil, nil
end

local function WaitForAvailableAlt()
    local started = os.clock()

    repeat
        for _, username in ipairs(AltAccounts) do
            MonitorAlt(username)
        end

        local username, root = GetAvailableAlt()

        if username and root then
            return username, root
        end

        RunService.Heartbeat:Wait()
    until os.clock() - started >= Config.CharacterAvailabilityTimeout

    return nil, nil
end

if IsMain then
    task.spawn(function()
        while true do
            for _, username in ipairs(AltAccounts) do
                MonitorAlt(username)
            end

            local username = WaitForAvailableAlt()

            if username then
                -- Availability tracking only.
                -- The reset event controls the Skill 4 cycle.
            end

            task.wait(0.5)
        end
    end)
end

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
print("[Farm] Synchronized Skill 4 cycle enabled")
