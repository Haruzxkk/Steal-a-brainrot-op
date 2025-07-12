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
local highlights = {}
local texts = {}
local serverHopButtonGui = nil
local teleportFails = 0
local maxTeleportRetries = 3

local function getSafeGuiParent()
    return (gethui and gethui()) or (syn and syn.protect_gui and syn.protect_gui(CoreGui)) or CoreGui
end

TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    warn("⚠️ Teleporte falhou:", result)

    if teleportFails >= maxTeleportRetries then
        warn("⛔ Muitas falhas de teleporte. Recarregando jogo...")
        teleportFails = 0
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    else
        task.wait(0.5)
        serverHop(true)
    end
end)

function serverHop(force)
    if stopHopping and not force then return end

    local PlaceId, JobId = game.PlaceId, game.JobId
    local attempt, foundServer = 0, false
    local maxAttempts = 15

    while not foundServer and attempt < maxAttempts do
        attempt += 1
        task.wait(0.5)

        local cursor = nil
        local pageTries = 0

        while pageTries < 5 do
            pageTries += 1
            local url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor then url ..= "&cursor=" .. cursor end

            local httpSuccess, response = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if httpSuccess and response and response.data then
                for _, server in ipairs(response.data) do
                    if tonumber(server.playing or 0) < tonumber(server.maxPlayers or 1)
                        and server.id ~= JobId
                        and not visitedJobIds[server.id] then

                        visitedJobIds[server.id] = true
                        hops += 1
                        if hops >= 50 then
                            visitedJobIds = {[JobId] = true}
                            hops = 0
                        end

                        warn("🌐 Tentando servidor:", server.id)
                        TeleportService:TeleportToPlaceInstance(PlaceId, server.id)
                        return
                    end
                end
                cursor = response.nextPageCursor
                if not cursor then break end
            else
                warn("⚠️ Erro na requisição da lista de servidores. Tentando novamente...")
                task.wait(0.2)
            end
        end
    end

    warn("❌ Nenhum servidor válido encontrado. Recarregando...")
    TeleportService:Teleport(PlaceId)
end

local function removeESP(player)
    if highlights[player] then highlights[player]:Destroy() highlights[player] = nil end
    if texts[player] then texts[player]:Remove() texts[player] = nil end
end

local function setupPlayerRemoval()
    Players.PlayerRemoving:Connect(removeESP)
end

function enableESP()
    for _, v in pairs(highlights) do if v then v:Destroy() end end
    for _, v in pairs(texts) do if v then v:Remove() end end
    highlights, texts = {}, {}

    setupPlayerRemoval()

    RunService:UnbindFromRenderStep("ESP")
    RunService:BindToRenderStep("ESP", Enum.RenderPriority.Camera.Value + 1, function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local char = player.Character
                local head = char:FindFirstChild("Head")
                if not head then continue end

                if not highlights[player] then
                    local hl = Instance.new("Highlight")
                    hl.Adornee = char
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.FillTransparency = 0.6
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.OutlineTransparency = 0
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = game:GetService("CoreGui")
                    highlights[player] = hl
                end

                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 2.2, 0))
                if not texts[player] then
                    local label = Drawing.new("Text")
                    label.Size = 18
                    label.Center = true
                    label.Outline = true
                    label.Color = Color3.fromRGB(255, 255, 255)
                    label.Transparency = 1
                    texts[player] = label
                end

                local label = texts[player]
                label.Text = player.Name
                label.Position = Vector2.new(screenPos.X, screenPos.Y)
                label.Visible = onScreen
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

local function buyItem(itemName)
    pcall(function()
        local args = {itemName}
        game:GetService("ReplicatedStorage")
            :WaitForChild("Packages")
            :WaitForChild("Net")
            :WaitForChild("RF/CoinsShopService/RequestBuy")
            :InvokeServer(unpack(args))
    end)
end

local function createGUI()
    if serverHopButtonGui then return end

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local gui = Instance.new("ScreenGui")
    gui.Name = "DreamHubGUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = getSafeGuiParent()

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 40, 0, 40)
    toggleBtn.Position = UDim2.new(0.5, -20, 0, 10)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    toggleBtn.Text = "🌟"
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 20
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.ZIndex = 10
    toggleBtn.AutoButtonColor = true
    toggleBtn.Parent = gui

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 10)
    toggleCorner.Parent = toggleBtn

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 240, 0, 300)
    frame.Position = UDim2.new(0.5, -120, 0.4, 0)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Visible = true
    frame.Parent = gui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 15)
    frameCorner.Parent = frame

    toggleBtn.MouseButton1Click:Connect(function()
        frame.Visible = not frame.Visible
    end)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "🌟 DreamHub"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = frame

    local clickSound = Instance.new("Sound")
    clickSound.SoundId = "rbxassetid://18705898425"
    clickSound.Volume = 1
    clickSound.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local function createButton(label, onClick)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -24, 0, 32)
        btn.Text = label
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        btn.BorderSizePixel = 0
        btn.TextColor3 = Color3.fromRGB(235, 235, 235)
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 15
        btn.AutoButtonColor = true
        btn.Parent = frame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 10)
        btnCorner.Parent = btn

        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        end)
        btn.MouseButton1Click:Connect(function()
            clickSound:Play()
            onClick()
        end)
    end

    createButton("ServerHop", function()
        serverHop(true)
    end)

    createButton("ESP Jogadores", function()
        enableESP()
    end)

    createButton("Medusa's Head", function()
        buyItem("Medusa's Head")
    end)

    createButton("Invisibility Cloak", function()
        buyItem("Invisibility Cloak")
    end)

    createButton("All Seeing Sentry", function()
        buyItem("All Seeing Sentry")
    end)

    createButton("Quantum Cloner", function()
        buyItem("Quantum Cloner")
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