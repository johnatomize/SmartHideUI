-- Lua 5.1: run from the addon directory with "lua tests/tests.lua".
-- A caller may supply addon source as the chunk argument for baseline checks.
local source = ...
if not source then
    local file = assert(io.open("Main.lua", "r"))
    source = file:read("*a")
    file:close()
end

local function setup(visible)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local s = { time = 0, combat = false, binding = "" }
    local methods = {}
    function methods:GetAlpha() return self.alpha end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:GetParent() return self.parent end
    function methods:GetChildren() return unpack(self.children) end
    function methods:GetRegions() return unpack(self.regions) end
    function methods:IsShown() return self.shown end
    function methods:IsObjectType(kind) return self.kind == kind end
    function methods:IsForbidden() return false end
    function methods:HasFocus() return self.focused or false end
    function methods:EnableKeyboard() end
    function methods:SetPropagateKeyboardInput() end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:RegisterUnitEvent(event) self.events[event] = true end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function methods:Fire(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function methods:Show() self.shown = true; self:Fire("OnShow") end
    function methods:Hide() self.shown = false; self:Fire("OnHide") end
    local function frame(name, parent, shown, alpha, kind)
        local f = setmetatable({ parent = parent, shown = shown ~= false,
            alpha = alpha or 1, kind = kind or "Frame", children = {}, regions = {},
            scripts = {}, hooks = {}, events = {} }, { __index = methods })
        if parent then table.insert(parent.children, f) end
        env[name] = f
        return f
    end
    frame("UIParent")
    frame("WorldFrame")
    frame("MinimapParent", env.UIParent, true, 0.9)
    frame("MinimapSibling", env.MinimapParent)
    frame("MinimapCluster", env.MinimapParent, true, 0.85)
    frame("Minimap", env.MinimapCluster)
    frame("MinimapMenu", env.MinimapCluster, true, 0.75)
    frame("TrackingPin", env.Minimap)
    frame("ChatFrame1", env.UIParent, true, 0.85)
    frame("ChatFrame1EditBox", env.UIParent, false, 0.9)
    frame("ChatFrame1Tab", env.UIParent)
    frame("ChatFrame1ButtonFrame", env.UIParent)
    frame("GeneralDockManager", env.UIParent)
    frame("Hud", env.UIParent, true, 0.65)
    frame("ZoneTextFrame", env.UIParent, false, 0)
    frame("SubZoneTextFrame", env.UIParent, false, 0)
    frame("TrackerParent", env.UIParent, true, 0.9)
    frame("TrackerSibling", env.TrackerParent)
    frame("QuestWatchFrame", env.TrackerParent, false, 0.8)
    frame("BuffFrame", env.UIParent, true, 0.8)
    frame("DebuffFrame", env.UIParent, true, 0.9)
    frame("MainMenuBar", env.UIParent)
    frame("ActionButton1", env.MainMenuBar, true, 0.8)
    frame("CharacterMicroButton", env.MainMenuBar)
    frame("PlayerFrame", env.UIParent, true, 0.7)
    frame("TargetFrame", env.UIParent, true, 0.9)
    frame("MainMenuBarBackpackButton", env.MainMenuBar)
    frame("CastParent", env.UIParent, true, 0.9)
    frame("CastingBarFrame", env.CastParent, false, 0.75)
    frame("PlayerCastingBarFrame", env.CastParent, false, 0.6)
    frame("CastSibling", env.CastParent)
    frame("PopupParent", env.UIParent, true, 0.9)
    frame("PopupSibling", env.PopupParent)
    for index = 1, 4 do
        local popup = frame("StaticPopup" .. index, env.PopupParent, false, 0.85)
        frame("StaticPopup" .. index .. "Button1", popup)
    end
    for _, name in ipairs({ "LootFrame", "ContainerFrame1", "TradeSkillFrame",
        "CraftFrame", "QuestFrame", "GossipFrame", "SpellBookFrame", "WorldMapFrame",
        "QuestLogFrame", "CharacterFrame", "MerchantFrame", "MailFrame", "OpenMailFrame" }) do frame(name, env.UIParent, false) end
    frame("StackSplitFrame", env.UIParent, false, 0.85)
    frame("GameTooltip", env.UIParent, false, 1, "GameTooltip")
    env.UIPanelWindows = { TradeSkillFrame = {}, CraftFrame = {}, QuestFrame = {},
        GossipFrame = {}, SpellBookFrame = {}, WorldMapFrame = {}, QuestLogFrame = {},
        CharacterFrame = {}, MerchantFrame = {}, MailFrame = {} }
    env.SlashCmdList = {}
    env.CreateFrame = function(_, name) return frame(name, env.UIParent) end
    env.GetTime = function() return s.time end
    env.InCombatLockdown = function() return s.combat end
    env.UnitAffectingCombat = env.InCombatLockdown
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = env.UnitHealth
    env.UnitPower = env.UnitHealth
    env.UnitPowerMax = env.UnitHealth
    env.UnitPowerType = function() return 0 end
    env.UnitDebuff = function() return s.debuff end
    env.UnitCastingInfo = function() return s.cast end
    env.UnitChannelInfo = function() return s.channel end
    env.UnitExists = function(unit) return unit == "target" and s.target or false end
    env.UnitIsPlayer = function(unit) return unit == "target" and s.playerTarget or false end
    env.UnitIsDeadOrGhost = function() return s.deadTarget end
    env.UnitCanAttack = function() return not s.friendly end
    env.IsShiftKeyDown = function() return false end
    env.IsControlKeyDown = env.IsShiftKeyDown
    env.IsAltKeyDown = env.IsShiftKeyDown
    env.GetBindingAction = function() return s.binding end
    env.GetMouseFoci = function() return { env.WorldFrame } end
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
    env.print = function() end
    env.hooksecurefunc = function(object, method, callback)
        local original = object[method]
        object[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
    end
    setfenv(assert(loadstring(source, "@Main.lua")), env)("SmartHideUI")
    local controller = env.SmartHideUIController
    function s.event(event)
        if controller.events[event] then controller:Fire("OnEvent", event, "player") end
    end
    function s.tick(seconds)
        s.time = s.time + (seconds or 0.05)
        controller:Fire("OnUpdate", seconds or 0.05)
    end
    function s.key(edge, binding)
        s.binding = binding
        controller:Fire(edge, "TESTKEY")
    end
    function s.hidden()
        assert(env.Hud.alpha == 0, "unrelated HUD was revealed")
        assert(env.MinimapParent.alpha == 0.9 and env.MinimapCluster.alpha == 0.85
            and env.Minimap.alpha == 1 and env.MinimapMenu.alpha == 0.75,
            "minimap or its surrounding controls were faded")
        assert(env.MinimapSibling.alpha == 0, "unrelated minimap ancestor sibling revealed")
        assert(env.CharacterMicroButton.alpha == 0 or env.MainMenuBar.alpha == 0,
            "micro menu was revealed")
    end
    function s.visible()
        assert(env.Hud.alpha == 0.65, "original HUD alpha was not restored")
    end
    function s.start(spell)
        s.cast = spell
        s.event("UNIT_SPELLCAST_START")
        env.CastingBarFrame:Show()
        s.tick()
    end
    function s.stop()
        s.cast = nil
        s.event("UNIT_SPELLCAST_SUCCEEDED")
        s.event("UNIT_SPELLCAST_STOP")
        s.tick()
    end
    function s.loot()
        s.event("LOOT_OPENED")
        env.LootFrame:Show()
        s.tick()
    end
    function s.close(eventFirst)
        if eventFirst then s.event("LOOT_CLOSED") end
        env.LootFrame:Hide()
        s.event("LOOT_CLOSED")
        s.tick()
    end
    if not visible then s.tick(4); s.hidden() end
    return s, env
end

local failures, count = {}, 0
local function test(name, callback)
    count = count + 1
    local ok, err = pcall(callback)
    if not ok then table.insert(failures, name .. ": " .. tostring(err)) end
end

for _, binding in ipairs({ "ACTIONBUTTON1", "MULTIACTIONBAR1BUTTON1" }) do
    test("bandage channel via " .. binding, function()
        local s, e = setup()
        s.key("OnKeyDown", binding); s.hidden()
        s.channel = "First Aid"; s.event("UNIT_SPELLCAST_CHANNEL_START")
        s.hidden()
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        e.BuffFrame:SetAlpha(0.8)
        s.key("OnKeyUp", binding); s.tick(); s.hidden()
        assert(e.BuffFrame.alpha == 0.8)
        s.channel = nil; s.event("UNIT_SPELLCAST_CHANNEL_STOP")
        s.tick(); s.hidden()
        assert(e.BuffFrame.alpha == 0 and e.DebuffFrame.alpha == 0)
        e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
    end)
end

test("bandaging preserves visible UI and overrides", function()
    local s, e = setup(true)
    s.key("OnKeyDown", "ACTIONBUTTON1")
    s.channel = "First Aid"; s.event("UNIT_SPELLCAST_CHANNEL_START")
    s.key("OnKeyUp", "ACTIONBUTTON1"); s.tick(); s.visible()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        s.tick(4); s.visible()
    end
end)

for _, panel in ipairs({ "LootFrame", "ContainerFrame1", "QuestFrame",
    "TradeSkillFrame", "SpellBookFrame", "WorldMapFrame", "QuestLogFrame" }) do
    test("debuff keeps auras visible in " .. panel, function()
        local s, e = setup()
        s.debuff = "Recently Bandaged"; s.event("UNIT_AURA")
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
        if panel == "LootFrame" then s.loot() else e[panel]:Show(); s.tick() end
        s.hidden()
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
        s.debuff = nil; s.event("UNIT_AURA")
        assert(e.BuffFrame.alpha == 0 and e.DebuffFrame.alpha == 0)
        s.debuff = "Poison"; s.event("UNIT_AURA")
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
        s.key("OnKeyDown", "UNRELATED_BINDING"); s.tick(); s.hidden()
        if panel == "LootFrame" then s.close() else e[panel]:Hide(); s.tick() end
        s.hidden()
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
        e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
        assert(e.BuffFrame.alpha == 0.8 and e.DebuffFrame.alpha == 0.9)
    end)
end

test("bandage auras compose with bags and combat", function()
    local s, e = setup()
    e.ContainerFrame1:Show(); s.tick()
    s.channel = "First Aid"; s.event("UNIT_SPELLCAST_CHANNEL_START"); s.tick()
    s.hidden(); assert(e.BuffFrame.alpha == 0.8 and e.ContainerFrame1.alpha == 1)
    e.ContainerFrame1:Hide(); s.tick(); s.hidden()
    assert(e.BuffFrame.alpha == 0.8)
    s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
    assert(e.ActionButton1.alpha == 0.8 and e.BuffFrame.alpha == 0.8)
    s.channel = nil; s.event("UNIT_SPELLCAST_CHANNEL_STOP")
    s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.tick(); s.hidden()
end)

for _, spell in ipairs({ "Mining", "Herb Gathering", "Skinning" }) do
    test(spell .. ": cast and loot remain selective", function()
        local s, e = setup()
        s.key("OnKeyDown", "INTERACTTARGET")
        if spell == "Skinning" then
            s.target, s.deadTarget = true, true
            s.event("PLAYER_TARGET_CHANGED")
        end
        s.start(spell); s.hidden()
        assert(e.CastingBarFrame.alpha == 0.75 and e.CastParent.alpha == 0.9)
        assert(e.PlayerCastingBarFrame.alpha == 0.6 and e.CastSibling.alpha == 0)
        s.key("OnKeyUp", "INTERACTTARGET"); s.hidden()
        s.stop(); s.hidden()
        s.loot(); s.hidden()
        assert(e.LootFrame.alpha == 1, "loot window is faded")
        s.close(); s.hidden()
    end)
    for _, eventFirst in ipairs({ false, true }) do
        test(spell .. ": delayed inventory update, close event first=" .. tostring(eventFirst), function()
            local s = setup()
            s.start(spell); s.stop(); s.loot(); s.close(eventFirst)
            s.event("BAG_UPDATE_DELAYED"); s.hidden()
            s.event("BAG_UPDATE_DELAYED"); s.tick(); s.hidden()
        end)
    end
    test(spell .. ": Escape cancellation without target", function()
        local s = setup()
        s.start(spell)
        s.key("OnKeyDown", "TOGGLEGAMEMENU")
        s.cast = nil
        s.event("UNIT_SPELLCAST_STOP")
        s.key("OnKeyUp", "TOGGLEGAMEMENU")
        s.tick(); s.hidden()
    end)
end

test("inventory update in the cast-to-loot gap", function()
    local s = setup()
    s.start("Mining"); s.stop()
    s.event("BAG_UPDATE_DELAYED"); s.hidden()
    s.loot(); s.hidden()
end)
test("loot can arrive before cast stop", function()
    local s = setup()
    s.start("Mining"); s.loot(); s.stop(); s.hidden()
    s.close(); s.event("BAG_UPDATE_DELAYED"); s.hidden()
end)
test("movement cancellation and failed attempts", function()
    local s = setup()
    s.start("Herb Gathering")
    s.key("OnKeyDown", "MOVEFORWARD")
    s.cast = nil
    s.event("UNIT_SPELLCAST_STOP")
    s.key("OnKeyUp", "MOVEFORWARD"); s.tick(); s.hidden()
    s.start("Herb Gathering"); s.cast = nil
    s.event("UNIT_SPELLCAST_FAILED"); s.event("UNIT_SPELLCAST_STOP")
    s.tick(); s.hidden()
end)
test("open bags retain their controls after looting", function()
    local s, e = setup()
    e.ContainerFrame1:Show(); s.event("BAG_UPDATE_DELAYED")
    s.start("Mining"); s.stop(); s.loot(); s.close()
    s.event("BAG_UPDATE_DELAYED"); s.hidden()
    assert(e.ContainerFrame1.alpha == 1 and e.ActionButton1.alpha == 0.8)
    e.ContainerFrame1:Hide(); s.event("BAG_UPDATE_DELAYED"); s.tick(); s.hidden()
    assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
end)
test("combat overrides gathering without full HUD", function()
    local s, e = setup()
    s.start("Skinning"); s.combat = true; s.event("PLAYER_REGEN_DISABLED")
    s.hidden(); assert(e.ActionButton1.alpha == 0.8)
    s.cast = nil; s.combat = false; s.event("PLAYER_REGEN_ENABLED")
    s.tick(); s.hidden()
end)
test("profession panel survives gathering and inventory updates", function()
    local s, e = setup()
    e.TradeSkillFrame:Show()
    s.start("Mining"); s.stop(); s.loot(); s.close()
    s.event("BAG_UPDATE_DELAYED"); s.hidden()
    assert(e.TradeSkillFrame.alpha == 1)
end)
test("initially visible UI stays visible throughout gathering", function()
    local s = setup(true)
    s.start("Mining"); s.visible()
    s.stop(); s.loot(); s.close(); s.event("BAG_UPDATE_DELAYED"); s.visible()
end)
for _, command in ipairs({ "off", "show" }) do
    test("/shu " .. command .. " restores and preserves alpha", function()
        local s, e = setup()
        s.start("Mining"); e.SlashCmdList.SMARTHIDEUI(command); s.visible()
        assert(e.CastingBarFrame.alpha == 0.75 and e.CastSibling.alpha == 1)
        s.stop(); s.loot(); s.close(); s.event("BAG_UPDATE_DELAYED"); s.visible()
    end)
end
test("ordinary keyboard activity still restores idle UI", function()
    local s = setup()
    s.key("OnKeyDown", "UNRELATED_BINDING"); s.visible()
end)

for _, binding in ipairs({ "TARGETNEARESTENEMY", "TARGETPREVIOUSENEMY", "ASSISTTARGET" }) do
    test(binding .. " leaves empty targeting hidden", function()
        local s = setup()
        s.key("OnKeyDown", binding); s.hidden()
        s.key("OnKeyUp", binding); s.tick(); s.hidden()
    end)
end

test("enemy selection, continued activity, and target loss", function()
    local s, e = setup()
    s.key("OnKeyDown", "TARGETNEARESTENEMY"); s.hidden()
    s.target = true; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.PlayerFrame.alpha == 0.7 and e.TargetFrame.alpha == 0.9)
    assert(e.MainMenuBar.alpha == 1 and e.ActionButton1.alpha == 0.8)
    s.key("OnKeyUp", "TARGETNEARESTENEMY"); s.hidden()
    s.key("OnKeyDown", "ACTIONBUTTON1"); s.tick(4); s.hidden()
    s.target = false; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.PlayerFrame.alpha == 0 and e.TargetFrame.alpha == 0)
    assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
end)

