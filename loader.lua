local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer

local success, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not success or not Rayfield then
    warn("[ Error]: Executor blocked UI. Please use a supported executor for the menu.")
    return
end

local Window = Rayfield:CreateWindow({
    Name = "Project Delta | Auto-Sorter",
    LoadingTitle = "Organizing Stash & Backpack...",
    LoadingSubtitle = "",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local SortTab = Window:CreateTab("Sorting 📦")

_G.SorterSettings = {
    TrashThreshold = 1000,
    MoveDelay = 0.01
}

local categoryOrder = {
    "Keys","Weapons","Attachments","Ammo","Magazines","Armor","Clothing",
    "Backpacks","Fabrics","Utility","Medical","Treasure","Trash","Rubles"
}

local function getRank(cat)
    for i, v in ipairs(categoryOrder) do if v == cat then return i end end
    return 999
end

local function getItemProperties(itemName)
    local itemsList = ReplicatedStorage:FindFirstChild("ItemsList")
    if not itemsList then return nil end
    local entry = itemsList:FindFirstChild(itemName)
    if not entry then return nil end
    local props = entry:FindFirstChild("ItemProperties")
    if not props then return nil end
    
    local itemType = props:GetAttribute("ItemType") or (props:FindFirstChild("ItemType") and props.ItemType.Value) or ""
    local slotType = props:GetAttribute("SlotType") or (props:FindFirstChild("SlotType") and props.SlotType.Value) or ""
    local cost = tonumber(props:GetAttribute("Cost") or props:GetAttribute("Price")) or 0
    return {ItemType = itemType, SlotType = slotType, Cost = cost}
end

local function getCategory(name, props)
    if not props then return "Trash" end
    local t, s, c = props.ItemType, props.SlotType, props.Cost
    if t == "Material" and name == "Rubles" then return "Rubles"
    elseif t == "Key" or t == "Keycard" then return "Keys"
    elseif t == "Ammo" then return "Ammo"
    elseif t == "Magazine" then return "Magazines"
    elseif (t == "RangedWeapon" and s ~= "FlareGun") or t == "Grenade" then return "Weapons"
    elseif t == "Handle" or t == "Stock" or t == "Front" or t == "Muzzle" or t == "Sight" or t == "Extra" then return "Attachments"
    elseif (t == "Clothing" and (s == "ClothingChestRig" or s == "ClothingHeadware" or s == "ClothingLegArmor")) or t == "Visor" then return "Armor"
    elseif (t == "Clothing" and (s == "ClothingMask" or s == "ClothingShirt" or s == "ClothingPants" or s == "ClothingGloves")) or t == "Filter" then return "Clothing"
    elseif t == "Clothing" and s == "ClothingBackpack" then return "Backpacks"
    elseif t == "Barter" and string.find(name, "Fabric") then return "Fabrics"
    elseif t == "Medical" then return "Medical"
    elseif t == "Equipment" or t == "Buildable" or t == "RepairKit" then return "Utility"
    else return c > _G.SorterSettings.TrashThreshold and "Treasure" or "Trash" end
end

local function SortItemArray(itemsArray)
    local nonRubles, rubles = {}, {}
    for _, item in ipairs(itemsArray) do
        if item.cat == "Rubles" then table.insert(rubles, item) else table.insert(nonRubles, item) end
    end

    table.sort(nonRubles, function(a, b)
        if a.cat ~= b.cat then return getRank(a.cat) < getRank(b.cat) end
        if a.cat == "Treasure" and a.cost ~= b.cost then return a.cost > b.cost end
        local groupA = a.name .. "|" .. a.skin
        local groupB = b.name .. "|" .. b.skin
        if groupA ~= groupB then return groupA < groupB end
        if a.durability ~= b.durability then return a.durability > b.durability end
        if a.loadedAmmo ~= b.loadedAmmo then return a.loadedAmmo > b.loadedAmmo end
        if a.amount ~= b.amount then return a.amount > b.amount end
        return false
    end)
    table.sort(rubles, function(a, b) return a.amount > b.amount end)

    local finalOrder = {}
    for _, item in ipairs(nonRubles) do finalOrder[#finalOrder+1] = item.obj end
    for _, item in ipairs(rubles) do finalOrder[#finalOrder+1] = item.obj end
    return finalOrder, #rubles
end

local function SortContainerFolder(folderInstance, maxSlotsOverride)
    local remote = ReplicatedStorage.Remotes:FindFirstChild("InventoryMove")
    if not remote or not folderInstance then return end

    local items, slotToItem, itemToSlot = {}, {}, {}
    local prefix = nil
    local detectedMaxSlot = 0

    for _, obj in ipairs(folderInstance:GetChildren()) do
        local slot = obj:GetAttribute("Slot")
        if slot then
            local p, numStr = slot:match("^([a-zA-Z]+)(%d+)$") 
            if p and numStr then
                prefix = p
                local num = tonumber(numStr)
                if num > detectedMaxSlot then detectedMaxSlot = num end
                table.insert(items, obj)
                slotToItem[slot] = obj
                itemToSlot[obj] = slot
            end
        end
    end

    if #items == 0 or not prefix then return end
    local maxSlot = maxSlotsOverride or detectedMaxSlot

    local enriched = {}
    for _, obj in ipairs(items) do
        local props = getItemProperties(obj.Name)
        table.insert(enriched, {
            obj = obj, name = obj.Name, slot = itemToSlot[obj], cat = getCategory(obj.Name, props),
            cost = props and props.Cost or 0, durability = obj:GetAttribute("Durability") or 0,
            skin = obj:GetAttribute("Skin") or "", loadedAmmo = obj:GetAttribute("LoadedAmmo") or 0,
            amount = obj:GetAttribute("Amount") or 1,
        })
    end

    local finalOrder, rubleCount = SortItemArray(enriched)

    local targetSlotMap = {}
    local nonRubleCount = #finalOrder - rubleCount
    
    for i = 1, nonRubleCount do
        targetSlotMap[finalOrder[i]] = prefix .. i
    end
    
    local rublesStart = maxSlot - rubleCount + 1
    for i = 1, rubleCount do
        targetSlotMap[finalOrder[nonRubleCount + i]] = prefix .. (rublesStart + i - 1)
    end

    for _, obj in ipairs(finalOrder) do
        local target = targetSlotMap[obj]
        local currentSlot = itemToSlot[obj]
        
        if target and currentSlot ~= target then
            local currentOccupant = slotToItem[target]
            remote:FireServer(currentSlot, target, folderInstance, folderInstance, nil)
            task.wait(_G.SorterSettings.MoveDelay)
            
            if currentOccupant then
                slotToItem[target] = obj
                slotToItem[currentSlot] = currentOccupant
                itemToSlot[obj] = target
                itemToSlot[currentOccupant] = currentSlot
            else
                slotToItem[target] = obj
                slotToItem[currentSlot] = nil
                itemToSlot[obj] = target
            end
        end
    end
end

local function SortPersonalInventory()
    local invFolder = ReplicatedStorage.Players:FindFirstChild(player.Name) and ReplicatedStorage.Players[player.Name]:FindFirstChild("Inventory")
    if not invFolder then return end

    for _, container in pairs(invFolder:GetChildren()) do
        local innerInv = container:FindFirstChild("Inventory")
        if innerInv then
            SortContainerFolder(innerInv, nil) 
        end
    end
    Rayfield:Notify({Title = "Success", Content = "Personal Inventory Sorted!", Duration = 3})
end

local function SortVault()
    local vault = ReplicatedStorage.Players:FindFirstChild(player.Name) and ReplicatedStorage.Players[player.Name]:FindFirstChild("VaultStorage")
    if not vault then 
        Rayfield:Notify({Title = "Error", Content = "Vault not found. Are you near your stash?", Duration = 3})
        return 
    end
    
    local inventory = vault:FindFirstChild("Inventory")
    if inventory then
        SortContainerFolder(inventory, 200)
        Rayfield:Notify({Title = "Success", Content = "Vault Sorted!", Duration = 3})
    end
end

SortTab:CreateSection("Auto-Sorters")

SortTab:CreateButton({
    Name = "Sort Personal Inventory (Bags/Rigs)",
    Callback = function()
        Rayfield:Notify({Title = "Sorting", Content = "Packing Backpack and Rigs...", Duration = 2})
        task.spawn(SortPersonalInventory)
    end
})

SortTab:CreateButton({
    Name = "Sort Vault Stash",
    Callback = function()
        Rayfield:Notify({Title = "Sorting", Content = "Sorting vault, please do not move items...", Duration = 2})
        task.spawn(SortVault)
    end
})

SortTab:CreateSection("Configuration")

SortTab:CreateSlider({ Name = "Move Delay (Anti-Kick)", Range = {0.01, 0.50}, Increment = 0.01, Suffix = "s", CurrentValue = 0.05, Flag = "SortDelay", Callback = function(v) _G.SorterSettings.MoveDelay = v end })
SortTab:CreateSlider({ Name = "Treasure Cost Threshold", Range = {0, 5000}, Increment = 100, Suffix = " Rubles", CurrentValue = 1000, Flag = "SortThreshold", Callback = function(v) _G.SorterSettings.TrashThreshold = v end })

print(" [!] Private Auto-Sorter Loaded.")
