local _, addon = ...

local interface = select(4, GetBuildInfo())
-- Forever currently identifies as a mainline project; its interface range is
-- distinct from Anniversary TBC and supplies the needed frame policy split.
local forever = type(interface) == "number" and interface >= 16000 and interface < 20000

addon.compat = {
    forever = forever,
    spellbookFrames = forever and { "PlayerSpellsFrame", "SpellBookFrame" }
        or { "SpellBookFrame" },
    tradeSkillFrames = forever and { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }
        or { "TradeSkillFrame", "CraftFrame" },
    questLogFrames = { "QuestLogFrame" },
    bagButtons = forever and { "BagsBar", "MainMenuBarBackpackButton" }
        or { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
            "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton" },
    actionFrames = forever and {
        "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
        "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar",
        "StanceBar", "PossessActionBar", "ExtraActionBarFrame", "MultiCastActionBarFrame",
    } or {
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
        "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBarFrame", "PetActionBar",
        "StanceBarFrame", "StanceBar", "PossessBarFrame", "PossessActionBar",
        "OverrideActionBar", "ExtraActionBarFrame", "MultiCastActionBarFrame",
        "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
    },
}

if not forever then
    for index = 1, 12 do
        addon.compat.actionFrames[#addon.compat.actionFrames + 1] = "ActionButton" .. index
    end
end