test("friendly player portrait persists through activity and overlapping modes", function()
    local s, e = setup()
    s.target, s.friendly, s.playerTarget = true, true, true
    s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9 and e.PlayerFrame.alpha == 0)
    assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
    s.key("OnKeyDown", "UNRELATED_BINDING"); s.tick(4); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
    e.ContainerFrame1:Show(); s.tick(); s.hidden()
    assert(e.TargetFrame.alpha == 0.9 and e.ActionButton1.alpha == 0.8)
    e.ContainerFrame1:Hide(); s.tick(); s.hidden()
    e.GossipFrame:Show(); s.tick(); s.hidden()
    assert(e.TargetFrame.alpha == 0.9 and e.GossipFrame.alpha == 1)
    e.GossipFrame:Hide(); s.tick(); s.hidden()
    s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
    s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
    s.target = false; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.TargetFrame.alpha == 0)
end)

test("friendly player targeting respects visible UI and overrides", function()
    local s, e = setup(true)
    s.target, s.friendly, s.playerTarget = true, true, true
    s.event("PLAYER_TARGET_CHANGED"); s.visible()
    s.tick(4); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        s.event("PLAYER_TARGET_CHANGED"); s.tick(4); s.visible()
        assert(e.TargetFrame.alpha == 0.9)
    end
end)

