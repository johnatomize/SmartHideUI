local addonName = ...
local controller = CreateFrame("Frame", "SmartHideUIController")
local enabled, delay, lastActivity = true, 3, 0
local hidden = false
local originalAlpha = {}
local unsupportedAlpha = setmetatable({}, { __mode = "k" })
local ApplyCombatUI, ApplyBagUI, ApplyQuestUI, ApplySpellbookUI, ApplyMapUI
local ApplyQuestLogUI, ApplyLootUI
local lootOpen = false
local HideUI
local function IsQuestLogOpen()
    return QuestLogFrame and QuestLogFrame:IsShown()
end
local function IsMapOpen()
    return WorldMapFrame and WorldMapFrame:IsShown()
end
local function IsSpellbookOpen()
    return SpellBookFrame and SpellBookFrame:IsShown()
end
local questFrames = { "QuestFrame", "GossipFrame" }
local function IsQuestConversationOpen()
    for _, name in ipairs(questFrames) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end
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
    local show = not enabled or (hidden ~= "quest" and hidden ~= "loot" and AreBagsOpen())
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
    if enabled and lootOpen then
        if hidden then ApplyLootUI() end
        return
    end
    if enabled and hidden and IsMapOpen() then
        ApplyMapUI()
        return
    end
    if enabled and hidden and IsQuestLogOpen() then
        ApplyQuestLogUI()
        return
    end
    if enabled and hidden and (hidden == "spellbook" or IsSpellbookOpen()) then
        ApplySpellbookUI()
        return
    end
    if enabled and hidden and (hidden == "quest" or IsQuestConversationOpen()) then
        ApplyQuestUI()
        return
    end
    if enabled and AreBagsOpen() then
        ApplyBagUI()
        return
    end
    -- Opening objects uses a cast. Keep the current hidden policy while its
    -- progress runs, including activity detected by the update loop.
    if enabled and hidden and (UnitCastingInfo("player") or UnitChannelInfo("player")) then
        HideUI()
        return
    end
    if enabled and (hidden == "combat" or hidden == "map" or hidden == "questlog"
        or hidden == "loot") then
        HideUI()
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

-- Breath can occupy any mirror timer slot. Preserve these warning bars even
-- before they are shown, so submerging while idle never inherits a faded bar.
-- Blizzard still controls when the timers appear and disappear.
local function ApplyMirrorTimerUI(keep, ancestors)
    for index = 1, MIRRORTIMER_NUMTIMERS or 3 do
        local frame = _G["MirrorTimer" .. index]
        if frame then
            keep[frame] = true
            local parent = frame:GetParent()
            while parent and parent ~= UIParent do
                ancestors[parent] = true
                parent = parent:GetParent()
            end
        end
    end
end

local function ApplyCastingUI(keep, ancestors)
    -- Preserve the bar before OnShow; Blizzard owns its progress and fade-out.
    for _, name in ipairs({ "CastingBarFrame", "PlayerCastingBarFrame" }) do
        local frame = _G[name]
        if frame then
            keep[frame] = true
            local parent = frame:GetParent()
            while parent and parent ~= UIParent do
                ancestors[parent] = true
                parent = parent:GetParent()
            end
        end
    end
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
HideUI = function()
    if IsQuestConversationOpen() then
        ApplyQuestUI()
        return
    end
    if hidden == "combat" then RestoreUI() end
    hidden = "idle"
    -- Keep UIParent shown so protected action buttons and bindings still work.
    -- Preserve the minimap's parent chain without reparenting Blizzard frames.
    local keepPlayer, playerAncestors = NeedsPlayerFrame(), {}
    local keepAuras, hasDebuff = {}, HasPlayerDebuff()
    ApplyMirrorTimerUI(keepAuras, playerAncestors)
    ApplyCastingUI(keepAuras, playerAncestors)
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

