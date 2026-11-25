
--==================================================
-- MULTI-ACCOUNT FARMING SYSTEM
-- MAIN + ALT CONTROLLER
-- SYNCHRONIZED SKILL 4 / RESET CYCLE
--==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")

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

    DisableAltCollisions = true,

    AutoEmoteAndSwitch = true,
    AutoScriptURL = "https://raw.githubusercontent.com/REES-oss/Loaders/refs/heads/main/auto.luau",

    KillCounter = true,
    PositionCheckInterval = 0.5,

    SkillKey = Enum.KeyCode.Four,
    SkillWaitBeforeReset = 2.7,
    CycleWaitAfterMainSpawn = 3.2,
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
    warn("[Farm] Check getgenv().MainAccount and getgenv().AltAccounts")
    return
end

if IsMain and #AltAccounts == 0 then
    warn("[Farm] No alt accounts configured")
    return
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

local function GetAliveCharacter(player)
    local char = player and player.Character
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

local function WaitForAliveCharacter(player, timeout)
    local started = os.clock()

    repeat
        local char, humanoid, root = GetAliveCharacter(player)

        if char and humanoid and root then
            return char, humanoid, root
        end

        RunService.Heartbeat:Wait()
    until os.clock() - started >= (timeout or 30)

    return nil
end

local function HandleCharacterSpawn(char)
    CharacterGeneration += 1
    local generation = CharacterGeneration

    CharacterReady = false
    Character = char
    Humanoid = nil
    RootPart = nil

    task.spawn(function()
        local started = os.clock()

        repeat
            if generation ~= CharacterGeneration then
                return
            end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")

            if humanoid and root and humanoid.Health > 0 then
                Character = char
                Humanoid = humanoid
                RootPart = root
                CharacterReady = true

                print("[Farm] Character ready:", LocalPlayer.Name)

                if IsAlt and Config.DisableAltCollisions then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end

                    char.DescendantAdded:Connect(function(part)
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end)
                end

                RootPart.CFrame = CFrame.new(AssignedPosition)
                return
            end

            RunService.Heartbeat:Wait()
        until os.clock() - started >= 30
    end)
end

LocalPlayer.CharacterAdded:Connect(HandleCharacterSpawn)

LocalPlayer.CharacterRemoving:Connect(function()
    CharacterGeneration += 1
    CharacterReady = false
    Character = nil
    Humanoid = nil
    RootPart = nil
end)

if LocalPlayer.Character then
    HandleCharacterSpawn(LocalPlayer.Character)
end

--==================================================
-- RESET FUNCTION
--==================================================

local function TapKey(key)
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function RequestLocalReset()
    local char, humanoid = GetAliveCharacter(LocalPlayer)

    if not char or not humanoid then
        warn("[Farm] Cannot reset: character is not alive")
        return false
    end

    print("[Farm] Requesting Roblox character reset:", LocalPlayer.Name)

    -- Use Roblox's reset menu rather than relying only on
    -- a client-side Humanoid.Health assignment.
    pcall(function()
        StarterGui:SetCore("ResetButtonCallback", true)
    end)

    local success, err = pcall(function()
        TapKey(Enum.KeyCode.Escape)
        task.wait(0.3)

        TapKey(Enum.KeyCode.R)
        task.wait(0.3)

        TapKey(Enum.KeyCode.Return)
    end)

    if not success then
        warn("[Farm] Reset input failed:", err)
        return false
    end

    return true
end

--==================================================
-- MAIN: SKILL 4
--==================================================

local MainCycleBusy = false
local MainCycleTriggered = false
local MainCycleReady = false
local MainCycleCharacter = nil

local function PressSkill4()
    if not IsMain then
        return false
    end

    local char, humanoid = GetAliveCharacter(LocalPlayer)

    if not char or not humanoid then
        warn("[Farm] Cannot press Skill 4: main is not alive")
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

local function StartMainCycle(reason)
    if not IsMain then
        return
    end

    if MainCycleBusy or MainCycleTriggered then
        return
    end

    MainCycleBusy = true
    MainCycleTriggered = true

    print("[Farm] ALT RESET DETECTED:", reason)

    task.spawn(function()
        -- Wait until the main has completed its spawn delay.
        while not MainCycleReady do
            if not GetAliveCharacter(LocalPlayer) then
                task.wait(0.05)
            else
                task.wait(0.05)
            end
        end

        local mainCharacter = LocalPlayer.Character
        MainCycleCharacter = mainCharacter

        -- Activate Skill 4 immediately.
        PressSkill4()

        -- Wait 2.7 seconds before resetting the main.
        task.wait(Config.SkillWaitBeforeReset)

        if LocalPlayer.Character == mainCharacter
            and GetAliveCharacter(LocalPlayer)
        then
            print("[Farm] Main resetting after 2.7 seconds")
            RequestLocalReset()
        else
            warn("[Farm] Main character changed before reset")
        end

        MainCycleBusy = false
    end)
end

--==================================================
-- MAIN: WAIT FOR SPAWN + 3.2 SECOND CYCLE GATE
--==================================================