test("mouse selection composes with bags and combat", function()
    local s, e = setup()
    s.target = true; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9 and e.ActionButton1.alpha == 0.8)
    e.ContainerFrame1:Show(); s.tick(); s.hidden()
    assert(e.ContainerFrame1.alpha == 1 and e.PlayerFrame.alpha == 0.7)
    e.ContainerFrame1:Hide(); s.tick(); s.hidden()
    s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
    s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
    s.friendly = true; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.TargetFrame.alpha == 0)
end)

test("target death returns to idle", function()
    local s, e = setup()
    s.target = true; s.event("PLAYER_TARGET_CHANGED")
    s.deadTarget = true; s.tick(); s.hidden()
    assert(e.TargetFrame.alpha == 0)
end)

test("visible targeting and explicit overrides stay visible", function()
    local s, e = setup(true)
    s.target = true; s.event("PLAYER_TARGET_CHANGED"); s.visible()
    s.tick(4); s.hidden()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command); s.visible()
        s.event("PLAYER_TARGET_CHANGED"); s.tick(4); s.visible()
    end
end)

for _, name in ipairs({ "Minimap", "MinimapCluster", "TrackingPin" }) do
    test(name .. " hover preserves hidden HUD and tooltip", function()
        local s, e = setup()
        e.GetMouseFoci = function() return { e[name] } end
        e.GameTooltip:Show()
        s.tick(); s.hidden()
        s.tick(4); s.hidden()
        assert(e.Minimap.alpha == 1 and e.MinimapCluster.alpha == 0.85)
        assert(e.GameTooltip:IsShown() and e.GameTooltip.alpha == 1)
        e.GameTooltip:Hide()
        e.GetMouseFoci = function() return { e.WorldFrame } end
        s.tick(); s.hidden()
    end)
