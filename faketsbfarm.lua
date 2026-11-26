local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

if typeof(getgenv) ~= "function" then
    return
end

local SharedEnv = getgenv()
local MainAccount = SharedEnv.MainAccount
local AltAccounts = SharedEnv.AltAccounts

if typeof(MainAccount) ~= "string" or typeof(AltAccounts) ~= "table" then
    return
end

local function NormalizeUsername(value)
    if typeof(value) ~= "string" then
        return ""
    end
    return string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local LocalUsername = NormalizeUsername(LocalPlayer.Name)
local IsMain = LocalUsername ~= "" and LocalUsername == NormalizeUsername(MainAccount)
local IsAlt = false

for _, username in ipairs(AltAccounts) do
    if LocalUsername ~= "" and LocalUsername == NormalizeUsername(username) then
        IsAlt = true
        break
    end
end

if not IsMain and not IsAlt then
    return
end

local MainPosition = Vector3.new(228, 1139, 319)
local AltPosition = Vector3.new(227, 1139, 317)

local StartingKills = 0
local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
local KillsValue = Leaderstats and Leaderstats:FindFirstChild("Kills")

if KillsValue and (KillsValue:IsA("IntValue") or KillsValue:IsA("NumberValue")) then
    StartingKills = KillsValue.Value
end

local ScreenGui
local KillLabel

if IsMain then
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "FarmedKillsCounter"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.Parent = PlayerGui

    KillLabel = Instance.new("TextLabel")
    KillLabel.Name = "KillCounter"
    KillLabel.AnchorPoint = Vector2.new(1, 0)
    KillLabel.Position = UDim2.new(1, -14, 0, 12)
    KillLabel.Size = UDim2.new(0, 220, 0, 28)
    KillLabel.BackgroundTransparency = 1
    KillLabel.BorderSizePixel = 0
    KillLabel.Font = Enum.Font.Gotham
    KillLabel.Text = "Farmed Kills: 0"
    KillLabel.TextColor3 = Color3.new(1, 1, 1)
    KillLabel.TextSize = 16
    KillLabel.TextXAlignment = Enum.TextXAlignment.Right
    KillLabel.Parent = ScreenGui
end

local function UpdateKillCounter()
    if not KillLabel then
        return
    end

    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local kills = stats and stats:FindFirstChild("Kills")

    if kills and (kills:IsA("IntValue") or kills:IsA("NumberValue")) then
        KillLabel.Text = "Farmed Kills: " .. tostring(math.max(0, kills.Value - StartingKills))
    end
end

task.spawn(function()
    while IsMain do
        UpdateKillCounter()
        task.wait(0.25)
    end
end)

LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

local function GetCharacterParts(character)
    local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
    return root, humanoid
end

local function TeleportCharacter(character, position)
    local root = GetCharacterParts(character)
    if not root then
        return nil
    end

    character:PivotTo(CFrame.new(position))
    task.wait(0.1)

    root = character:FindFirstChild("HumanoidRootPart")
    return root
end

local function FreezeCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.AssemblyLinearVelocity = Vector3.zero
            descendant.AssemblyAngularVelocity = Vector3.zero
        end
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = true
    end
end

local function DisableCharacterCollision(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
        end
    end

    character.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
        end
    end)
end

local function PressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function ResetCharacter()
    PressKey(Enum.KeyCode.Escape)
    task.wait(0.15)
    PressKey(Enum.KeyCode.R)
    task.wait(0.15)
    PressKey(Enum.KeyCode.Return)
end

local function SpamM1()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.04)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

if IsMain then
    local currentCharacter

    local function HandleMainCharacter(character)
        currentCharacter = character
        local root = GetCharacterParts(character)
        if not root then
            return
        end

        task.wait(0.15)
        if currentCharacter ~= character or not character.Parent then
            return
        end

        root = TeleportCharacter(character, MainPosition)
        if not root then
            return
        end

        FreezeCharacter(character)
    end

    if LocalPlayer.Character then
        task.spawn(HandleMainCharacter, LocalPlayer.Character)
    end

    LocalPlayer.CharacterAdded:Connect(function(character)
        task.spawn(HandleMainCharacter, character)
    end)

    task.spawn(function()
        while true do
            local character = currentCharacter
            if character and character.Parent then
                local root = character:FindFirstChild("HumanoidRootPart")
                if root and not root.Anchored then
                    character:PivotTo(CFrame.new(MainPosition))
                    FreezeCharacter(character)
                end
                SpamM1()
            else
                task.wait(0.1)
            end
            task.wait(0.03)
        end
    end)
elseif IsAlt then
    local currentCharacter

    local function HandleAltCharacter(character)
        currentCharacter = character
        local root = GetCharacterParts(character)
        if not root then
            return
        end

        task.wait(0.15)
        if currentCharacter ~= character or not character.Parent then
            return
        end

        TeleportCharacter(character, AltPosition)
        DisableCharacterCollision(character)
    end

    if LocalPlayer.Character then
        task.spawn(HandleAltCharacter, LocalPlayer.Character)
    end

    LocalPlayer.CharacterAdded:Connect(function(character)
        task.spawn(HandleAltCharacter, character)
    end)

    task.spawn(function()
        while true do
            local character = currentCharacter
            if character and character.Parent then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    ResetCharacter()
                end
            end
            task.wait(1.2)
        end
    end)
end
