local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local SharedEnv = (typeof(getgenv) == "function" and getgenv()) or _G

local function CleanUsername(value)
    if typeof(value) ~= "string" then return nil end
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
    MainPosition = Vector3.new(286, 440, 474),
    AltPosition = Vector3.new(285, 440, 470),

    DisableAltCollisions = true,

    AutoEmoteAndSwitch = true,
    AutoScriptURL = "https://raw.githubusercontent.com/REES-oss/Loaders/refs/heads/main/auto.luau",

    KillCounter = true,
    PositionCheckInterval = 0.5,

    SkillKey = Enum.KeyCode.Four,
    MobileSkillName = "Jet Dive",
    MobileButtonSearchTimeout = 8,

    SkillWaitBeforeReset = 2.9,
    CycleWaitAfterMainSpawn = 3.2,
    KeyPressDuration = 0.12,
}

-- Mobile is detected separately from PC.
-- Touch-only devices use the mobile button.
-- Devices with a physical keyboard use the PC key method.
local IsMobile = UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

local function FindPlayer(username)
    if not username or username == "" then return nil end

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
    warn("[Farm] Account is not configured")
    return
end

if IsMain and #AltAccounts == 0 then
    warn("[Farm] No alt accounts configured")
    return
end

local AssignedPosition = IsMain and Config.MainPosition or Config.AltPosition

local Character
local Humanoid
local RootPart
local CharacterReady = false
local CharacterGeneration = 0
local CollisionConnection

local function GetCharacterComponents()
    local char = LocalPlayer.Character
    if not char then return nil end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end

    return char, humanoid, root
end

local function WaitForLocalCharacter(timeout)
    local started = os.clock()

    repeat
        local char, humanoid, root = GetCharacterComponents()

        if char and humanoid and root then
            Character = char
            Humanoid = humanoid
            RootPart = root
            CharacterReady = true
            return true
        end

        RunService.Heartbeat:Wait()
    until os.clock() - started >= (timeout or 30)

    return false
end

--==================================================
-- DIRECT CHARACTER RESET
--==================================================

local function RequestLocalReset()
    local char, humanoid = GetCharacterComponents()
    if not char or not humanoid then return false end

    local success = pcall(function()
        humanoid.Health = 0
    end)

    return success
end

--==================================================
-- MOBILE SKILL BUTTON DETECTION
--==================================================

local function NormalizeSkillText(value)
    if typeof(value) ~= "string" then
        return ""
    end

    value = value:lower()
    value = value:gsub("%s+", " ")
    value = value:match("^%s*(.-)%s*$")

    return value
end

local function IsGuiVisible(guiObject)
    local current = guiObject

    while current and current ~= game do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end

        current = current.Parent
    end

    return true
end