end

test("legacy minimap focus and unrelated simultaneous focus", function()
    local s, e = setup()
    e.GetMouseFoci = false
    e.GetMouseFocus = function() return e.TrackingPin end
    s.tick(); s.hidden()
    e.GetMouseFoci = function() return { e.Minimap, e.Hud } end
    s.tick(); s.visible()
end)

test("minimap hover preserves visible state and manual overrides", function()
    local s, e = setup(true)
    e.GetMouseFoci = function() return { e.Minimap } end
    s.tick(); s.visible()
    s.tick(4); s.hidden()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        s.tick(4); s.visible()
    end
end)

test("minimap hover composes with bags and combat", function()
    local s, e = setup()
    e.GetMouseFoci = function() return { e.TrackingPin } end
    e.ContainerFrame1:Show(); s.tick(); s.hidden()
    assert(e.ContainerFrame1.alpha == 1 and e.ActionButton1.alpha == 0.8)
    e.ContainerFrame1:Hide(); s.tick(); s.hidden()
    s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.tick(); s.hidden()
    assert(e.ActionButton1.alpha == 0.8)
    s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.tick(); s.hidden()
    assert(e.GameTooltip.alpha == 1)
end)

for index = 1, 4 do
    for _, visible in ipairs({ false, true }) do
        test("combat party invite slot " .. index .. " visible=" .. tostring(visible), function()
            local s, e = setup(visible)
            s.combat = true; s.event("PLAYER_REGEN_DISABLED")
            local popup = e["StaticPopup" .. index]
            popup.which = "PARTY_INVITE"
            popup:Show()
            local function checkInvite()
                s.hidden()
                assert(popup.alpha == 0.85 and e.PopupParent.alpha == 0.9,
                    "party invite or its ancestor is faded")
                assert(e["StaticPopup" .. index .. "Button1"].alpha == 1,
                    "accept button is faded")
                assert(e.PopupSibling.alpha == 0, "unrelated popup sibling revealed")
                assert(e.ActionButton1.alpha == 0.8, "combat controls faded")
            end
            checkInvite() -- Must work immediately, before the next update tick.
            s.key("OnKeyDown", "ACTIONBUTTON1"); s.tick(4); checkInvite()
            s.loot(); checkInvite()
            s.close(); checkInvite()
            popup:Hide(); s.hidden()
            popup.which = "UNRELATED_DIALOG"; popup:Show(); s.tick()
            assert(popup.alpha == 0 or e.PopupParent.alpha == 0,
                "reused popup slot bypasses combat filtering")
            popup:Hide()
            s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.tick(); s.hidden()
            e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
            assert(popup.alpha == 0.85 and e.PopupParent.alpha == 0.9)
        end)
    end
