local addonName = SmartHideUI

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        print("|cff33ff99" .. addonName .. "|r har laddats!")
    end
end)

SLASH_SMARTHIDEUI1 = "/shu"

SlashCmdList.SMARTHIDEUI = function(message)
    if message == "hej" then
        print("Hej från din addon!")
    else
        print("Skriv /shu hej")
    end
end