local function FindJetDiveButton()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end

    local targetName = NormalizeSkillText(Config.MobileSkillName)

    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("GuiButton") then
            local buttonText = ""

            if object:IsA("TextButton") then
                buttonText = NormalizeSkillText(object.Text)
            end

            if buttonText == targetName then
                if IsGuiVisible(object) and object.Active then
                    return object
                end
            end

            for _, child in ipairs(object:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    local childText = NormalizeSkillText(child.Text)

                    if childText == targetName then
                        if IsGuiVisible(object) and object.Active then
                            return object
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function ActivateMobileSkill4()
    if not IsMobile then
        return false
    end

    local started = os.clock()
    local button

    repeat
        if not GetCharacterComponents() then
            return false
        end

        button = FindJetDiveButton()

        if button then
            break
        end

        task.wait(0.1)
    until os.clock() - started >= Config.MobileButtonSearchTimeout

    if not button then
        warn("[Farm] Mobile Jet Dive button was not found")
        return false
    end

    local success, err = pcall(function()
        button:Activate()
    end)

    if not success then
        warn("[Farm] Mobile Jet Dive activation failed:", err)
        return false
    end

    return true
end

--==================================================
-- MAIN SKILL 4
--==================================================

local function PressSkill4()
    if not IsMain then return false end

    local char, humanoid = GetCharacterComponents()
    if not char or not humanoid then return false end

    -- MOBILE ONLY:
    -- Activate the actual Jet Dive on-screen button.
    if IsMobile then
        return ActivateMobileSkill4()
    end

    -- PC ONLY:
    -- Keep the original keyboard activation.
    local success, err = pcall(function()
        local VirtualInputManager = game:GetService("VirtualInputManager")

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
        warn("[Farm] PC Skill 4 input failed:", err)
        return false
    end

    return true
end

--==================================================
-- ALT COLLISION HANDLING
--==================================================

local function DisableCollisions(char)
    if not IsAlt or not Config.DisableAltCollisions then return end

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
-- MAIN CYCLE
--==================================================

local MainCycleBusy = false
local MainCycleTriggered = false
local MainCycleReady = false
local MainCycleCharacter = nil

local function StartMainCycle()
    if not IsMain or MainCycleBusy or MainCycleTriggered then return end

    MainCycleBusy = true
    MainCycleTriggered = true

    task.spawn(function()
        if not WaitForLocalCharacter(30) then
            MainCycleBusy = false
            MainCycleTriggered = false
            return
        end

        while not MainCycleReady do
            if not GetCharacterComponents() then
                MainCycleBusy = false
                return
            end

            RunService.Heartbeat:Wait()
        end

        local mainCharacter = LocalPlayer.Character
        MainCycleCharacter = mainCharacter

        local skillActivated = PressSkill4()

        if skillActivated then
            task.wait(Config.SkillWaitBeforeReset)

            if LocalPlayer.Character == mainCharacter
                and GetCharacterComponents()
            then
                RequestLocalReset()
            end
        else
            -- Do not reset the main if Skill 4 failed.
            -- Allow another attempt on a later alt death.
            MainCycleTriggered = false
        end

        MainCycleBusy = false
    end)
end

local function PrepareMainCycle(char)
    MainCycleReady = false
    MainCycleTriggered = false
    MainCycleCharacter = nil

    task.spawn(function()
        local started = os.clock()

        repeat
            local current, humanoid, root = GetCharacterComponents()

            if current == char and humanoid and root then
                break
            end

            RunService.Heartbeat:Wait()
        until os.clock() - started >= 30

        if LocalPlayer.Character ~= char or not GetCharacterComponents() then
            return
        end

        task.wait(Config.CycleWaitAfterMainSpawn)

        if LocalPlayer.Character == char and GetCharacterComponents() then
            MainCycleReady = true
        end
    end)
end

--==================================================
-- WATCH ALT HEALTH
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
    if not IsMain or not IsConfiguredAlt(player) then return end
    if WatchedAltCharacters[char] then return end

    WatchedAltCharacters[char] = true

    task.spawn(function()
        local started = os.clock()
        local humanoid

        repeat
            humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then break end
            RunService.Heartbeat:Wait()
        until os.clock() - started >= 20

        if not humanoid then return end

        local triggered = false

        local function CheckHealth()
            if triggered or humanoid.Health > 0 then return end

            triggered = true
            StartMainCycle()
        end

        humanoid.HealthChanged:Connect(CheckHealth)
        humanoid.Died:Connect(CheckHealth)

        CheckHealth()
    end)
end

local BoundAltPlayers = {}

local function BindAltPlayer(player)
    if not IsMain or not IsConfiguredAlt(player) then return end
    if BoundAltPlayers[player] then return end

    BoundAltPlayers[player] = true

    player.CharacterAdded:Connect(function(char)
        WatchAltCharacter(player, char)
    end)

    if player.Character then
        WatchAltCharacter(player, player.Character)
    end
end

--==================================================
-- ALT RESET AFTER MAIN SPAWNS
--==================================================

local LastScheduledMainCharacter = nil
local AltResetScheduled = false
local BoundMainPlayer = nil

local function ScheduleAltCycle(mainCharacter)
    if not IsAlt or not mainCharacter then return end
    if LastScheduledMainCharacter == mainCharacter then return end

    LastScheduledMainCharacter = mainCharacter
    AltResetScheduled = true

    task.spawn(function()
        local mainPlayer = FindPlayer(MainAccount)

        if not mainPlayer then
            AltResetScheduled = false
            return
        end

        local started = os.clock()

        repeat
            if mainPlayer.Character ~= mainCharacter then
                AltResetScheduled = false
                return
            end

            local char, humanoid, root = GetCharacterComponents()
            if char and humanoid and root then break end

            RunService.Heartbeat:Wait()
        until os.clock() - started >= 30

        if mainPlayer.Character ~= mainCharacter then
            AltResetScheduled = false
            return
        end

        task.wait(Config.CycleWaitAfterMainSpawn)

        if not AltResetScheduled then return end

        if mainPlayer.Character ~= mainCharacter
            or not GetCharacterComponents()
        then
            AltResetScheduled = false
            return
        end

        RequestLocalReset()
        AltResetScheduled = false
    end)
end

local function BindMainPlayer(player)
    if not IsAlt or not player then return end
    if player.Name:lower() ~= MainAccount:lower() then return end
    if BoundMainPlayer == player then return end

    BoundMainPlayer = player

    player.CharacterAdded:Connect(function(char)
        ScheduleAltCycle(char)
    end)

    if player.Character then
        ScheduleAltCycle(player.Character)
    end
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
        local started = os.clock()

        repeat
            if generation ~= CharacterGeneration then return end

            local current, humanoid, root = GetCharacterComponents()

            if current == char and humanoid and root then
                Character = current
                Humanoid = humanoid
                RootPart = root
                CharacterReady = true

                if IsAlt then
                    DisableCollisions(char)
                end

                RootPart.CFrame = CFrame.new(AssignedPosition)

                if IsMain then
                    PrepareMainCycle(char)
                end

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

    if CollisionConnection then
        CollisionConnection:Disconnect()
        CollisionConnection = nil
    end
end)

if LocalPlayer.Character then
    HandleCharacterSpawn(LocalPlayer.Character)
end

--==================================================
-- ACCOUNT BINDING
--==================================================

if IsMain then
    for _, player in ipairs(Players:GetPlayers()) do
        BindAltPlayer(player)
    end

    Players.PlayerAdded:Connect(BindAltPlayer)

    Players.PlayerRemoving:Connect(function(player)
        BoundAltPlayers[player] = nil
    end)
end

if IsAlt then
    local main = FindPlayer(MainAccount)

    if main then
        BindMainPlayer(main)
    end

    Players.PlayerAdded:Connect(function(player)
        if player.Name:lower() == MainAccount:lower() then
            BindMainPlayer(player)
        end
    end)
end

--==================================================
-- KILL COUNTER
--==================================================

if Config.KillCounter then
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")

        local oldGui = playerGui:FindFirstChild("FarmKillCounter")
        if oldGui then oldGui:Destroy() end

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
-- CREDITS
--==================================================

task.spawn(function()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    local oldGui = playerGui:FindFirstChild("FarmInfo")
    if oldGui then oldGui:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "FarmInfo"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui

    local label = Instance.new("TextLabel")
    label.Name = "Credits"
    label.AnchorPoint = Vector2.new(0, 1)
    label.Position = UDim2.new(0, 12, 1, -12)
    label.Size = UDim2.new(0, 350, 0, 42)
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Text = "discord.gg/mCjGKXrhgp\nCredits to revenang for anti ban script"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 13
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.Parent = gui
end)

--==================================================
-- AUTO EMOTE / CHARACTER SWITCH
--==================================================

if Config.AutoEmoteAndSwitch then
    task.spawn(function()
        pcall(function()
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
    end)
end

--==================================================
-- ALT POSITION MAINTENANCE
--==================================================

task.spawn(function()
    while true do
        if CharacterReady
            and Character == LocalPlayer.Character
            and Humanoid
            and RootPart
            and Humanoid.Health > 0
            and IsAlt
        then
            if (RootPart.Position - AssignedPosition).Magnitude > 2 then
                RootPart.CFrame = CFrame.new(AssignedPosition)
            end
        end

        task.wait(Config.PositionCheckInterval)
    end
end)