end

test("existing invite survives combat entry and manual overrides", function()
    local s, e = setup(true)
    e.StaticPopup1.which = "PARTY_INVITE"; e.StaticPopup1:Show(); s.visible()
    s.combat = true; s.event("PLAYER_REGEN_DISABLED")
    assert(e.StaticPopup1.alpha == 0.85 and e.PopupParent.alpha == 0.9)
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        e.StaticPopup1:Hide(); e.StaticPopup1:Show(); s.tick(4); s.visible()
        assert(e.StaticPopup1.alpha == 0.85 and e.PopupSibling.alpha == 1)
    end
end)

for _, visible in ipairs({ false, true }) do
    test("minimap controls survive combat, death, loot, and panels: visible=" .. tostring(visible), function()
        local s, e = setup(visible)
        s.target = true; s.event("PLAYER_TARGET_CHANGED")
        s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
        s.key("OnKeyDown", "ACTIONBUTTON1"); s.tick(); s.hidden()
        s.deadTarget = true; s.combat = false; s.event("PLAYER_REGEN_ENABLED")
        s.tick(); s.hidden()
        s.loot(); s.hidden(); s.close(); s.hidden()
        s.target = false; s.event("PLAYER_TARGET_CHANGED"); s.hidden()
        e.QuestLogFrame:Show(); s.tick(); s.hidden()
        e.QuestLogFrame:Hide(); s.tick()
        assert(e.MinimapMenu.alpha == 0.75 and e.MinimapCluster.alpha == 0.85)
        e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
        assert(e.MinimapParent.alpha == 0.9 and e.MinimapSibling.alpha == 1)
        assert(e.MinimapMenu.alpha == 0.75 and e.MinimapCluster.alpha == 0.85)
    end)
end


for _, binding in ipairs({ "OPENCHAT", "OPENCHATSLASH", "CHATREPLY", "CHATREPLY2" }) do
    test(binding .. " reveals only chat and closes without revealing HUD", function()
        local s, e = setup()
        s.key("OnKeyDown", binding); s.hidden()
        e.ChatFrame1EditBox:Show()
        e.ChatFrame1EditBox.focused = true
        e.ChatFrame1EditBox:Fire("OnEditFocusGained"); s.hidden()
        assert(e.ChatFrame1.alpha == 0.85 and e.ChatFrame1EditBox.alpha == 0.9)
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        s.key("OnKeyUp", binding); s.tick(20); s.hidden()
        assert(e.ChatFrame1.alpha == 0.85)
        s.key("OnKeyDown", "UNRELATED_BINDING"); s.hidden()
        s.key("OnKeyUp", "UNRELATED_BINDING")
        s.key("OnKeyDown", "OPENCHAT")
        e.ChatFrame1EditBox.focused = false
        e.ChatFrame1EditBox:Fire("OnEditFocusLost")
        e.ChatFrame1EditBox:Hide()
        s.key("OnKeyUp", "OPENCHAT"); s.hidden()
        s.tick(4); s.hidden()
        assert(e.ChatFrame1.alpha == 0)
    end)
