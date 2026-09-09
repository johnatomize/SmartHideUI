# SmartHideUI development guidance

## Core principle: reveal only what the interaction needs

SmartHideUI aims to keep the game world visible with as little UI as possible.
When an event occurs while the UI is hidden, show only the UI elements needed
for that event or interaction. Do not restore the entire UI just because the
player has become active, opened a panel, or started interacting with an NPC.

Include supporting controls when they serve a concrete purpose in the current
interaction. For example:

- Opening bags needs the bag windows, bag buttons in the lower right, action
  bars so items can be assigned to them, and item tooltips.
- Talking to a quest NPC needs the gossip/quest selection, quest details,
  progress, and reward windows as appropriate, plus relevant tooltips. It does
  not by itself require action bars or the rest of the HUD.
- Combat needs its own set of relevant controls and information, as defined by
  the combat visibility module.

These examples guide future features; use the same reasoning for other UI
elements and events. Avoid adding unrelated frames to a visibility mode merely
because they normally appear together in Blizzard's UI.

## Modular visibility policies

Keep interaction-specific policies in clearly named functions such as
`ApplyQuestUI`, `ApplyBagUI`, and `ApplyCombatUI`. Extend this pattern when adding
new interaction types.

- Each module should define the smallest useful set of visible frames for its
  interaction. Share frame lists for genuinely shared controls, such as action
  bars.
- Reuse common frame traversal, alpha preservation/restoration, and ancestor
  handling. Keep these mechanics separate from the decision about what to show.
- Route events and visibility updates through the appropriate module instead
  of scattering frame mutations or full-UI restoration across event handlers.
- Define priorities or composition explicitly when interactions overlap, such
  as combat during a quest conversation. Preserve necessary controls without
  using a full-UI reveal as the fallback.
- When an interaction closes, return to the appropriate remaining interaction
  or idle policy. Do not reveal the entire UI as a side effect of closing it.

## Preserve behavior and usability

Respect whether the UI was already visible or hidden when the interaction
started. A feature intended for hidden UI should not unnecessarily hide an
already visible UI. Preserve explicit user overrides such as `/shu off` and
`/shu show`.

Account for event ordering: selecting an NPC, pressing an interaction binding,
or receiving an event before its frame is shown must not briefly restore the
whole UI. Mouse movement, keyboard activity, and updates within an active
interaction should continue using that interaction's visibility policy.

Keep required ancestors visible without exposing unrelated siblings. Preserve
original alpha values and restore them correctly across mode transitions.
Maintain protected action buttons and key bindings; respect combat restrictions
and avoid unnecessary reparenting or Show/Hide changes to protected frames.

## Verification

For visibility changes, check entry from hidden and visible states, continued
interaction, closing, overlapping modes, and disabling the addon. Check for
unrelated UI flashing into view and for required controls remaining invisible.
Use available automated checks where useful, and clearly state when in-game
verification is still needed.

### Lua test runtime

Lua 5.1 is installed at
`C:\Users\johnh\AppData\Local\Programs\Lua\5.1\lua.exe`. The directory may be
present on `PATH`, but the Codex filesystem sandbox can prevent discovery or
execution because it is outside the workspace. Whenever the regression suite
needs to run, request escalated access for that exact executable, preferably
with the reusable prefix rule
`["C:\\Users\\johnh\\AppData\\Local\\Programs\\Lua\\5.1\\lua.exe"]`, then run:

`& 'C:\Users\johnh\AppData\Local\Programs\Lua\5.1\lua.exe' tests\tests.lua`
