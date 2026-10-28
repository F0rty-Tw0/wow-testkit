-- Names only: the global functions a tainted caller may not run (row TS8, protected) or may not run in combat
-- (row TS8, nocombat), and the widget methods beyond the documentation flags that a tainted caller may not run on a protected
-- frame in combat (row TS9). Which of these a flavour has is decided by its API data: a name it lacks is never gated.
local M = {}

local function set(names)
  local out = {}
  for name in names:gmatch("%S+") do
    out[name] = true
  end
  return out
end

-- source: assumed (row TS8) the wiki category API_functions/restricted, label protected (114 names), plus
-- C_TooltipComparison.CompareItem, which the documentation of the 70575 extract flags.
M.protected = set([[
  AcceptBattlefieldPort AcceptSpellConfirmationPrompt AssistUnit AttackTarget C_Club.CreateClub C_Club.CreateTicket C_Club.KickMember
  C_Club.RedeemTicket C_Club.SendCharacterInvitation C_Container.UseContainerItem C_Container.UseHearthstone C_CovenantSanctumUI.DepositAnima
  C_GuildInfo.Demote C_GuildInfo.Disband C_GuildInfo.Leave C_GuildInfo.Promote C_GuildInfo.SetLeader C_GuildInfo.Uninvite
  C_Item.ConfirmBindOnUse C_Item.UseItemByName C_ItemUpgrade.UpgradeItem C_Macro.RunMacroText C_MountJournal.ApplyMountEquipment
  C_Ping.SendMacroPing C_Ping.TogglePingListener C_PingSecure.ClearPendingPingInfo C_PingSecure.CreateFrame C_PingSecure.DisplayError
  C_PingSecure.GetTargetPingReceiver C_PingSecure.GetTargetWorldPing C_PingSecure.GetTargetWorldPingAndSend C_PingSecure.SendPing
  C_PingSecure.SetPendingPingOffScreenCallback C_PingSecure.SetPingCooldownStartedCallback C_PingSecure.SetPingPinFrameAddedCallback
  C_PingSecure.SetPingPinFrameRemovedCallback C_PingSecure.SetPingPinFrameScreenClampStateUpdatedCallback
  C_PingSecure.SetPingRadialWheelCreatedCallback C_PingSecure.SetSendMacroPingCallback C_PingSecure.SetTogglePingListenerCallback
  C_PlayerInteractionManager.InteractUnit C_ReportSystem.InitiateReportPlayer C_ReportSystem.SendReport C_ReportSystem.SendReportPlayer
  C_Social.TwitterCheckStatus C_Social.TwitterConnect C_Social.TwitterDisconnect C_SpellBook.CastSpellBookItem CameraOrSelectOrMoveStart
  CameraOrSelectOrMoveStop CancelItemTempEnchantment CancelLogout CancelShapeshiftForm CastPetAction CastShapeshiftForm CastSpell
  CastSpellByName ClearTarget CopyToClipboard DeclineSpellConfirmationPrompt DescendStop DestroyTotem FocusUnit ForceLogout ForceQuit
  GuildControlSetRank GuildControlSetRankFlag GuildDemote GuildPromote GuildUninvite JoinBattlefield JumpOrAscendStart LaunchURL Logout
  MoveBackwardStop MoveForwardStop PetAssistMode PetAttack PetDefensiveAssistMode PlaceGlyphInSocket PortGraveyard ProcessExceptionClient Quit
  RemoveGlyphFromSocket ReplaceEnchant ReplaceTradeEnchant RunMacro RunMacroText SetAllowDangerousScripts SetMoveEnabled SetRaidTarget
  SetTurnEnabled SitStandOrDescendStart SpellStopCasting SpellStopTargeting SpellTargetUnit StrafeLeftStart StrafeLeftStop StrafeRightStart
  StrafeRightStop Stuck TargetLastEnemy TargetLastTarget TargetNearestEnemy TargetNearestFriend TargetUnit ToggleRun TurnOrActionStart
  TurnOrActionStop TurnRightStop UseAction UseContainerItem UseToy UseToyByName
  C_TooltipComparison.CompareItem
]])

-- source: assumed (row TS8) the wiki category API_functions/restricted, label nocombat.
M.noCombat = set([[
  C_EquipmentSet.UseEquipmentSet C_Map.OpenWorldMap C_PetJournal.PickupPet C_PetJournal.SummonPetByGUID CancelUnitBuff ChangeActionBarPage
  CheckInteractDistance ClearOverrideBindings CreateMacro DeleteMacro EditMacro IsItemInRange PetStopAttack PickupAction PickupCompanion
  PickupInventoryItem PickupMacro PickupPetAction PickupSpell PickupSpellBookItem SetBinding SetBindingClick SetBindingItem SetBindingMacro
  SetBindingSpell SetOverrideBinding SetOverrideBindingClick SetOverrideBindingItem SetOverrideBindingMacro SetOverrideBindingSpell
  SetRaidSubgroup SwapRaidSubgroup
]])

-- source: assumed (row TS9) SetAttribute is restricted like the flagged methods; the API documentation does not flag it.
M.methods = { SetAttribute = true }

return M
