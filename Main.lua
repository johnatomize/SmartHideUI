local addonName = ...
local controller = CreateFrame("Frame", "SmartHideUIController")
local enabled, delay, lastActivity = true, 3, 0
local hidden = false
local originalAlpha = {}
local unsupportedAlpha = setmetatable({}, { __mode = "k" })
local ApplyCombatUI
local bagButtonAlpha = {}
local bagButtons = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}

local function AreBagsOpen()
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then return true end
    for index = 1, 13 do
        local frame = _G["ContainerFrame" .. index]
        if frame and frame:IsShown() then return true end
    end
    return false
end

local function ApplyBagButtons()
    local show = not enabled or AreBagsOpen()
    for _, name in ipairs(bagButtons) do
        local button = _G[name]
        if button then
            if show then
                if bagButtonAlpha[button] ~= nil then
                    button:SetAlpha(bagButtonAlpha[button])
                    bagButtonAlpha[button] = nil
                end
            else
                if bagButtonAlpha[button] == nil then
                    bagButtonAlpha[button] = button:GetAlpha()
                end
                button:SetAlpha(0)
            end
        end
    end
end

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

local auraFrames = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }
for index = 1, 32 do
    auraFrames[#auraFrames + 1] = "BuffButton" .. index
    auraFrames[#auraFrames + 1] = "DebuffButton" .. index
end
for index = 1, 3 do
    auraFrames[#auraFrames + 1] = "TempEnchant" .. index
end
local hookedAuraFrames = setmetatable({}, { __mode = "k" })

local function HasPlayerDebuff()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex("player", 1, "HARMFUL") ~= nil
    end
    return UnitDebuff("player", 1) ~= nil
end

local function NeedsPlayerFrame()
    if InCombat() then return true end
    if UnitHealth("player") < UnitHealthMax("player") then return true end
    -- Check mana even in shapeshift forms, and energy when it is active.
    if UnitPower("player", 0) < UnitPowerMax("player", 0) then return true end
    local powerType = UnitPowerType("player")
    -- Rage builds from empty: keep the portrait visible until it is spent or decays.
    if powerType == 1 then return UnitPower("player", 1) > 0 end
    return powerType == 3
        and UnitPower("player", 3) < UnitPowerMax("player", 3)
end

local function RestoreUI()
    hidden = false
    for region, alpha in pairs(originalAlpha) do
        pcall(region.SetAlpha, region, alpha)
    end
    wipe(originalAlpha)
    hidden = false
    ApplyBagButtons()
end

local function Activity()
    lastActivity = GetTime()
    if enabled and InCombat() then
        ApplyCombatUI()
        return
    end
    if hidden then RestoreUI() end
end

-- Some UIParent children expose alpha methods but reject calls on their native
-- object. Probe once, then skip them instead of aborting every update tick.
local function FadeAlpha(region)
    if unsupportedAlpha[region] then return end
    if region.IsForbidden and region:IsForbidden() then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    if not ok or type(alpha) ~= "number" then
        unsupportedAlpha[region] = true
        return
    end
    if originalAlpha[region] == nil then
        originalAlpha[region] = bagButtonAlpha[region] or alpha
    end
    if alpha ~= 0 and not pcall(region.SetAlpha, region, 0) then
        originalAlpha[region] = nil
        unsupportedAlpha[region] = true
    end
end

local function IsChatting()
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and editBox:HasFocus() then return true end
    end
    return false
end

local function IsMinimapBranch(region)
    local current = Minimap
    while current do
        if current == region then return true end
        current = current:GetParent()
    end
    return region == MinimapCluster
end

local function FadeRegion(region, playerAncestors, keepPlayer, keepAuras)
    if region == controller or region == GameTooltip or IsMinimapBranch(region) then return end
    -- Blizzard animates these frames' alpha; hiding them every tick causes flicker.
    if region == ZoneTextFrame or region == SubZoneTextFrame then return end
    if (keepPlayer and region == PlayerFrame) or playerAncestors[region] or keepAuras[region] then
        if originalAlpha[region] ~= nil then
            pcall(region.SetAlpha, region, originalAlpha[region])
            originalAlpha[region] = nil
        end
        if (keepPlayer and region == PlayerFrame) or keepAuras[region] then return end
        for _, child in ipairs({ region:GetChildren() }) do
            FadeRegion(child, playerAncestors, keepPlayer, keepAuras)
        end
        for _, texture in ipairs({ region:GetRegions() }) do
            FadeRegion(texture, playerAncestors, keepPlayer, keepAuras)
        end
        return
    end
    FadeAlpha(region)
end

local hookedPlayerFrame
local function HideUI()
    if hidden == "combat" then RestoreUI() end
    hidden = "idle"
    -- Keep UIParent shown so protected action buttons and bindings still work.
    -- Preserve the minimap's parent chain without reparenting Blizzard frames.
    local keepPlayer, playerAncestors = NeedsPlayerFrame(), {}
    local keepAuras, hasDebuff = {}, HasPlayerDebuff()
    for _, name in ipairs(auraFrames) do
        local frame = _G[name]
        if frame then
            if not hookedAuraFrames[frame] then
                hooksecurefunc(frame, "SetAlpha", function(aura, alpha)
                    if alpha ~= 0 and enabled and hidden == "idle"
                        and not InCombat() and not HasPlayerDebuff() then
                        FadeAlpha(aura)
                    end
                end)
                hookedAuraFrames[frame] = true
            end
            if hasDebuff then
                keepAuras[frame] = true
                local parent = frame:GetParent()
                while parent and parent ~= UIParent do
                    playerAncestors[parent] = true
                    parent = parent:GetParent()
                end
            end
        end
    end
    if PlayerFrame then
        if hookedPlayerFrame ~= PlayerFrame then
            hooksecurefunc(PlayerFrame, "SetAlpha", function(frame, alpha)
                if alpha ~= 0 and enabled and hidden == "idle" and not NeedsPlayerFrame() then
                    frame:SetAlpha(0)
                end
            end)
            hookedPlayerFrame = PlayerFrame
        end
        local parent = PlayerFrame:GetParent()
        while keepPlayer and parent and parent ~= UIParent do
            playerAncestors[parent] = true
            parent = parent:GetParent()
        end
        -- Explicitly fade the portrait even if it ignores its parent's alpha.
        FadeRegion(PlayerFrame, playerAncestors, keepPlayer, keepAuras)
    end
    for _, child in ipairs({ UIParent:GetChildren() }) do
        FadeRegion(child, playerAncestors, keepPlayer, keepAuras)
    end
    for _, region in ipairs({ UIParent:GetRegions() }) do
        FadeRegion(region, playerAncestors, keepPlayer, keepAuras)
    end
    -- Aura buttons may ignore parent alpha or be animated by Blizzard.
    for _, name in ipairs(auraFrames) do
        local frame = _G[name]
        if frame then FadeRegion(frame, playerAncestors, keepPlayer, keepAuras) end
    end
    hidden = "idle"
end

-- Keep only these Blizzard controls during combat. Individual main-bar buttons
-- are listed because Classic shares their parent with bags and the micro menu.
local combatFrames = {
    "GameTooltip",
    "ZoneTextFrame", "SubZoneTextFrame",
    "PlayerFrame", "TargetFrame", "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBarFrame", "PetActionBar",
    "StanceBarFrame", "StanceBar", "PossessBarFrame", "PossessActionBar",
    "OverrideActionBar", "ExtraActionBarFrame", "MultiCastActionBarFrame",
    "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
}
for index = 1, 12 do
    combatFrames[#combatFrames + 1] = "ActionButton" .. index
end
-- Older Classic layouts may parent aura buttons directly to UIParent.
for index = 1, 32 do
    combatFrames[#combatFrames + 1] = "BuffButton" .. index
    combatFrames[#combatFrames + 1] = "DebuffButton" .. index
end
for index = 1, 3 do
    combatFrames[#combatFrames + 1] = "TempEnchant" .. index
end

ApplyCombatUI = function()
    if hidden ~= "combat" then RestoreUI() end
    local keep, ancestors = { [controller] = true }, {}
    local visibleFrames = {}
    for _, name in ipairs(combatFrames) do visibleFrames[#visibleFrames + 1] = name end
    if IsChatting() then
        for index = 1, NUM_CHAT_WINDOWS or 10 do
            for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
                visibleFrames[#visibleFrames + 1] = "ChatFrame" .. index .. suffix
            end
        end
        visibleFrames[#visibleFrames + 1] = "GeneralDockManager"
    end
    if AreBagsOpen() then
        for _, name in ipairs(bagButtons) do visibleFrames[#visibleFrames + 1] = name end
    end
    for _, name in ipairs(visibleFrames) do
        local region = _G[name]
        if region then
            keep[region] = true
            local parent = region:GetParent()
            while parent and parent ~= UIParent do
                ancestors[parent] = true
                parent = parent:GetParent()
            end
        end
    end
    local function Visit(region)
        if keep[region] or ancestors[region] then
            if originalAlpha[region] ~= nil then
                pcall(region.SetAlpha, region, originalAlpha[region])
                originalAlpha[region] = nil
            end
            if keep[region] then return end
            for _, child in ipairs({ region:GetChildren() }) do Visit(child) end
            for _, texture in ipairs({ region:GetRegions() }) do Visit(texture) end
        else
            FadeAlpha(region)
        end
    end
    for _, child in ipairs({ UIParent:GetChildren() }) do Visit(child) end
    for _, region in ipairs({ UIParent:GetRegions() }) do Visit(region) end
    hidden = "combat"
end

local function IsShown(name)
    local frame = _G[name]
    return frame and frame:IsShown()
end

local function IsInteracting()
    if IsChatting() then return true end
    if InCombatLockdown() or UnitAffectingCombat("player")
        or UnitCastingInfo("player") or UnitChannelInfo("player")
        or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then
        return true
    end
    -- Open panels remain readable even when the mouse stops moving.
    for name in pairs(UIPanelWindows or {}) do
        if IsShown(name) then return true end
    end
    for _, name in ipairs({ "GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame",
        "ChatConfigFrame" }) do
        if IsShown(name) then return true end
    end
    if AreBagsOpen() then return true end
    for index = 1, 4 do
        if IsShown("StaticPopup" .. index) then return true end
    end
    -- Inspecting a world unit should not reveal the rest of the UI.
    if UnitExists("mouseover") then return false end
    local foci = GetMouseFoci and GetMouseFoci()
        or (GetMouseFocus and { GetMouseFocus() }) or {}
    for _, focus in ipairs(foci) do
        local current, hiddenBagButton = focus, false
        while current do
            if bagButtonAlpha[current] ~= nil then
                hiddenBagButton = true
                break
            end
            current = current:GetParent()
        end
        if focus ~= WorldFrame and focus ~= UIParent and focus ~= controller
            and focus ~= GameTooltip and not hiddenBagButton then
            return true
        end
    end
    return false
end

-- Resolve bindings so custom movement keys also leave the UI hidden.
local movementActions = {
    MOVEFORWARD = true, MOVEBACKWARD = true,
    STRAFELEFT = true, STRAFERIGHT = true, TURNLEFT = true, TURNRIGHT = true,
    JUMP = true, TOGGLEAUTORUN = true, STARTAUTORUN = true, STOPAUTORUN = true,
    PITCHUP = true, PITCHDOWN = true, TOGGLERUN = true,
    SITSTAND = true, ASCEND = true, DESCEND = true,
}
local movementKeysDown = {}
local function KeyboardActivity(_, key)
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT" then return end
    local binding = key
    if IsShiftKeyDown() then binding = "SHIFT-" .. binding end
    if IsControlKeyDown() then binding = "CTRL-" .. binding end
    if IsAltKeyDown() then binding = "ALT-" .. binding end
    if movementActions[GetBindingAction(binding)] then
        movementKeysDown[key] = true
        return
    end
    Activity()
end

controller:EnableKeyboard(true)
controller:SetPropagateKeyboardInput(true)
controller:SetScript("OnKeyDown", KeyboardActivity)
controller:SetScript("OnKeyUp", function(self, key)
    if movementKeysDown[key] then
        movementKeysDown[key] = nil
        return
    end
    KeyboardActivity(self, key)
    movementKeysDown[key] = nil
end)

for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    -- Movement and world mouse buttons (including mouse steering) do not reveal UI.
    "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_DETAIL",
    "QUEST_COMPLETE", "GOSSIP_SHOW", "MERCHANT_SHOW", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}) do
    controller:RegisterEvent(event)
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_AURA",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    controller:RegisterUnitEvent(event, "player")
end
controller:SetScript("OnEvent", function(_, event)
    -- Resource and aura changes refresh visibility without resetting idle UI.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
        or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER" or event == "UNIT_AURA" then
        if enabled and hidden == "idle" then HideUI() end
        return
    end
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
    if InCombat() then
        ApplyCombatUI()
        ApplyBagButtons()
        return
    elseif hidden == "combat" then
        Activity()
    end
    -- Cursor movement alone must not reveal the UI while inspecting the world.
    if IsInteracting() then
        Activity()
    elseif GetTime() - lastActivity >= delay then
        -- Include frames created or shown while already idle.
        HideUI()
    end
    ApplyBagButtons()
end)

SLASH_SMARTHIDEUI1 = "/shu"
SlashCmdList.SMARTHIDEUI = function(message)
    local command, value = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    Activity()
    if command == "on" then
        enabled = true
        Activity()
        print("SmartHideUI: automatisk döljning på.")
    elseif command == "off" or command == "show" then
        enabled = false
        RestoreUI()
        print("SmartHideUI: UI visas och automatisk döljning är av.")
    elseif command == "delay" and tonumber(value) and tonumber(value) >= 0.5 then
        delay = tonumber(value)
        print("SmartHideUI: fördröjning " .. delay .. " sekunder.")
    else
        print("SmartHideUI: /shu on, /shu off, /shu show, /shu delay 3. Inställningar gäller till nästa /reload.")
    end
end
