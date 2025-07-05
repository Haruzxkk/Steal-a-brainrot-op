local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

local targetPets = getgenv().TargetPetNames or {}

print("🔧 DreamHub initialized with", #targetPets, "target pets")

local visitedJobIds = {[game.JobId] = true}
local hops = 0
local maxHopsBeforeReset = 50

local teleportFails = 0
local maxTeleportRetries = 3

local detectedPets = {}
local stopHopping = false

TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    warn("⚠️ Teleport error:", result)

    if teleportFails >= maxTeleportRetries then  
        warn("⚠️ Too many teleport fails. Forcing fresh server...")  
        teleportFails = 0  
        task.wait(0.5)  
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    else  
        task.wait(0.5)  
        pcall(serverHop)
    end
end)

local function addESP(targetModel)
    pcall(function()
        if not targetModel or not targetModel.Parent then return end
        if targetModel:FindFirstChild("PetESP") then return end

        local Billboard = Instance.new("BillboardGui")
        Billboard.Name = "PetESP"
        Billboard.Adornee = targetModel
        Billboard.Size = UDim2.new(0, 100, 0, 30)
        Billboard.StudsOffset = Vector3.new(0, 3, 0)
        Billboard.AlwaysOnTop = true
        Billboard.Parent = targetModel

        local Label = Instance.new("TextLabel")  
        Label.Size = UDim2.new(1, 0, 1, 0)  
        Label.BackgroundTransparency = 1  
        Label.Text = "🎯 (" .. targetModel.Name .. ")"  
        Label.TextColor3 = Color3.fromRGB(255, 0, 0)  
        Label.TextStrokeTransparency = 0.5  
        Label.Font = Enum.Font.SourceSansBold  
        Label.TextScaled = true  
        Label.Parent = Billboard
    end)
end

local function checkForPets()
    local found = {}
    pcall(function()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj and obj:IsA("Model") and obj.Name then
                local nameLower = string.lower(obj.Name)
                for _, target in pairs(targetPets) do
                    if target and string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                        addESP(obj)
                        table.insert(found, obj.Name)
                        stopHopping = true
                        break
                    end
                end
            end
        end
    end)
    return found
end

function serverHop()
    if stopHopping then return end

    local success, result = pcall(function()
        task.wait(0.5)

        local cursor = nil  
        local PlaceId, JobId = game.PlaceId, game.JobId  
        local tries = 0  

        hops += 1  
        if hops >= maxHopsBeforeReset then  
            visitedJobIds = {[JobId] = true}  
            hops = 0  
            print("♻️ Resetting visited JobIds.")  
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
                    print("✅ Hopping to server:", picked)  
                    teleportFails = 0  
                    TeleportService:TeleportToPlaceInstance(PlaceId, picked)  
                    return  
                end  

                cursor = response.nextPageCursor  
                if not cursor then  
                    tries += 1  
                    cursor = nil  
                    task.wait(0.25)  
                end  
            else  
                warn("⚠️ Failed to fetch server list. Retrying...")  
                tries += 1  
                task.wait(0.25)  
            end  
        end  

        warn("❌ No valid servers found. Forcing random teleport...")  
        TeleportService:Teleport(PlaceId)
    end)

    if not success then
        warn("❌ Error in serverHop function:", result)
        task.wait(1)
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    end
end

workspace.DescendantAdded:Connect(function(obj)
    pcall(function()
        task.wait(0.15)
        if obj and obj:IsA("Model") and obj.Name then
            local nameLower = string.lower(obj.Name)
            for _, target in pairs(targetPets) do
                if target and string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                    if not detectedPets[obj.Name] then
                        detectedPets[obj.Name] = true
                        addESP(obj)
                        print("🎯 New pet appeared:", obj.Name)
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
    print("🔍 Starting pet detection...")
    local petsFound = checkForPets()
    if #petsFound > 0 then
        for _, name in ipairs(petsFound) do
            detectedPets[name] = true
        end
        print("🎯 Found pet(s):", table.concat(petsFound, ", "))
    else
        print("🔍 No target pets found. Hopping to next server...")
        task.delay(0.75, serverHop)
    end
end)