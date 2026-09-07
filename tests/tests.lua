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
    function methods:HasFocus() return false end
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
    frame("MinimapCluster", env.UIParent)
    frame("Minimap", env.MinimapCluster)
    frame("TrackingPin", env.Minimap)
    frame("Hud", env.UIParent, true, 0.65)
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
        "QuestLogFrame", "CharacterFrame" }) do frame(name, env.UIParent, false) end
    frame("GameTooltip", env.UIParent, false, 1, "GameTooltip")
    env.UIPanelWindows = { TradeSkillFrame = {}, CraftFrame = {}, QuestFrame = {},
        GossipFrame = {}, SpellBookFrame = {}, WorldMapFrame = {}, QuestLogFrame = {},
        CharacterFrame = {} }
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
    env.UnitDebuff = function() end
    env.UnitCastingInfo = function() return s.cast end
    env.UnitChannelInfo = function() return s.channel end
    env.UnitExists = function(unit) return unit == "target" and s.target or false end
    env.UnitIsPlayer = function() return false end
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
        assert(e.Minimap.alpha == 1 and e.MinimapCluster.alpha == 1)
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

for _, failure in ipairs(failures) do print("FAIL " .. failure) end
print(string.format("%d/%d regression checks passed", count - #failures, count))
assert(#failures == 0, "regression checks failed")