end

for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_SAY" }) do
    test(event .. " reveals chat temporarily and extends on new messages", function()
        local s, e = setup()
        s.event(event); s.hidden()
        assert(e.ChatFrame1.alpha == 0.85)
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        s.tick(9); s.hidden(); assert(e.ChatFrame1.alpha == 0.85)
        s.event(event); s.tick(9); s.hidden(); assert(e.ChatFrame1.alpha == 0.85)
        s.tick(2); s.hidden(); assert(e.ChatFrame1.alpha == 0)
    end)
end

test("chat composes with bags, quest conversation, target, loot and combat", function()
    local s, e = setup()
    s.event("CHAT_MSG_WHISPER")
    e.ContainerFrame1:Show(); s.tick(); s.hidden()
    assert(e.ChatFrame1.alpha == 0.85 and e.ContainerFrame1.alpha == 1)
    e.ContainerFrame1:Hide(); s.tick(); s.hidden()
    e.GossipFrame:Show(); s.tick(); s.hidden()
    assert(e.ChatFrame1.alpha == 0.85 and e.GossipFrame.alpha == 1)
    e.GossipFrame:Hide(); s.tick(); s.hidden()
    s.target, s.friendly, s.playerTarget = true, true, true
    s.event("PLAYER_TARGET_CHANGED"); s.hidden()
    assert(e.ChatFrame1.alpha == 0.85 and e.TargetFrame.alpha == 0.9)
    s.loot(); s.hidden()
    assert(e.ChatFrame1.alpha == 0.85 and e.LootFrame.alpha == 1)
    s.close(true); s.hidden()
    s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
    assert(e.ChatFrame1.alpha == 0.85 and e.ActionButton1.alpha == 0.8)
    s.tick(11); s.hidden()
    assert(e.ChatFrame1.alpha == 0 and e.ActionButton1.alpha == 0.8)
    s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.hidden()
    assert(e.TargetFrame.alpha == 0.9)
end)

test("chat respects visible entry and explicit overrides", function()
    local s, e = setup(true)
    s.key("OnKeyDown", "OPENCHAT")
    e.ChatFrame1EditBox.focused = true
    e.ChatFrame1EditBox:Fire("OnEditFocusGained")
    s.tick(4); s.visible()
    e.ChatFrame1EditBox.focused = false
    s.tick(4); s.hidden()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        s.event("CHAT_MSG_SAY"); s.tick(11); s.visible()
        assert(e.ChatFrame1.alpha == 0.85)
    end
end)

test("objective progress reveals only tracker, refreshes duration and expires", function()
    local s, e = setup()
    s.event("QUEST_WATCH_UPDATE")
    assert(e.QuestWatchFrame.alpha == 0.8 and not e.QuestWatchFrame.shown)
    e.QuestWatchFrame:Show() -- Blizzard can show it after the progress event.
    assert(e.TrackerParent.alpha == 0.9 and e.TrackerSibling.alpha == 0)
    s.hidden()
    s.tick(2)
    s.event("QUEST_WATCH_UPDATE") -- Includes the final objective update.
    s.key("OnKeyDown", "UNBOUND"); s.hidden()
    s.tick(2)
    assert(e.QuestWatchFrame.alpha == 0.8)
    s.tick(1.1); s.hidden()
    assert(e.QuestWatchFrame.alpha == 0 or e.TrackerParent.alpha == 0)
    e.SlashCmdList.SMARTHIDEUI("show")
    assert(e.QuestWatchFrame.alpha == 0.8 and e.TrackerParent.alpha == 0.9)
end)

for _, mode in ipairs({ "combat", "loot", "bags", "quest" }) do
    test("objective tracker composes with " .. mode, function()
        local s, e = setup()
        if mode == "combat" then s.combat = true; s.event("PLAYER_REGEN_DISABLED")
        elseif mode == "loot" then s.loot()
        elseif mode == "bags" then e.ContainerFrame1:Show(); s.tick()
        else e.QuestFrame:Show(); s.event("QUEST_DETAIL") end
        s.event("QUEST_WATCH_UPDATE"); s.tick(); s.hidden()
        assert(e.QuestWatchFrame.alpha == 0.8 and e.TrackerParent.alpha == 0.9)
        s.tick(3.1); s.hidden()
        assert(e.QuestWatchFrame.alpha == 0 or e.TrackerParent.alpha == 0)
        if mode == "combat" then assert(e.ActionButton1.alpha == 0.8)
        elseif mode == "loot" then assert(e.LootFrame.alpha == 1)
        elseif mode == "bags" then assert(e.ContainerFrame1.alpha == 1)
        else assert(e.QuestFrame.alpha == 1) end
    end)
