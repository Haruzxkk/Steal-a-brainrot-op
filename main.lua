local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

local targetPets = getgenv().TargetPetNames or {}
print("🔧 DreamHub By Haruzx initialized with", #targetPets, "target pets")

local visitedJobIds = {[game.JobId] = true}
local hops = 0
local maxHopsBeforeReset = 50
local teleportFails = 0
local maxTeleportRetries = 3
local detectedPets = {}
local stopHopping = false
local serverHopButton = nil

local function createServerHopButton()
    if serverHopButton then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NotifyBotGUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = (gethui and gethui()) or (syn and syn.protect_gui and syn.protect_gui(CoreGui)) or CoreGui

    local button = Instance.new("TextButton")
    button.Name = "ServerHopButton"
    button.Size = UDim2.new(0, 140, 0, 50)
    button.Position = UDim2.new(0.5, -70, 0.8, 0)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.SourceSansBold
    button.Text = "ServerHop"
    button.TextScaled = true
    button.Active = true
    button.Draggable = true
    button.Parent = gui

    button.MouseButton1Click:Connect(function()
        print("🔘 Botão ServerHop clicado")
        if button then button.Text = "Hopping..." end
        pcall(serverHop)
    end)

    serverHopButton = button
end

function serverHop()
    if stopHopping then return end

    local success, result = pcall(function()
        task.wait(0.5)

        local PlaceId = game.PlaceId
        local JobId = game.JobId
        local cursor = nil
        local tries = 0

        hops += 1
        if hops >= maxHopsBeforeReset then
            visitedJobIds = {[JobId] = true}
            hops = 0
            print("♻️ Resetando servidores visitados.")
        end

        while tries < 3 do
            local url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor then url = url .. "&cursor=" .. cursor end

            local httpSuccess, response = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if httpSuccess and response and response.data then
                local servers = {}
                for _, server in ipairs(response.data) do
                    if tonumber(server.playing or 0) < tonumber(server.maxPlayers or 1)
                        and server.id ~= JobId
                        and not visitedJobIds[server.id] then
                            table.insert(servers, server.id)
                    end
                end

                if #servers > 0 then
                    local picked = servers[math.random(1, #servers)]
                    print("✅ Hopping to:", picked)
                    teleportFails = 0
                    TeleportService:TeleportToPlaceInstance(PlaceId, picked)
                    return
                end

                cursor = response.nextPageCursor
                if not cursor then
                    tries += 1
                    task.wait(0.2)
                end
            else
                warn("⚠️ Erro ao buscar servidores...")
                tries += 1
                task.wait(0.2)
            end
        end

        warn("❌ Sem servidores válidos. Teleporte aleatório...")
        TeleportService:Teleport(PlaceId)
    end)

    if not success then
        warn("❌ Erro no serverHop:", result)
        task.wait(1)
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    end
end

local function addESP(targetModel)
    pcall(function()
        if not targetModel or not targetModel.Parent then return end
        if targetModel:FindFirstChild("PetESP") then return end

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
    end)
end

local function checkForPets()
    local found = {}
    pcall(function()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name then
                local nameLower = obj.Name:lower()
                for _, target in pairs(targetPets) do
                    if target and nameLower:find(target:lower()) and not obj:FindFirstChild("PetESP") then
                        addESP(obj)
                        table.insert(found, obj.Name)
                        stopHopping = true
                        createServerHopButton()
                        break
                    end
                end
            end
        end
    end)
    return found
end

workspace.DescendantAdded:Connect(function(obj)
    task.delay(0.2, function()
        if obj:IsA("Model") and obj.Name then
            local nameLower = obj.Name:lower()
            for _, target in pairs(targetPets) do
                if target and nameLower:find(target:lower()) and not obj:FindFirstChild("PetESP") then
                    if not detectedPets[obj.Name] then
                        detectedPets[obj.Name] = true
                        addESP(obj)
                        createServerHopButton()
                        print("🎯 Pet encontrado:", obj.Name)
                        stopHopping = true
                    end
                    break
                end
            end
        end
    end)
end)

pcall(function()
    task.wait(3)
    print("🔍 Iniciando busca por pets...")
    local petsFound = checkForPets()
    if #petsFound > 0 then
        for _, name in ipairs(petsFound) do
            detectedPets[name] = true
        end
        print("🎯 Pets encontrados:", table.concat(petsFound, ", "))
        createServerHopButton()
    else
        print("🔍 Nenhum pet. Pulando...")
        task.delay(0.75, serverHop)
    end
end)