local function PrepareMainCycle(char)
    MainCycleReady = false
    MainCycleTriggered = false
    MainCycleCharacter = nil

    task.spawn(function()
        local aliveCharacter = WaitForAliveCharacter(LocalPlayer, 30)

        if not aliveCharacter or LocalPlayer.Character ~= char then
            return
        end

        print("[Farm] Main spawned. Waiting 3.2 seconds")

        task.wait(Config.CycleWaitAfterMainSpawn)

        if LocalPlayer.Character == char
            and GetAliveCharacter(LocalPlayer)
        then
            MainCycleReady = true
            print("[Farm] Main cycle ready")
        end
    end)
end

if IsMain then
    LocalPlayer.CharacterAdded:Connect(PrepareMainCycle)

    if LocalPlayer.Character then
        PrepareMainCycle(LocalPlayer.Character)
    end
end

--==================================================
-- MAIN: MONITOR ALT HEALTH
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

    if WatchedAltCharacters[char] then
        return
    end

    WatchedAltCharacters[char] = true

    task.spawn(function()
        local started = os.clock()
        local humanoid

        repeat
            humanoid = char:FindFirstChildOfClass("Humanoid")

            if humanoid then
                break
            end

            RunService.Heartbeat:Wait()
        until os.clock() - started >= 15

        if not humanoid then
            warn("[Farm] Could not find alt Humanoid:", player.Name)
            return
        end

        print("[Farm] Monitoring alt health:", player.Name)

        local detected = false

        local function CheckHealth()
            if detected then
                return
            end

            if humanoid.Health <= 0 then
                detected = true
                print("[Farm] ALT HEALTH REACHED ZERO:", player.Name)
                StartMainCycle(player.Name .. " reached 0 HP")
            end
        end

        humanoid.HealthChanged:Connect(CheckHealth)
        humanoid.Died:Connect(CheckHealth)

        -- Immediate check in case the alt was already at zero.
        CheckHealth()
    end)
end

local function BindAltPlayer(player)
    if not IsMain or not IsConfiguredAlt(player) then
        return
    end

    player.CharacterAdded:Connect(function(char)
        WatchAltCharacter(player, char)
    end)

    player.CharacterRemoving:Connect(function()
        -- Fallback if the reset begins before the health event replicates.
        StartMainCycle(player.Name .. " character removing")
    end)

    if player.Character then
        WatchAltCharacter(player, player.Character)
    end

    print("[Farm] Watching alt:", player.Name)
end

if IsMain then
    for _, player in ipairs(Players:GetPlayers()) do
        BindAltPlayer(player)
    end

    Players.PlayerAdded:Connect(BindAltPlayer)
end

--==================================================
-- ALT: RESET 3.2 SECONDS AFTER MAIN SPAWNS
--==================================================

local LastScheduledMainCharacter = nil
local AltResetScheduled = false

local function ScheduleAltCycle(mainCharacter)
    if not IsAlt or not mainCharacter then
        return
    end

    if LastScheduledMainCharacter == mainCharacter then
        return
    end

    LastScheduledMainCharacter = mainCharacter
    AltResetScheduled = true

    task.spawn(function()
        local aliveCharacter = WaitForAliveCharacter(
            FindPlayer(Config.MainAccount),
            30
        )

        if not aliveCharacter then
            warn("[Farm] Alt could not detect main spawning")
            AltResetScheduled = false
            return
        end

        if FindPlayer(Config.MainAccount).Character ~= mainCharacter then
            AltResetScheduled = false
            return
        end

        print("[Farm] Main spawned. Alt waiting 3.2 seconds")

        task.wait(Config.CycleWaitAfterMainSpawn)

        local mainPlayer = FindPlayer(Config.MainAccount)

        if not mainPlayer
            or mainPlayer.Character ~= mainCharacter
            or not GetAliveCharacter(mainPlayer)
        then
            print("[Farm] Main changed during wait. Waiting for next spawn")
            AltResetScheduled = false
            return
        end

        if not AltResetScheduled then
            return
        end

        print("[Farm] 3.2 seconds finished. Alt resetting now")
        RequestLocalReset()

        -- Do not schedule another reset for this same main character.
        -- The next main CharacterAdded starts the next cycle.
    end)
end

if IsAlt then
    local function BindMain(player)
        if not player or player.Name:lower() ~= Config.MainAccount:lower() then
            return
        end

        player.CharacterAdded:Connect(function(char)
            ScheduleAltCycle(char)
        end)

        if player.Character then
            ScheduleAltCycle(player.Character)
        end

        print("[Farm] Alt watching main:", player.Name)
    end

    local main = FindPlayer(Config.MainAccount)

    if main then
        BindMain(main)
    else
        Players.PlayerAdded:Connect(function(player)
            if player.Name:lower() == Config.MainAccount:lower() then
                BindMain(player)
            end
        end)
    end
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
print("[Farm] Main reset delay:", Config.SkillWaitBeforeReset)
print("[Farm] Spawn cycle delay:", Config.CycleWaitAfterMainSpawn)
