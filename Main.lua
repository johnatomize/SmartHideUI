local addonName = ...
local controller = CreateFrame("Frame", "SmartHideUIController")
local enabled, delay, lastActivity = true, 3, 0
local hidden = false
local originalAlpha = {}
local unsupportedAlpha = setmetatable({}, { __mode = "k" })
local ApplyCombatUI, ApplyBagUI, ApplyQuestUI, ApplySpellbookUI, ApplyMapUI
local ApplyQuestLogUI, ApplyLootUI, ApplyTradeSkillUI, ApplyTargetUI, ApplyChatUI
local ApplyCharacterUI
local lootOpen = false
local merchantOpen = false
local ApplyMailUI
local mailOpen = false
local mailFrames = { "MailFrame", "OpenMailFrame" }
local ApplyMerchantUI
local questTrackerVisibleUntil = 0
local function NeedsQuestTrackerUI()
    return GetTime() < questTrackerVisibleUntil
end
local tradeSkillFrames = { "TradeSkillFrame", "CraftFrame" }
local function IsTradeSkillOpen()
    for _, name in ipairs(tradeSkillFrames) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end
local extraWindows = { "GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame",
    "ChatConfigFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }
local function HasOpenPanel()
    for name in pairs(UIPanelWindows or {}) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    for _, name in ipairs(extraWindows) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end
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
local function IsCharacterOpen()
    return CharacterFrame and CharacterFrame:IsShown()
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

local function HasEnemyTarget()
    return UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
end

local function HasPortraitTarget()
    return HasEnemyTarget() or (UnitExists("target") and UnitIsPlayer("target")
        and not UnitIsDeadOrGhost("target"))
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

-- Bandaging uses a channel. Compose aura visibility with the existing cast
-- policy without adding action bars or unrelated HUD controls.
local function NeedsAuras()
    return UnitChannelInfo("player") ~= nil or HasPlayerDebuff()
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

local function IsChatting()
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and editBox:HasFocus() then return true end
    end
    return false
end

local chatVisibleUntil = 0
local function NeedsChatUI()
    return IsChatting() or GetTime() < chatVisibleUntil
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
    if enabled and mailOpen then
        if hidden then ApplyMailUI() end
        return
    end
    if enabled and hidden and merchantOpen then
        ApplyMerchantUI()
        return
    end
    if enabled and hidden and (IsTradeSkillOpen()
        or (hidden == "tradeskill" and HasOpenPanel())) then
        ApplyTradeSkillUI()
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
    if enabled and hidden and IsCharacterOpen() then
        ApplyCharacterUI()
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
    if enabled and hidden and HasPortraitTarget() then
        ApplyTargetUI()
        return
    end
    if enabled and hidden and NeedsChatUI() then
        ApplyChatUI()
        return
    end
    -- Opening objects uses a cast. Keep the current hidden policy while its
    -- progress runs, including activity detected by the update loop.
    if enabled and hidden and (NeedsQuestTrackerUI()
        or UnitCastingInfo("player") or UnitChannelInfo("player")) then
        HideUI()
        return
    end
    if enabled and (hidden == "combat" or hidden == "map" or hidden == "questlog" or hidden == "character"
        or hidden == "loot" or hidden == "tradeskill" or hidden == "target" or hidden == "chat"
        or hidden == "merchant" or hidden == "mail") then
        HideUI()
        return
    end
    if hidden then RestoreUI() end
end

-- Some UIParent children expose alpha methods but reject calls on their native
-- object. Probe once, then skip them instead of aborting every update tick.
local function FadeAlpha(region)
    -- Blizzard owns area-text fades in every mode, including open windows.
    -- Never save or overwrite their animated alpha on an update tick.
    if region == ZoneTextFrame or region == SubZoneTextFrame then return end
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

-- Preserve the whole minimap cluster, including its surrounding controls, in
-- every policy. Ancestors only provide visibility; unrelated siblings still fade.
local function ApplyMinimapUI(keep, ancestors)
    for _, name in ipairs({ "MinimapCluster", "Minimap" }) do
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

-- Objective progress is a temporary overlay shared by every hidden policy.
-- Blizzard owns tracker contents and Show/Hide; only restore its saved alpha.
local function ApplyQuestTrackerUI(keep, ancestors)
    if not NeedsQuestTrackerUI() then return end
    for _, name in ipairs({ "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }) do
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
    if region == controller or region == GameTooltip then return end
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
    if mailOpen then
        ApplyMailUI()
        return
    end
    if merchantOpen then
        ApplyMerchantUI()
        return
    end
    if IsTradeSkillOpen() then
        ApplyTradeSkillUI()
        return
    end
    if IsCharacterOpen() then
        ApplyCharacterUI()
        return
    end
    if IsQuestConversationOpen() then
        ApplyQuestUI()
        return
    end
    if HasPortraitTarget() then
        ApplyTargetUI()
        return
    end
    if NeedsChatUI() then
        ApplyChatUI()
        return
    end
    if hidden == "combat" then RestoreUI() end
    hidden = "idle"
    -- Keep UIParent shown so protected action buttons and bindings still work.
    -- Preserve the minimap's parent chain without reparenting Blizzard frames.
    local keepPlayer, playerAncestors = NeedsPlayerFrame(), {}
    local keepAuras, showAuras = {}, NeedsAuras()
    ApplyMinimapUI(keepAuras, playerAncestors)
    ApplyMirrorTimerUI(keepAuras, playerAncestors)
    ApplyCastingUI(keepAuras, playerAncestors)
    ApplyQuestTrackerUI(keepAuras, playerAncestors)
    for _, name in ipairs(auraFrames) do
        local frame = _G[name]
        if frame then
            if not hookedAuraFrames[frame] then
                hooksecurefunc(frame, "SetAlpha", function(aura, alpha)
                    if alpha ~= 0 and enabled and hidden == "idle"
                        and not InCombat() and not NeedsAuras() then
                        FadeAlpha(aura)
                    end
                end)
                hookedAuraFrames[frame] = true
            end
            if showAuras then
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

local function ApplyPartyInviteUI(visibleFrames)
    for index = 1, STATICPOPUP_NUMDIALOGS or 4 do
        local name = "StaticPopup" .. index
        local frame = _G[name]
        if frame and frame:IsShown() and frame.which == "PARTY_INVITE" then
            visibleFrames[#visibleFrames + 1] = name
        end
    end
end

local function ApplyStackSplitUI(visibleFrames)
    -- The quantity picker is a separate UIParent child, not part of the
    -- merchant or bag windows. Preserve it before Blizzard shows it, too.
    if AreBagsOpen() or (MerchantFrame and MerchantFrame:IsShown()) then
        visibleFrames[#visibleFrames + 1] = "StackSplitFrame"
    end
end

local function ApplySelectiveUI(mode)
    if hidden ~= mode then RestoreUI() end
    local keep, ancestors = { [controller] = true }, {}
    ApplyMinimapUI(keep, ancestors)
    ApplyMirrorTimerUI(keep, ancestors)
    ApplyCastingUI(keep, ancestors)
    ApplyQuestTrackerUI(keep, ancestors)
    -- All interactions use standard item and comparison tooltips without
    -- rediscovering tooltip frames across the entire UI on every refresh.
    local visibleFrames = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
    ApplyStackSplitUI(visibleFrames)
    -- Debuffs keep all auras visible in every interaction, including loot.
    if NeedsAuras() then
        for _, name in ipairs(auraFrames) do visibleFrames[#visibleFrames + 1] = name end
    end
    if mode == "combat" then ApplyPartyInviteUI(visibleFrames) end
    local windowMode = mode == "map" or mode == "questlog" or mode == "character"
        or mode == "tradeskill" or mode == "merchant" or mode == "mail"
    local modeFrames = (windowMode or mode == "target" or mode == "chat") and {}
        or mode == "loot" and { "LootFrame" }
        or mode == "quest" and questFrames
        or (mode == "combat" and combatFrames or actionFrames)
    for _, name in ipairs(modeFrames) do
        visibleFrames[#visibleFrames + 1] = name
    end
    -- The opened letter is a separate frame, so preserve it before OnShow.
    -- Mail composes with every active policy, including bags and combat.
    if mailOpen then
        for _, name in ipairs(mailFrames) do visibleFrames[#visibleFrames + 1] = name end
    end
    if merchantOpen and mode ~= "loot" then
        visibleFrames[#visibleFrames + 1] = "MerchantFrame"
        visibleFrames[#visibleFrames + 1] = "StackSplitFrame"
    end
    -- Player targets need their portrait; enemies also need combat controls.
    if mode ~= "combat" and HasPortraitTarget() then
        visibleFrames[#visibleFrames + 1] = "TargetFrame"
    end
    -- Target controls compose with open interactions; combat owns its own HUD.
    if mode ~= "combat" and HasEnemyTarget() then
        visibleFrames[#visibleFrames + 1] = "PlayerFrame"
        for _, name in ipairs(actionFrames) do visibleFrames[#visibleFrames + 1] = name end
    end
    -- Window interactions preserve open panels without revealing the HUD.
    if mode ~= "loot" then
        for _, name in ipairs(tradeSkillFrames) do
            local frame = _G[name]
            if frame and frame:IsShown() then visibleFrames[#visibleFrames + 1] = name end
        end
    end
    if mode ~= "loot" and IsMapOpen() then
        visibleFrames[#visibleFrames + 1] = "WorldMapFrame"
    end
    if mode ~= "loot" and IsQuestLogOpen() then
        visibleFrames[#visibleFrames + 1] = "QuestLogFrame"
    end
    if mode ~= "loot" and IsCharacterOpen() then
        visibleFrames[#visibleFrames + 1] = "CharacterFrame"
    end
    if mode ~= "loot" and (windowMode or IsTradeSkillOpen()
        or AreBagsOpen() or IsMapOpen() or IsQuestLogOpen() or IsCharacterOpen()) then
        for name in pairs(UIPanelWindows or {}) do
            local frame = _G[name]
            if frame and frame:IsShown() then
                visibleFrames[#visibleFrames + 1] = name
            end
        end
        for _, name in ipairs(extraWindows) do
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
    if mode == "chat" and NeedsPlayerFrame() then
        visibleFrames[#visibleFrames + 1] = "PlayerFrame"
    end
    if NeedsChatUI() then
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
ApplyCharacterUI = function() ApplySelectiveUI("character") end
ApplyLootUI = function() ApplySelectiveUI("loot") end
ApplyTradeSkillUI = function() ApplySelectiveUI("tradeskill") end
ApplyTargetUI = function() ApplySelectiveUI("target") end
ApplyChatUI = function() ApplySelectiveUI("chat") end
ApplyMailUI = function() ApplySelectiveUI("mail") end
ApplyMerchantUI = function() ApplySelectiveUI("merchant") end

-- Track the event before Blizzard shows the window or opens bags. Both close
-- notifications may arrive; neither should become generic full-UI activity.
local function MerchantClosed()
    if not merchantOpen then return end
    merchantOpen = false
    if enabled and hidden then
        if hidden == "idle" then HideUI() else Activity() end
    end
end
local hookedMerchant
local function HookMerchant()
    if not MerchantFrame or hookedMerchant == MerchantFrame then return end
    hookedMerchant = MerchantFrame
    MerchantFrame:HookScript("OnShow", function()
        merchantOpen = true
        if enabled and hidden then Activity() end
    end)
    MerchantFrame:HookScript("OnHide", MerchantClosed)
end
HookMerchant()

-- MAIL_SHOW can precede both the mailbox frame and automatically opened bags.
local function MailClosed()
    if not mailOpen then return end
    mailOpen = false
    if enabled and hidden then
        if hidden == "idle" then HideUI() else Activity() end
    end
end
local hookedMail = setmetatable({}, { __mode = "k" })
local function HookMail()
    for _, name in ipairs(mailFrames) do
        local frame = _G[name]
        if frame and not hookedMail[frame] then
            hookedMail[frame] = true
            frame:HookScript("OnShow", function()
                if name == "MailFrame" then mailOpen = true end
                if enabled and hidden and mailOpen then Activity() end
            end)
            if name == "MailFrame" then frame:HookScript("OnHide", MailClosed) end
        end
    end
end
HookMail()

local hookedChatEdits = setmetatable({}, { __mode = "k" })
local function HookChatEdits()
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and not hookedChatEdits[editBox] then
            editBox:HookScript("OnEditFocusGained", function()
                if enabled and hidden then Activity() end
            end)
            local function ChatClosed()
                if not enabled or not hidden then return end
                chatVisibleUntil = math.max(chatVisibleUntil, GetTime() + delay)
                Activity()
            end
            editBox:HookScript("OnEditFocusLost", ChatClosed)
            editBox:HookScript("OnHide", ChatClosed)
            hookedChatEdits[editBox] = true
        end
    end
end
HookChatEdits()

-- The invite event can precede Blizzard showing or assigning a popup slot.
-- Refresh on the actual frame transition so a previously faded slot is usable
-- immediately, and closing it keeps the remaining combat policy in effect.
local hookedPartyPopups = setmetatable({}, { __mode = "k" })
local function HookPartyPopups()
    for index = 1, STATICPOPUP_NUMDIALOGS or 4 do
        local frame = _G["StaticPopup" .. index]
        if frame and not hookedPartyPopups[frame] then
            hookedPartyPopups[frame] = true
            local function Refresh()
                if enabled and InCombat() then ApplyCombatUI() end
            end
            frame:HookScript("OnShow", Refresh)
            frame:HookScript("OnHide", Refresh)
        end
    end
end
HookPartyPopups()

local function TradeSkillClosed()
    if not enabled or not hidden then return end
    -- CLOSE and OnHide can both fire, in either order. Once idle, a second
    -- notification must not count as new activity and restore the whole HUD.
    if hidden == "idle" and not IsTradeSkillOpen() then return end
    Activity()
end

local hookedTradeSkills = setmetatable({}, { __mode = "k" })
local function HookTradeSkills()
    for _, name in ipairs(tradeSkillFrames) do
        local frame = _G[name]
        if frame and not hookedTradeSkills[frame] then
            hookedTradeSkills[frame] = true
            frame:HookScript("OnShow", function()
                if enabled and hidden then Activity() end
            end)
            frame:HookScript("OnHide", TradeSkillClosed)
        end
    end
end
HookTradeSkills()

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

local hookedCharacter
local function HookCharacter()
    if not CharacterFrame or hookedCharacter == CharacterFrame then return end
    hookedCharacter = CharacterFrame
    CharacterFrame:HookScript("OnShow", function()
        if enabled and hidden then
            if InCombat() then ApplyCombatUI()
            elseif lootOpen then ApplyLootUI() else ApplyCharacterUI() end
        end
    end)
    CharacterFrame:HookScript("OnHide", function()
        if enabled and hidden == "character" then Activity() end
    end)
end
HookCharacter()

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
        local current, passiveHover = focus, false
        while current do
            -- The always-visible minimap and its pins only need their tooltip.
            -- Check descendants too, without excluding unrelated UIParent children.
            if current == Minimap or current == MinimapCluster
                or bagButtonAlpha[current] ~= nil then
                passiveHover = true
                break
            end
            current = current:GetParent()
        end
        if focus ~= WorldFrame and focus ~= UIParent and focus ~= controller
            and focus ~= GameTooltip and not passiveHover then
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
    -- Chat bindings run after this callback; focus hooks select the policy.
    -- Suppress both edges, including Enter/Escape after the edit box closes.
    if hidden and (IsChatting() or action == "OPENCHAT" or action == "OPENCHATSLASH"
        or action == "CHATREPLY" or action == "CHATREPLY2") then
        targetClearingKeysDown[key] = true
        return
    end
    -- Action bindings execute after OnKeyDown. Let the resulting cast/channel
    -- or combat event choose visibility, and suppress release after completion.
    if hidden and (action:match("^ACTIONBUTTON%d+$")
        or action:match("^MULTIACTIONBAR%d+BUTTON%d+$")) then
        targetClearingKeysDown[key] = true
        return
    end
    -- Target bindings run after this callback and may find no unit. Neither
    -- key edge should reveal the HUD; PLAYER_TARGET_CHANGED selects the policy.
    if action:match("^TARGET") or action == "ASSISTTARGET" then
        targetClearingKeysDown[key] = true
        return
    end
    -- Escape can close a window, clear the target, or cancel gathering. Suppress
    -- both key edges: the window, target, or cast may be gone on key release.
    if hidden and action == "TOGGLEGAMEMENU"
        and (mailOpen or lootOpen or IsMapOpen() or IsQuestLogOpen() or IsCharacterOpen()
            or IsTradeSkillOpen() or hidden == "tradeskill" or hidden == "character" or UnitExists("target")
            or UnitCastingInfo("player") or UnitChannelInfo("player")) then
        targetClearingKeysDown[key] = true
        return
    end
    -- The binding runs after keyboard activity; wait for the panel's OnShow.
    if action == "TOGGLESPELLBOOK" or action == "TOGGLEPETBOOK"
        or action == "TOGGLEWORLDMAP" or action == "TOGGLEQUESTLOG"
        or action:match("^TOGGLECHARACTER") then return end
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
    "QUEST_WATCH_UPDATE",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_EQUIPMENT_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_SHOW", "CRAFT_CLOSE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_SAY",
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
    HookCharacter()
    HookSpellbook()
    HookLoot()
    HookTradeSkills()
    HookPartyPopups()
    HookChatEdits()
    HookMerchant()
    HookMail()
    if event == "MAIL_SHOW" then
        mailOpen = true
        if enabled and hidden then Activity() end
        return
    elseif event == "MAIL_CLOSED" then
        MailClosed()
        return
    end
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
        if enabled and hidden then Activity() end
        return
    elseif event == "MERCHANT_CLOSED" then
        MerchantClosed()
        return
    end
    -- Unlike QUEST_LOG_UPDATE, this event reports objective progress rather
    -- than general log refreshes. Do not count it as full-UI activity.
    if event == "QUEST_WATCH_UPDATE" then
        if enabled then
            questTrackerVisibleUntil = GetTime() + 3
            if hidden == "idle" then HideUI()
            elseif hidden then ApplySelectiveUI(hidden) end
        end
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        questTrackerVisibleUntil = 0
        merchantOpen = false
        mailOpen = false
    end
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER"
        or event == "CHAT_MSG_SAY" then
        if enabled then
            chatVisibleUntil = GetTime() + 10
            if hidden then Activity() end
        end
        return
    end
    if event == "ADDON_LOADED" then return end
    -- Gathering loot changes inventory even with every bag closed. The delayed
    -- notification can arrive after LOOT_CLOSED; it is not player activity.
    -- Open bags still use their policy, and OnUpdate handles closing them.
    if event == "BAG_UPDATE_DELAYED" and not AreBagsOpen() then return end
    if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        TradeSkillClosed()
        return
    end
    -- Profession events can precede OnShow. Select the policy before activity
    -- gets a chance to restore the HUD; OnShow supplies the actual open frame.
    if enabled and hidden and (event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW") then
        if InCombat() then ApplyCombatUI()
        elseif lootOpen then ApplyLootUI() else ApplyTradeSkillUI() end
        return
    end
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
    if event == "PLAYER_TARGET_CHANGED" then
        if enabled and hidden and (HasPortraitTarget() or hidden == "target") then Activity() end
        return
    end
    -- Quest events can arrive before Blizzard shows the conversation frame.
    if enabled and hidden and not InCombat() and not lootOpen then
        if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE"
            or event == "QUEST_GREETING" or event == "QUEST_PROGRESS"
            or event == "GOSSIP_SHOW" then
            ApplyQuestUI()
            return
        end
    end
    -- Resource and aura changes refresh visibility without resetting idle UI.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
        or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER" or event == "UNIT_AURA" then
        if enabled and hidden then
            if hidden == "idle" then HideUI()
            elseif event == "UNIT_AURA" then ApplySelectiveUI(hidden) end
        end
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
    if questTrackerVisibleUntil > 0 and not NeedsQuestTrackerUI() then
        questTrackerVisibleUntil = 0
        if hidden == "idle" then HideUI() end
    end
    if InCombat() then
        ApplyCombatUI()
        ApplyBagButtons()
        return
    elseif lootOpen then
        if hidden then ApplyLootUI() end
        ApplyBagButtons()
        return
    elseif mailOpen then
        if hidden then ApplyMailUI() end
        ApplyBagButtons()
        return
    elseif hidden and merchantOpen then
        ApplyMerchantUI()
        ApplyBagButtons()
        return
    elseif hidden and (IsTradeSkillOpen()
        or (hidden == "tradeskill" and HasOpenPanel())) then
        ApplyTradeSkillUI()
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
    elseif hidden and IsCharacterOpen() then
        ApplyCharacterUI()
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
    elseif hidden and HasPortraitTarget() then
        ApplyTargetUI()
        ApplyBagButtons()
        return
    elseif hidden and NeedsChatUI() then
        ApplyChatUI()
        ApplyBagButtons()
        return
    elseif hidden == "bags" or hidden == "spellbook" or hidden == "map"
        or hidden == "questlog" or hidden == "character" or hidden == "loot" or hidden == "tradeskill"
        or hidden == "target" or hidden == "chat" or hidden == "merchant" or hidden == "mail" then
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
        questTrackerVisibleUntil = 0
        RestoreUI()
        print("SmartHideUI: UI visas och automatisk döljning är av.")
    elseif command == "delay" and tonumber(value) and tonumber(value) >= 0.5 then
        delay = tonumber(value)
        print("SmartHideUI: fördröjning " .. delay .. " sekunder.")
    else
        print("SmartHideUI: /shu on, /shu off, /shu show, /shu delay 3. Inställningar gäller till nästa /reload.")
    end
end
