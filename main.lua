local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local targetPets = getgenv().TargetPetNames or {}

local hops = 0
local visitedJobIds = {[game.JobId] = true}
local stopHopping = false
local detectedPets = {}
local teleportFails = 0
local maxTeleportRetries = 3
local serverHopButtonGui = nil
local highlights = {}
local texts = {}

local function getSafeGuiParent()
    return (gethui and gethui()) or (syn and syn.protect_gui and syn.protect_gui(CoreGui)) or CoreGui
end

function serverHop(force)
    if stopHopping and not force then return end

    local success, result = pcall(function()
        task.wait(0.5)
        local PlaceId, JobId = game.PlaceId, game.JobId
        local cursor, tries = nil, 0

        hops += 1
        if hops >= 50 then
            visitedJobIds = {[JobId] = true}
            hops = 0
        end

        while tries < 3 do
            local url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor then url ..= "&cursor=" .. cursor end

            local httpSuccess, response = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if httpSuccess and response and response.data then
                local servers = {}
                for _, server in ipairs(response.data) do
                    if tonumber(server.playing) < tonumber(server.maxPlayers)
                        and server.id ~= JobId
                        and not visitedJobIds[server.id] then
                        table.insert(servers, server.id)
                    end
                end

                if #servers > 0 then
                    local picked = servers[math.random(1, #servers)]
                    TeleportService:TeleportToPlaceInstance(PlaceId, picked)
                    return
                end

                cursor = response.nextPageCursor
                if not cursor then tries += 1; task.wait(0.2) end
            else
                tries += 1
                task.wait(0.2)
            end
        end

        TeleportService:Teleport(PlaceId)
    end)

    if not success then
        warn("❌ serverHop erro:", result)
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    end
end

local function removeESP(player)
    if highlights[player] then
        highlights[player]:Destroy()
        highlights[player] = nil
    end
    if texts[player] then
        texts[player]:Remove()
        texts[player] = nil
    end
end

local function setupPlayerRemoval()
    Players.PlayerRemoving:Connect(removeESP)
end

function enableESP()
    for _, v in pairs(highlights) do if v and v.Destroy then v:Destroy() end end
    for _, v in pairs(texts) do if v and v.Remove then v:Remove() end end
    highlights, texts = {}, {}

    setupPlayerRemoval()

    RunService:UnbindFromRenderStep("ESP")
    RunService:BindToRenderStep("ESP", Enum.RenderPriority.Camera.Value + 1, function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)

                if onScreen then
                    if not highlights[player] then
                        local hl = Instance.new("Highlight")
                        hl.Adornee = player.Character
                        hl.FillColor = Color3.fromRGB(255, 0, 0)
                        hl.FillTransparency = 0.5
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.OutlineTransparency = 0
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Parent = game:GetService("CoreGui")
                        highlights[player] = hl
                    end

                    texts[player] = texts[player] or Drawing.new("Text")
                    local label = texts[player]
                    label.Text = player.Name
                    label.Size = 18
                    label.Center = true
                    label.Outline = true
                    label.Color = Color3.fromRGB(255, 255, 255)
                    label.Transparency = 1
                    label.Position = Vector2.new(pos.X, pos.Y - 35)
                    label.Visible = true
                else
                    if texts[player] then texts[player].Visible = false end
                end
            else
                removeESP(player)
            end
        end
    end)
end

local function addESP(targetModel)
    if not targetModel or targetModel:FindFirstChild("PetESP") then return end

    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "PetESP"
    Billboard.Adornee = targetModel
    Billboard.Size = UDim2.new(0, 120, 0, 40)
    Billboard.StudsOffset = Vector3.new(0, 4, 0)
    Billboard.AlwaysOnTop = true
    Billboard.Parent = targetModel

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = "🎯 (" .. targetModel.Name .. ")"
    Label.TextColor3 = Color3.fromRGB(255, 0, 0)
    Label.TextStrokeTransparency = 0.4
    Label.Font = Enum.Font.SourceSansBold
    Label.TextScaled = true
    Label.Parent = Billboard
end

local function checkForPets()
    local found = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name then
            for _, target in pairs(targetPets) do
                if string.lower(obj.Name):find(string.lower(target)) and not obj:FindFirstChild("PetESP") then
                    addESP(obj)
                    table.insert(found, obj.Name)
                    stopHopping = true
                    break
                end
            end
        end
    end
    return found
end

local function createGUI()
    if serverHopButtonGui then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DreamHubGUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = getSafeGuiParent()

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 140)
    frame.Position = UDim2.new(0, 40, 0.4, 0)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Draggable = true
    frame.Active = true
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "🌙 DreamHub"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = frame

    local serverHopBtn = Instance.new("TextButton")
    serverHopBtn.Size = UDim2.new(0.9, 0, 0, 35)
    serverHopBtn.Position = UDim2.new(0.05, 0, 0, 40)
    serverHopBtn.Text = "🔁 ServerHop"
    serverHopBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    serverHopBtn.TextColor3 = Color3.new(1, 1, 1)
    serverHopBtn.Font = Enum.Font.SourceSansBold
    serverHopBtn.TextSize = 18
    serverHopBtn.Parent = frame
    serverHopBtn.MouseButton1Click:Connect(function()
        serverHop(true)
    end)

    local espBtn = Instance.new("TextButton")
    espBtn.Size = UDim2.new(0.9, 0, 0, 35)
    espBtn.Position = UDim2.new(0.05, 0, 0, 85)
    espBtn.Text = "🔦 ESP Jogadores"
    espBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    espBtn.TextColor3 = Color3.new(1, 1, 1)
    espBtn.Font = Enum.Font.SourceSansBold
    espBtn.TextSize = 18
    espBtn.Parent = frame
    espBtn.MouseButton1Click:Connect(function()
        enableESP()
    end)

    serverHopButtonGui = gui
end

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.1)
    if obj:IsA("Model") and obj.Name then
        for _, target in pairs(targetPets) do
            if string.lower(obj.Name):find(string.lower(target)) and not obj:FindFirstChild("PetESP") then
                if not detectedPets[obj.Name] then
                    detectedPets[obj.Name] = true
                    addESP(obj)
                    stopHopping = true
                    createGUI()
                end
                break
            end
        end
    end
end)

task.wait(3)
print("🔍 Procurando... By Haruzx")
local pets = checkForPets()
if #pets > 0 then
    for _, name in ipairs(pets) do
        detectedPets[name] = true
    end
    createGUI()
else
    print("⚙️ Nenhum alvo encontrado...")
    task.delay(1, function()
        serverHop(false)
    end)
end