end

test("closing loot preserves the remaining tracker reveal", function()
    local s, e = setup()
    s.loot(); s.event("QUEST_WATCH_UPDATE"); s.close()
    s.hidden(); assert(e.QuestWatchFrame.alpha == 0.8)
    s.tick(3.1); s.hidden()
    assert(e.QuestWatchFrame.alpha == 0 or e.TrackerParent.alpha == 0)
end)

test("quest progress preserves visible entry and manual overrides", function()
    local s, e = setup(true)
    s.event("QUEST_WATCH_UPDATE"); s.tick(); s.visible()
    s.tick(4); s.hidden()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI("on"); s.tick(4)
        s.event("QUEST_WATCH_UPDATE")
        e.SlashCmdList.SMARTHIDEUI(command)
        s.event("QUEST_WATCH_UPDATE"); s.tick(4); s.visible()
        assert(e.QuestWatchFrame.alpha == 0.8 and e.TrackerParent.alpha == 0.9)
    end
end)

for _, eventFirst in ipairs({ false, true }) do
    test("vendor entry and close ordering eventFirst=" .. tostring(eventFirst), function()
        local s, e = setup()
        s.key("OnKeyDown", "INTERACTTARGET"); s.hidden()
        if eventFirst then s.event("MERCHANT_SHOW"); s.hidden(); s.tick(); s.hidden() end
        e.MerchantFrame:Show(); s.hidden()
        s.event("MERCHANT_SHOW"); s.hidden()
        assert(e.MerchantFrame.alpha == 1)
        s.key("OnKeyUp", "INTERACTTARGET"); s.tick(); s.hidden()
        s.key("OnKeyDown", "UNBOUND"); s.hidden()
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        e.ContainerFrame1:Show(); s.tick(); s.hidden()
        assert(e.ActionButton1.alpha == 0.8 and e.ContainerFrame1.alpha == 1)
        e.ContainerFrame1:Hide(); s.tick(); s.hidden()
        s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
        assert(e.MerchantFrame.alpha == 1 and e.ActionButton1.alpha == 0.8)
        s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.hidden()
        if eventFirst then s.event("MERCHANT_CLOSED"); s.hidden() end
        e.MerchantFrame:Hide(); s.hidden()
        s.event("MERCHANT_CLOSED"); s.tick(); s.hidden()
        e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
        assert(e.MerchantFrame.alpha == 1)
    end)
end

test("vendor without bags preserves visible entry and overrides", function()
    local s, e = setup(true)
    s.event("MERCHANT_SHOW"); e.MerchantFrame:Show(); s.tick(4); s.visible()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        e.MerchantFrame:Hide(); s.event("MERCHANT_CLOSED")
        s.event("MERCHANT_SHOW"); e.MerchantFrame:Show(); s.tick(4); s.visible()
    end
end)

for _, visible in ipairs({ false, true }) do
    test("vendor quantity picker with visible entry " .. tostring(visible), function()
        local s, e = setup(visible)
        e.MerchantFrame:Show(); e.ContainerFrame1:Show(); s.tick()
        e.StackSplitFrame:Show()
        assert(e.StackSplitFrame.alpha == 0.85, "quantity picker was faded")
        assert(e.MerchantFrame.alpha == 1)
        s.key("OnKeyDown", "UNBOUND"); s.tick(); s.hidden()
        assert(e.StackSplitFrame.alpha == 0.85)
        s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.tick()
        assert(e.StackSplitFrame.alpha == 0.85); s.hidden()
        e.StackSplitFrame:Hide(); s.tick(); s.hidden()
        s.combat = false; e.MerchantFrame:Hide(); e.ContainerFrame1:Hide()
        s.tick(); s.tick(4); s.hidden()
        assert(e.StackSplitFrame.alpha == 0)
        e.SlashCmdList.SMARTHIDEUI("off")
        assert(e.StackSplitFrame.alpha == 0.85); s.visible()
    end)
end

