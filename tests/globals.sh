#!/bin/sh
# Fail if the addon reads or writes a global that isn't on the list below.
# Catches a local used before it's defined, which Lua silently treats as a nil global.
# Run from the repo root: sh tests/globals.sh
cd "$(dirname "$0")/.." || exit 1

ALLOWED="_G CANCEL C_AddOns C_Container C_Item C_Spell C_TooltipInfo C_TradeSkillUI C_UnitAuras
CampKitCharDB CampKitDB CooldownFrame_Set CreateFont CreateFrame GameTooltip
GetAddOnMetadata GetContainerItemInfo GetContainerNumSlots GetItemCooldown
GetItemCount GetItemInfo GetItemInfoInstant GetItemSpell GetLocale GetNumTradeSkills GetSpellCooldown
GetSpellTexture GetTradeSkillInfo GetTradeSkillItemLink InCombatLockdown
InterfaceOptions_AddCategory InterfaceOptionsFrame_OpenToCategory MouseIsOver NO
NUM_BAG_SLOTS NUM_TOTAL_EQUIPPED_BAG_SLOTS RegisterStateDriver SLASH_CAMPKIT1 Settings
SlashCmdList STANDARD_TEXT_FONT StaticPopupDialogs StaticPopup_Show UIParent UnitBuff
UnregisterStateDriver WorldFrame YES
ipairs math pairs pcall print select table tonumber tostring type unpack wipe"

status=0
for f in $(grep -v '^#' CampKit.toc | grep '\.lua$'); do
    [ -f "$f" ] || continue
    for g in $(luac -l -p "$f" | grep -oE '_ENV "[A-Za-z_0-9]+"' | sed 's/_ENV "//; s/"//' | sort -u); do
        case " $(echo $ALLOWED) " in
            *" $g "*) ;;
            *) echo "FAIL $f uses unknown global: $g"; status=1 ;;
        esac
    done
done
[ $status -eq 0 ] && echo "globals ok"
exit $status
