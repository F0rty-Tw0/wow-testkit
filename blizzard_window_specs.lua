-- The Blizzard windows per flavor as data (rows B1-B3 of docs/client-sources.md; read by blizzard_windows.lua).
-- WINDOWS[flavor][window] = { addon, also? = { addon, ... }, lod = true, interaction? = "<Enum.PlayerInteractionType name>",
-- open? = event, show? = global, toggle? = global, frame? = global }: lod is "the TOC says ## LoadOnDemand: 1" (an absent
-- lod is true), interaction the PLAYER_INTERACTION_MANAGER_FRAME_SHOW type the window code registers for, open the
-- legacy event addons listen for, show the window's own show global (the classic merchant and mail windows have no
-- handler, B2), toggle its toggle global, also the addons loadFor loads after addon.
local M = {}

-- source: confirmed (rows B1, B2) retail; assumed forever: no forever extract, so its talents, auction and SHARED
-- addons follow retail.
local MAP = { addon = "Blizzard_WorldMap", lod = false, toggle = "ToggleWorldMap", frame = "WorldMapFrame" }
local TALENTS_CLASSIC = { addon = "Blizzard_TalentUI", toggle = "ToggleTalentFrame", frame = "PlayerTalentFrame" }

local MAINLINE = {
  talents = { addon = "Blizzard_PlayerSpells", toggle = "TogglePlayerSpellsFrame", frame = "PlayerSpellsFrame" },
  map = MAP,
  merchant = { addon = "Blizzard_UIPanels_Game", lod = false, interaction = "Merchant", open = "MERCHANT_SHOW" },
  mail = { addon = "Blizzard_MailFrame", lod = false, interaction = "MailInfo", open = "MAIL_SHOW", frame = "MailFrame" },
  auction = { addon = "Blizzard_AuctionHouseUI", interaction = "Auctioneer", open = "AUCTION_HOUSE_SHOW" },
  transmog = { addon = "Blizzard_Transmog", also = { "Blizzard_Collections" }, interaction = "Transmogrifier", open = "TRANSMOGRIFY_OPEN" },
}

-- source: confirmed (B1, Ruling R12-a) an addon name is its folder name: Blizzard_UIPanels_Game, whose
-- Blizzard_UIPanels_Game_Classic.toc the classic family reads (blizzard_ui.lua tocOf). That TOC gates TBC\MerchantFrame to
-- tbc, wrath, cata, mists and loads Classic\MailFrame ungated; assumed (B2) the engine-side caller of both, so the kit
-- calls their show globals.
local MERCHANT_CLASSIC =
  { addon = "Blizzard_UIPanels_Game", lod = false, show = "MerchantFrame_MerchantShow", open = "MERCHANT_SHOW", frame = "MerchantFrame" }
local MAIL_CLASSIC = { addon = "Blizzard_UIPanels_Game", lod = false, show = "MailFrame_Show", open = "MAIL_SHOW", frame = "MailFrame" }

-- confirmed (B1): the tbc auction window at 2.5.6.70577 is the legacy Blizzard_AuctionUI (the installed TOCs list it).
local CLASSIC = {
  talents = TALENTS_CLASSIC,
  map = MAP,
  merchant = MERCHANT_CLASSIC,
  mail = MAIL_CLASSIC,
  auction = { addon = "Blizzard_AuctionUI", open = "AUCTION_HOUSE_SHOW" },
}

M.WINDOWS = {
  retail = MAINLINE,
  forever = MAINLINE,
  tbc = CLASSIC,
  vanilla = CLASSIC,
  mists = {
    talents = TALENTS_CLASSIC,
    map = MAP,
    merchant = MERCHANT_CLASSIC,
    mail = MAIL_CLASSIC,
    auction = { addon = "Blizzard_AuctionUI", also = { "Blizzard_AuctionHouseUI" }, open = "AUCTION_HOUSE_SHOW" },
    transmog = { addon = "Blizzard_Collections", open = "TRANSMOGRIFY_OPEN" },
  },
}

-- source: confirmed (B2) retail uiparentpanelmanager.lua:861; the classic family's Shared/UIParentPanelManager.lua:828 at
-- the pins 2cfec7c, 8165d4c and 15c8a75. The addon that defines ShowUIPanel and HideUIPanel.
M.BASE = {}
for flavor in pairs(M.WINDOWS) do
  M.BASE[flavor] = { "Blizzard_UIParentPanelManager" }
end

-- source: confirmed (B1) retail; assumed forever. Addons that load at startup without being a window's own (Ruling C3).
-- Blizzard_FrameEffects has no LoadOnDemand line (blizzard_frameeffects.toc) and Blizzard_ClassTalentsFrame.lua:1302 calls its
-- GlowEmitterFactory, so it loads at startup too.
local SHARED = { "Blizzard_SharedTalentUI", "Blizzard_TransmogShared", "Blizzard_FrameEffects" }
M.SHARED = { retail = SHARED, forever = SHARED, mists = {}, tbc = {}, vanilla = {} }

-- source: confirmed (row BU16) the classic family: Blizzard_MoneyFrame has no LoadOnDemand line and DefaultState enabled
-- (tbc 70577 blizzard_moneyframe.toc), and the XML OnLoad of Blizzard_UIPanels_Game's merchant (TBC\MerchantFrame.xml:71,
-- SmallMoneyFrame_OnLoad) and the classic mail file (Classic\MailFrame.lua:38) call it although that addon's classic TOC does
-- not depend on it; so it loads before every other layer addon. Assumed for vanilla and mists (one shared classic Interface
-- tree, Ruling R12-a). Retail lists it as a dependency.
local CLASSIC_FIRST = { "Blizzard_MoneyFrame" }
M.FIRST = { retail = {}, forever = {}, mists = CLASSIC_FIRST, tbc = CLASSIC_FIRST, vanilla = CLASSIC_FIRST }

return M