for _, panel in ipairs({ "ContainerFrame1", "QuestLogFrame", "SpellBookFrame",
    "WorldMapFrame", "TradeSkillFrame", "QuestFrame", "LootFrame", "CharacterFrame" }) do
    for _, visible in ipairs({ false, true }) do
        test("area text animation with " .. panel .. " visible=" .. tostring(visible), function()
            local s, e = setup(visible)
            local zone, subzone = e.ZoneTextFrame, e.SubZoneTextFrame
            -- Animate before entry to catch stale alpha restoration on transitions.
            zone:SetAlpha(0.25); subzone:SetAlpha(0.35)
            -- Generic panels compose with bag mode; combat alone filters them.
            if panel == "CharacterFrame" then e.ContainerFrame1:Show() end
            if panel == "LootFrame" then s.loot() else e[panel]:Show(); s.tick() end
            assert(zone.alpha == 0.25 and subzone.alpha == 0.35)
            zone:Show(); subzone:Show()
            local function animate()
                for _, alpha in ipairs({ 0.1, 0.6, 1, 0.4, 0 }) do
                    zone:SetAlpha(alpha); subzone:SetAlpha(alpha / 2)
                    s.tick()
                    assert(zone.alpha == alpha and subzone.alpha == alpha / 2,
                        "addon overwrote Blizzard's area-text animation")
                end
            end
            animate()
            s.combat = true; s.event("PLAYER_REGEN_DISABLED"); animate(); s.hidden()
            assert(e[panel].alpha == 1, "open window was faded")
            s.combat = false; s.event("PLAYER_REGEN_ENABLED")
            zone:SetAlpha(0.45); subzone:SetAlpha(0.2)
            if panel == "LootFrame" then s.close() else e[panel]:Hide(); s.tick() end
            if panel == "CharacterFrame" then e.ContainerFrame1:Hide(); s.tick() end
            assert(zone.alpha == 0.45 and subzone.alpha == 0.2)
            s.tick(4); animate(); s.hidden()
            for _, command in ipairs({ "show", "off" }) do
                zone:SetAlpha(0.3); subzone:SetAlpha(0.7)
                e.SlashCmdList.SMARTHIDEUI(command)
                assert(zone.alpha == 0.3 and subzone.alpha == 0.7)
                animate(); s.visible()
            end
        end)
    end
end

for _, eventFirst in ipairs({ false, true }) do
    test("mail entry, bags, letter and close ordering " .. tostring(eventFirst), function()
        local s, e = setup()
        s.key("OnKeyDown", "INTERACTTARGET"); s.hidden()
        if eventFirst then s.event("MAIL_SHOW"); s.tick(); s.hidden() end
        e.MailFrame:Show(); s.hidden()
        s.event("MAIL_SHOW"); s.hidden()
        assert(e.MailFrame.alpha == 1 and e.OpenMailFrame.alpha == 1)
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        e.ContainerFrame1:Show(); s.event("BAG_UPDATE_DELAYED"); s.hidden()
        e.OpenMailFrame:Show(); s.hidden()
        assert(e.OpenMailFrame.alpha == 1 and e.ContainerFrame1.alpha == 1)
        assert(e.ActionButton1.alpha == 0.8)
        s.key("OnKeyUp", "INTERACTTARGET")
        s.key("OnKeyDown", "UNBOUND"); s.tick(4); s.hidden()
        assert(e.OpenMailFrame.alpha == 1 and e.MailFrame.alpha == 1)
        e.ContainerFrame1:Hide(); s.tick(); s.hidden()
        assert(e.OpenMailFrame.alpha == 1)
        assert(e.MainMenuBar.alpha == 0 or e.ActionButton1.alpha == 0)
        e.ContainerFrame1:Show(); s.tick()
        s.combat = true; s.event("PLAYER_REGEN_DISABLED"); s.hidden()
        assert(e.OpenMailFrame.alpha == 1 and e.MailFrame.alpha == 1)
        s.combat = false; s.event("PLAYER_REGEN_ENABLED"); s.hidden()
        s.key("OnKeyDown", "TOGGLEGAMEMENU")
        e.OpenMailFrame:Hide()
        if eventFirst then s.event("MAIL_CLOSED"); s.hidden() end
        e.MailFrame:Hide(); s.event("MAIL_CLOSED"); s.hidden()
        assert(e.ContainerFrame1.alpha == 1 and e.ActionButton1.alpha == 0.8)
        s.key("OnKeyUp", "TOGGLEGAMEMENU"); s.hidden()
        e.ContainerFrame1:Hide(); s.tick(); s.hidden()
        e.SlashCmdList.SMARTHIDEUI("off"); s.visible()
        assert(e.MailFrame.alpha == 1 and e.OpenMailFrame.alpha == 1)
    end)
end

test("mail close without bags remains minimal", function()
    local s, e = setup()
    s.event("MAIL_SHOW"); e.MailFrame:Show(); e.OpenMailFrame:Show()
    e.OpenMailFrame:Hide(); e.MailFrame:Hide(); s.event("MAIL_CLOSED")
    s.tick(); s.hidden()
end)

test("mail preserves visible entry with automatic bags and overrides", function()
    local s, e = setup(true)
    s.event("MAIL_SHOW"); e.MailFrame:Show(); e.ContainerFrame1:Show()
    s.event("BAG_UPDATE_DELAYED"); e.OpenMailFrame:Show(); s.tick(4); s.visible()
    for _, command in ipairs({ "show", "off" }) do
        e.SlashCmdList.SMARTHIDEUI(command)
        e.MailFrame:Hide(); s.event("MAIL_CLOSED")
        s.event("MAIL_SHOW"); e.MailFrame:Show(); s.tick(4); s.visible()
        assert(e.OpenMailFrame.alpha == 1)
    end
end)

for _, failure in ipairs(failures) do print("FAIL " .. failure) end
print(string.format("%d/%d regression checks passed", count - #failures, count))
assert(#failures == 0, "regression checks failed")
