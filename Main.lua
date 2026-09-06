local addonName = ...
local controller = CreateFrame("Frame", "SmartHideUIController")
local enabled, delay, lastActivity = true, 3, 0
local hidden = false
local originalAlpha = {}
local lastX, lastY

local function RestoreUI()
    for region, alpha in pairs(originalAlpha) do
        region:SetAlpha(alpha)
    end
    wipe(originalAlpha)
    hidden = false
end

local function Activity()
    lastActivity = GetTime()
    if hidden then RestoreUI() end
end

local function IsMinimapBranch(region)
    local current = Minimap
    while current do
        if current == region then return true end
        current = current:GetParent()
    end
    return region == MinimapCluster
end

local function FadeRegion(region)
    if region == controller or IsMinimapBranch(region) then return end
    if originalAlpha[region] == nil then
        originalAlpha[region] = region:GetAlpha()
    end
    region:SetAlpha(0)
end

local function HideUI()
    -- Keep UIParent shown so protected action buttons and bindings still work.
    -- Preserve the minimap's parent chain without reparenting Blizzard frames.
    for _, child in ipairs({ UIParent:GetChildren() }) do FadeRegion(child) end
    for _, region in ipairs({ UIParent:GetRegions() }) do FadeRegion(region) end
    hidden = true
end

local function IsShown(name)
    local frame = _G[name]
    return frame and frame:IsShown()
end

local function IsInteracting()
    if InCombatLockdown() or UnitAffectingCombat("player")
        or GetUnitSpeed("player") > 0
        or UnitCastingInfo("player") or UnitChannelInfo("player")
        or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())
        or IsMouseButtonDown() then
        return true
    end
    -- Open panels remain readable even when the mouse stops moving.
    for name in pairs(UIPanelWindows or {}) do
        if IsShown(name) then return true end
    end
    for _, name in ipairs({ "GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame",
        "ContainerFrameCombinedBags", "ChatConfigFrame" }) do
        if IsShown(name) then return true end
    end
    for index = 1, 13 do
        if IsShown("ContainerFrame" .. index) then return true end
    end
    for index = 1, 4 do
        if IsShown("StaticPopup" .. index) then return true end
    end
    local foci = GetMouseFoci and GetMouseFoci()
        or (GetMouseFocus and { GetMouseFocus() }) or {}
    for _, focus in ipairs(foci) do
        if focus ~= WorldFrame and focus ~= UIParent and focus ~= controller then
            return true
        end
    end
    return false
end

controller:EnableKeyboard(true)
controller:SetPropagateKeyboardInput(true)
controller:SetScript("OnKeyDown", Activity)
controller:SetScript("OnKeyUp", Activity)

for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "UPDATE_MOUSEOVER_UNIT",
    "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP", "MODIFIER_STATE_CHANGED",
    "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_DETAIL",
    "QUEST_COMPLETE", "GOSSIP_SHOW", "MERCHANT_SHOW", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}) do
    controller:RegisterEvent(event)
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    controller:RegisterUnitEvent(event, "player")
end
controller:SetScript("OnEvent", function(_, event)
    Activity()
    if event == "PLAYER_LOGIN" then
        print("|cff33ff99" .. addonName .. "|r laddad. UI döljs efter 3 sekunders inaktivitet. /shu för hjälp.")
    end
end)

local elapsedSinceCheck = 0
controller:SetScript("OnUpdate", function(_, elapsed)
    if not enabled then return end
    elapsedSinceCheck = elapsedSinceCheck + elapsed
    if elapsedSinceCheck < 0.05 then return end
    elapsedSinceCheck = 0
    local x, y = GetCursorPosition()
    local mouseMoved = x ~= lastX or y ~= lastY
    lastX, lastY = x, y
    if mouseMoved or IsInteracting() then
        Activity()
    elseif GetTime() - lastActivity >= delay then
        -- Include frames created or shown while already idle.
        HideUI()
    end
end)

SLASH_SMARTHIDEUI1 = "/shu"
SlashCmdList.SMARTHIDEUI = function(message)
    local command, value = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    Activity()
    if command == "on" then
        enabled = true
        print("SmartHideUI: automatisk döljning på.")
    elseif command == "off" or command == "show" then
        enabled = false
        print("SmartHideUI: UI visas och automatisk döljning är av.")
    elseif command == "delay" and tonumber(value) and tonumber(value) >= 0.5 then
        delay = tonumber(value)
        print("SmartHideUI: fördröjning " .. delay .. " sekunder.")
    else
        print("SmartHideUI: /shu on, /shu off, /shu show, /shu delay 3. Inställningar gäller till nästa /reload.")
    end
end
