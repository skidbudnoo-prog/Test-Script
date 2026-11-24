
--// MULTI-ACCOUNT FARMING SYSTEM
--// Main + Alt Account Controller

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    return
end

--==================================================
-- GETGENV CONFIGURATION
--==================================================

local SharedEnv = (typeof(getgenv) == "function" and getgenv()) or _G

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

local MainAccountName = CleanUsername(SharedEnv.MainAccount) or ""
local AltAccountNames = {}

if typeof(SharedEnv.AltAccounts) == "table" then
    local Added = {}

    for _, username in pairs(SharedEnv.AltAccounts) do
        local cleaned = CleanUsername(username)

        if cleaned and not Added[cleaned:lower()] then
            Added[cleaned:lower()] = true
            table.insert(AltAccountNames, cleaned)
        end
    end
end

--==================================================
-- CONFIGURATION
--==================================================

local Config = {
    MainAccount = MainAccountName,
    AltAccounts = AltAccountNames,

    MainPosition = Vector3.new(364, 440, 433),
    AltPosition = Vector3.new(361, 440, 428),

    DetectionDistance = 15,
    CharacterAvailabilityTimeout = 3,

    DisableAltCollisions = true,

    AutoEmoteAndSwitch = true,

    AutoScriptURL =
        "https://raw.githubusercontent.com/REES-oss/Loaders/refs/heads/main/auto.luau",

    KillCounter = true,
}

--==================================================
-- ACCOUNT IDENTIFICATION
--==================================================

local IsMain = MainAccountName ~= ""
    and LocalPlayer.Name:lower() == MainAccountName:lower()

local IsAlt = false

for _, username in ipairs(Config.AltAccounts) do
    if LocalPlayer.Name:lower() == username:lower() then
        IsAlt = true
        break
    end
end

if not IsMain and not IsAlt then
    warn("[Farm] Account is not configured:", LocalPlayer.Name)
    return
end

print("[Farm] Account:", LocalPlayer.Name)
print("[Farm] Role:", IsMain and "MAIN" or "ALT")
print("[Farm] Configured alts:", #Config.AltAccounts)

local AssignedPosition = IsMain
    and Config.MainPosition
    or Config.AltPosition

--==================================================
-- PLAYER LOOKUP
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

    if not humanoid or not root then
        return nil
    end

    if humanoid.Health <= 0 then
        return nil
    end

    return char, humanoid, root
end

local function WaitForCharacterReady(generation)
    while generation == CharacterGeneration do
        local char, humanoid, root = GetCharacterComponents()

        if char and humanoid and root then
            if char == LocalPlayer.Character then
                Character = char
                Humanoid = humanoid
                RootPart = root
                CharacterReady = true

                return true
            end
        end

        RunService.Heartbeat:Wait()
    end

    return false
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

    CollisionConnection = char.DescendantAdded:Connect(
        ApplyCollision
    )
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
    end)
end

LocalPlayer.CharacterAdded:Connect(HandleCharacterSpawn)