-- Share action controls between bag, spellbook and combat modes. Individual main-bar buttons
-- are listed because Classic shares their parent with bags and the micro menu.
local actionFrames = {
    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBarFrame", "PetActionBar",
    "StanceBarFrame", "StanceBar", "PossessBarFrame", "PossessActionBar",
    "OverrideActionBar", "ExtraActionBarFrame", "MultiCastActionBarFrame",
    "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
}
for index = 1, 12 do
    actionFrames[#actionFrames + 1] = "ActionButton" .. index
end
local combatFrames = {
    "GameTooltip", "ZoneTextFrame", "SubZoneTextFrame",
    "PlayerFrame", "TargetFrame", "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
}
for _, name in ipairs(actionFrames) do combatFrames[#combatFrames + 1] = name end
-- Older Classic layouts may parent aura buttons directly to UIParent.
for index = 1, 32 do
    combatFrames[#combatFrames + 1] = "BuffButton" .. index
    combatFrames[#combatFrames + 1] = "DebuffButton" .. index
end
for index = 1, 3 do
    combatFrames[#combatFrames + 1] = "TempEnchant" .. index
end

-- NPC reward tooltips may include additional comparison/addon tooltips. Keep
-- every tooltip branch, including its ancestors, without touching its alpha
-- again once restored. Blizzard owns tooltip visibility and fade animations.
local function ApplyQuestTooltips(keep, ancestors)
    local function Visit(frame)
        if frame.IsForbidden and frame:IsForbidden() then return end
        if frame:IsObjectType("GameTooltip") then
            keep[frame] = true
            local parent = frame:GetParent()
            while parent and parent ~= UIParent do
                ancestors[parent] = true
                parent = parent:GetParent()
            end
            return
        end
        for _, child in ipairs({ frame:GetChildren() }) do Visit(child) end
    end
    Visit(UIParent)
end

local function ApplySelectiveUI(mode)
    if hidden ~= mode then RestoreUI() end
    local keep, ancestors = { [controller] = true }, {}
    ApplyMirrorTimerUI(keep, ancestors)
    ApplyCastingUI(keep, ancestors)
    if mode == "quest" or IsQuestConversationOpen() then
        ApplyQuestTooltips(keep, ancestors)
    end
    -- Equipment comparisons use separate tooltips from the hovered item.
    local visibleFrames = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
    local windowMode = mode == "map" or mode == "questlog"
    local modeFrames = windowMode and {}
        or mode == "loot" and { "LootFrame" }
        or mode == "quest" and questFrames
        or (mode == "combat" and combatFrames or actionFrames)
    for _, name in ipairs(modeFrames) do
        visibleFrames[#visibleFrames + 1] = name
    end
    -- Bags, map and quest log preserve open windows without revealing the HUD.
    if mode ~= "loot" and IsMapOpen() then
        visibleFrames[#visibleFrames + 1] = "WorldMapFrame"
    end
    if mode ~= "loot" and IsQuestLogOpen() then
        visibleFrames[#visibleFrames + 1] = "QuestLogFrame"
    end
    if mode ~= "loot" and (AreBagsOpen() or IsMapOpen() or IsQuestLogOpen()) then
        for name in pairs(UIPanelWindows or {}) do
            local frame = _G[name]
            if frame and frame:IsShown() then
                visibleFrames[#visibleFrames + 1] = name
            end
        end
        for _, name in ipairs({ "GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame",
            "ChatConfigFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }) do
            local frame = _G[name]
            if frame and frame:IsShown() then visibleFrames[#visibleFrames + 1] = name end
        end
    end
    if windowMode and (IsSpellbookOpen() or AreBagsOpen()) then
        for _, name in ipairs(actionFrames) do visibleFrames[#visibleFrames + 1] = name end
    end
    -- Compose the spellbook with quest, bag and combat controls when they overlap.
    if mode ~= "loot" and IsSpellbookOpen() then
        visibleFrames[#visibleFrames + 1] = "SpellBookFrame"
        if mode == "quest" then
            for _, name in ipairs(actionFrames) do visibleFrames[#visibleFrames + 1] = name end
        end
    end
    if mode ~= "loot" and mode ~= "quest" and IsQuestConversationOpen() then
        for _, name in ipairs(questFrames) do visibleFrames[#visibleFrames + 1] = name end
    end
    if mode == "combat" and IsChatting() then
        for index = 1, NUM_CHAT_WINDOWS or 10 do
            for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
                visibleFrames[#visibleFrames + 1] = "ChatFrame" .. index .. suffix
            end
        end
        visibleFrames[#visibleFrames + 1] = "GeneralDockManager"
    end
    -- Combat takes priority, but must still allow looting and open bags.
    if mode == "combat" and lootOpen then
        visibleFrames[#visibleFrames + 1] = "LootFrame"
    end
    if mode ~= "quest" and AreBagsOpen() then
        if mode ~= "loot" then
            for _, name in ipairs(bagButtons) do visibleFrames[#visibleFrames + 1] = name end
        end
        visibleFrames[#visibleFrames + 1] = "ContainerFrameCombinedBags"
        for index = 1, 13 do
            visibleFrames[#visibleFrames + 1] = "ContainerFrame" .. index
        end
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
    hidden = mode
end

ApplyCombatUI = function() ApplySelectiveUI("combat") end
ApplyBagUI = function() ApplySelectiveUI("bags") end
ApplyQuestUI = function() ApplySelectiveUI("quest") end
ApplySpellbookUI = function() ApplySelectiveUI("spellbook") end
ApplyMapUI = function() ApplySelectiveUI("map") end
ApplyQuestLogUI = function() ApplySelectiveUI("questlog") end
ApplyLootUI = function() ApplySelectiveUI("loot") end

local hookedLoot
local function HookLoot()
    if not LootFrame or hookedLoot == LootFrame then return end
    hookedLoot = LootFrame
    LootFrame:HookScript("OnShow", function()
        lootOpen = true
        Activity()
    end)
    LootFrame:HookScript("OnHide", function()
        if not lootOpen then return end
        lootOpen = false
        Activity()
    end)
end
HookLoot()

local hookedQuestLog
local function HookQuestLog()
    if not QuestLogFrame or hookedQuestLog == QuestLogFrame then return end
    hookedQuestLog = QuestLogFrame
    QuestLogFrame:HookScript("OnShow", function()
        if enabled and hidden then
            if InCombat() then ApplyCombatUI()
            elseif lootOpen then ApplyLootUI()
            elseif IsMapOpen() then ApplyMapUI()
            else ApplyQuestLogUI() end
        end
    end)
end
HookQuestLog()

local hookedMap
local function HookMap()
    if not WorldMapFrame or hookedMap == WorldMapFrame then return end
    hookedMap = WorldMapFrame
    WorldMapFrame:HookScript("OnShow", function()
        if enabled and hidden then
            if InCombat() then ApplyCombatUI()
            elseif lootOpen then ApplyLootUI() else ApplyMapUI() end
        end
    end)
end
HookMap()

local hookedSpellbook
local function HookSpellbook()
    if not SpellBookFrame or hookedSpellbook == SpellBookFrame then return end
    hookedSpellbook = SpellBookFrame
    SpellBookFrame:HookScript("OnShow", function()
        if enabled and hidden then
            if InCombat() then ApplyCombatUI()
            elseif lootOpen then ApplyLootUI() else ApplySpellbookUI() end
        end
    end)
end
HookSpellbook()

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
local targetClearingKeysDown = {}
local function KeyboardActivity(_, key)
    if targetClearingKeysDown[key] then return end
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT" then return end
    local binding = key
    if IsShiftKeyDown() then binding = "SHIFT-" .. binding end
    if IsControlKeyDown() then binding = "CTRL-" .. binding end
    if IsAltKeyDown() then binding = "ALT-" .. binding end
    local action = GetBindingAction(binding)
    -- Escape can close a window or clear the target. Suppress both key edges,
    -- since the window or target may already be gone when the key is released.
    if hidden and action == "TOGGLEGAMEMENU"
        and (lootOpen or IsMapOpen() or IsQuestLogOpen() or UnitExists("target")) then
        targetClearingKeysDown[key] = true
        return
    end
    -- The binding runs after keyboard activity; wait for the panel's OnShow.
    if action == "TOGGLESPELLBOOK" or action == "TOGGLEPETBOOK"
        or action == "TOGGLEWORLDMAP" or action == "TOGGLEQUESTLOG" then return end
    if hidden and (action == "INTERACTTARGET" or action == "INTERACTMOUSEOVER") then
        return
    end
    -- Let the bag update select visibility after the binding opens/closes it.
    if action == "TOGGLEBACKPACK" or action == "OPENALLBAGS"
        or action == "TOGGLEBAG1" or action == "TOGGLEBAG2"
        or action == "TOGGLEBAG3" or action == "TOGGLEBAG4" then return end
    if movementActions[action] then
        movementKeysDown[key] = true
        return
    end
    Activity()
end

controller:EnableKeyboard(true)
controller:SetPropagateKeyboardInput(true)
controller:SetScript("OnKeyDown", KeyboardActivity)
controller:SetScript("OnKeyUp", function(self, key)
    if targetClearingKeysDown[key] then
        targetClearingKeysDown[key] = nil
        return
    end
    if movementKeysDown[key] then
        movementKeysDown[key] = nil
        return
    end
    KeyboardActivity(self, key)
    movementKeysDown[key] = nil
end)

for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ADDON_LOADED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    -- Movement and world mouse buttons (including mouse steering) do not reveal UI.
    "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_DETAIL",
    "QUEST_COMPLETE", "QUEST_GREETING", "QUEST_PROGRESS", "GOSSIP_SHOW",
    "MERCHANT_SHOW", "PLAYER_EQUIPMENT_CHANGED",
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
    HookMap()
    HookQuestLog()
    HookSpellbook()
    HookLoot()
    if event == "ADDON_LOADED" then return end
    -- Cast completion can precede LOOT_OPENED, and cancelled casts may never
    -- open loot. Neither case should restore the HUD in that gap.
    if enabled and hidden and event:match("^UNIT_SPELLCAST_") then
        if InCombat() then ApplyCombatUI()
        elseif hidden == "idle" then HideUI() end
        return
    end
    -- Record loot before Blizzard shows its frame; close without restoring the HUD.
    if event == "LOOT_OPENED" then lootOpen = true end
    -- OnHide and LOOT_CLOSED may both fire, in either order.
    if event == "LOOT_CLOSED" and not lootOpen then return end
    if event == "LOOT_CLOSED" or event == "PLAYER_LEAVING_WORLD" then lootOpen = false end
    -- Manual deselection and automatic target loss on death are not activity.
    if event == "PLAYER_TARGET_CHANGED" and not UnitExists("target") then return end
    -- Quest events can arrive before Blizzard shows the conversation frame.
    if enabled and hidden and not InCombat() and not lootOpen then
        if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE"
            or event == "QUEST_GREETING" or event == "QUEST_PROGRESS"
            or event == "GOSSIP_SHOW" then
            ApplyQuestUI()
            return
        end
        -- Selecting a quest giver or corpse can precede its interaction window.
        if event == "PLAYER_TARGET_CHANGED" and UnitExists("target")
            and not UnitIsPlayer("target")
            and (UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target")) then
            return
        end
    end
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
    elseif lootOpen then
        if hidden then ApplyLootUI() end
        ApplyBagButtons()
        return
    elseif hidden and IsMapOpen() then
        ApplyMapUI()
        ApplyBagButtons()
        return
    elseif hidden and IsQuestLogOpen() then
        ApplyQuestLogUI()
        ApplyBagButtons()
        return
    elseif hidden and IsSpellbookOpen() then
        ApplySpellbookUI()
        ApplyBagButtons()
        return
    elseif hidden and IsQuestConversationOpen() then
        ApplyQuestUI()
        ApplyBagButtons()
        return
    elseif hidden == "quest" then
        RestoreUI()
        if AreBagsOpen() then ApplyBagUI() else HideUI() end
        ApplyBagButtons()
        return
    elseif AreBagsOpen() then
        ApplyBagUI()
        ApplyBagButtons()
        return
    elseif hidden == "bags" or hidden == "spellbook" or hidden == "map"
        or hidden == "questlog" or hidden == "loot" then
        RestoreUI()
        HideUI()
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