LocalPlayer.CharacterRemoving:Connect(function()
    CharacterReady = false

    CharacterGeneration += 1

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
-- KILL COUNTER UI
--==================================================

local StartingKills = 0
local CurrentKills = 0

local ScreenGui
local KillLabel

if Config.KillCounter then
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "FarmKillCounter"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = PlayerGui

    KillLabel = Instance.new("TextLabel")
    KillLabel.Name = "KillCounter"

    KillLabel.AnchorPoint = Vector2.new(1, 0)
    KillLabel.Position = UDim2.new(1, -20, 0, 20)
    KillLabel.Size = UDim2.new(0, 220, 0, 35)

    KillLabel.BackgroundTransparency = 1
    KillLabel.BorderSizePixel = 0

    KillLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    KillLabel.TextSize = 18
    KillLabel.Font = Enum.Font.GothamBold

    KillLabel.TextXAlignment = Enum.TextXAlignment.Right
    KillLabel.Text = "Farmed Kills: 0"

    KillLabel.Parent = ScreenGui

    local function SetupKillCounter()
        local leaderstats = LocalPlayer:FindFirstChild("leaderstats")

        if not leaderstats then
            return
        end

        local kills = leaderstats:FindFirstChild("Kills")

        if not kills then
            return
        end

        StartingKills = kills.Value
        CurrentKills = kills.Value

        kills:GetPropertyChangedSignal("Value"):Connect(function()
            CurrentKills = kills.Value

            local farmed = CurrentKills - StartingKills

            KillLabel.Text = "Farmed Kills: " ..
                tostring(math.max(0, farmed))
        end)
    end

    task.spawn(function()
        while not LocalPlayer:FindFirstChild("leaderstats") do
            RunService.Heartbeat:Wait()
        end

        while not LocalPlayer.leaderstats:FindFirstChild("Kills") do
            RunService.Heartbeat:Wait()
        end

        SetupKillCounter()
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
-- MAIN ACCOUNT: ALT MONITORING
--==================================================

local AltStates = {}

local function GetAltState(username)
    if not AltStates[username] then
        AltStates[username] = {
            Available = false,
            Character = nil,
            Humanoid = nil,
            RootPart = nil,
            LastSeen = 0,
        }
    end

    return AltStates[username]
end

local function MonitorAlt(username)
    local player = FindPlayer(username)

    local state = GetAltState(username)

    if not player then
        state.Available = false
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
    for _, username in ipairs(Config.AltAccounts) do
        local state = GetAltState(username)

        if state.Available and state.RootPart then
            return username, state.RootPart
        end
    end

    return nil, nil
end

--==================================================
-- ALT ACCOUNT: MAIN DETECTION
--==================================================

local ResetTriggered = false

local function MonitorMain()
    local main = FindPlayer(Config.MainAccount)

    if not main then
        ResetTriggered = false
        return
    end

    local mainCharacter = main.Character

    if not mainCharacter then
        return
    end

    local mainRoot = mainCharacter:FindFirstChild("HumanoidRootPart")
    local mainHumanoid = mainCharacter:FindFirstChildOfClass("Humanoid")

    if not mainRoot or not mainHumanoid then
        return
    end

    if not RootPart or not CharacterReady then
        return
    end

    local distance = (mainRoot.Position - RootPart.Position).Magnitude

    if distance <= Config.DetectionDistance then
        if not ResetTriggered then
            ResetTriggered = true

            print("[Farm] Main detected nearby")

            if Humanoid and Humanoid.Health > 0 then
                Humanoid.Health = 0
            end
        end
    else
        ResetTriggered = false
    end
end

--==================================================
-- HEARTBEAT MONITORING
--==================================================

local LastPositionCheck = 0
local PositionCheckInterval = 0.5

RunService.Heartbeat:Connect(function()
    -- Character readiness

    if not CharacterReady then
        return
    end

    if not Character or not Humanoid or not RootPart then
        return
    end

    if Character ~= LocalPlayer.Character then
        CharacterReady = false
        return
    end

    if Humanoid.Health <= 0 then
        CharacterReady = false
        return
    end

    -- ALT ACCOUNT PROCESS

    if IsAlt then
        MonitorMain()
    end

    -- MAIN ACCOUNT PROCESS

    if IsMain then
        for _, username in ipairs(Config.AltAccounts) do
            MonitorAlt(username)
        end

        local selectedUsername, selectedRoot = GetAvailableAlt()

        if selectedUsername and selectedRoot then
            local availableFor = os.clock() -
                GetAltState(selectedUsername).LastSeen

            if availableFor <= Config.CharacterAvailabilityTimeout then
                -- Alt availability confirmed.
            end
        end
    end

    -- Position maintenance

    if os.clock() - LastPositionCheck >= PositionCheckInterval then
        LastPositionCheck = os.clock()

        if IsAlt then
            if (RootPart.Position - AssignedPosition).Magnitude > 2 then
                RootPart.CFrame = CFrame.new(AssignedPosition)
            end
        end
    end
end)

