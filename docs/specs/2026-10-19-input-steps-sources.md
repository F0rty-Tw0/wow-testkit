# Input steps: behavior sources

Records the verdict for each rule that `2026-10-19-input-steps-design.md` marks **(source)**. A rule is
`confirmed` when Blizzard's Lua shows it; the source column then gives `path:line` relative to
`mirror/gethe/<branch>/` under the testkit home (fetched by `tools/fetch.sh`). A rule is `assumed` when no Lua shows
it; the source column then names the warcraft.wiki.gg page that supports it, or says "no source". Every `assumed`
rule has a test whose name ends in `_assumed`. A source that contradicts the spec stops the work until the user
approves a spec change.

| Rule | Verdict | Source |
|---|---|---|

## Phase 2

Wiki pages are on warcraft.wiki.gg (`https://warcraft.wiki.gg/wiki/<page>`), read 2026-10-20. Blizzard paths are
relative to `mirror/gethe/<branch>/`. No Lua in the mirror sets or reads the rules below beyond the cited lines
(`Blizzard_Menu` and `UIDropDownMenu.lua` are the only checked-out UI Lua).

| Rule | Verdict | Source |
|---|---|---|
| I1 Button `Enable`/`Disable` fire `OnEnable`/`OnDisable` only when the state changes | assumed | no source: Widget_script_handlers says only "OnEnable(self) - Invoked when the frame is enabled."; `Interface/AddOns/Blizzard_Menu/MenuTemplates.lua:127-128` sets the handlers but shows no change guard |
| I2 `RegisterForClicks` default `"LeftButtonUp"`; accepts `"AnyUp"`, `"AnyDown"`, `"<Button>Up"`, `"<Button>Down"` | confirmed | wiki `API_Button_RegisterForClicks`: "The default button registered on new button objects is `LeftButtonUp`." and the value list `AnyUp`, `AnyDown`, `LeftButtonUp`/`Down`, `RightButtonUp`/`Down`, `MiddleButtonUp`/`Down`, `Button4Up`/`Down`, `Button5Up`/`Down`; call forms in `Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenu.lua:452-456` |
| I3 `Button:Click(button?)` on an enabled button runs `PreClick`, `OnClick`, `PostClick` with `(self, button or "LeftButton", false)`, skipping mouse and visibility checks; on a disabled one it does nothing | confirmed | wiki `API_Button_Click`: "The arguments to this function will be passed to the widget's PreClick, OnClick, and PostClick script handlers.", `button` default "= LeftButton", "does not fire the OnMouseDown and OnMouseUp script handlers", "This function does nothing if the Button widget is disabled, or if the button is already being clicked." Wiki is silent on mouse and visibility checks (only "a virtual mouse click") and on the default of the optional `isDown` (spec uses `false`) |
| I4 a CheckButton flips its checked state before `PreClick` | assumed | no source: wiki `UIOBJECT_CheckButton` says only "Interacting with anything within the HitRectInsets toggles the button state" and `API_CheckButton_SetChecked` "Does not fire OnClick"; neither gives the order of the flip |
| I5 mouse defaults: Button, CheckButton, EditBox start mouse-enabled; setting `OnEnter`/`OnLeave`/`OnMouseDown`/`OnMouseUp` implies `EnableMouse(true)` (both) | auto-enable: confirmed (user ruling 2026-10-20 to follow the wiki; spec updated); per-type defaults: assumed | was CONTRADICTED in part by wiki `API_ScriptRegion_EnableMouse`: "Setting the OnEnter/Leave, OnMouseDown/Up script automatically implies `EnableMouse(true)`" and "EnableMouse implies SetMouseMotionEnabled and SetMouseClickEnabled", so one script would enable both (the spec enables only the matching one; the wiki text may predate the click/motion split). Defaults for Button, CheckButton, EditBox unsettled: the wiki only gives a fresh Frame as mouse-disabled; `Interface/AddOns/Blizzard_Menu/MenuTemplates.lua:597-600` enables both on a pooled Button explicitly |
| I6 EditBox `SetText` fires `OnTextChanged(self, false)`, and whether `OnTextSet` fires too (and in which order) | confirmed | wiki `UIHANDLER_OnTextSet`: "Fires when setting text programmatically." and "Fires before OnTextChanged"; `UIHANDLER_OnTextChanged`: "True when changing as a result of user input, false when programmatically set." Verdict: `SetText` fires `OnTextSet(self)` first, then `OnTextChanged(self, false)`. The `API_EditBox_SetText` page itself names no scripts |
| I7 a click fires `OnMouseDown(self, button)` then `OnMouseUp(self, button, true)` | confirmed | wiki `UIHANDLER_OnClick`: "Preceeded by OnMouseDown, OnMouseUp and PreClick; and followed by PostClick." Signatures from `Widget_script_handlers`: "OnMouseDown(self, button)", "OnMouseUp(self, button, upInside)"; `UIHANDLER_OnMouseUp`: `upInside` is "Whether the cursor was over the frame at moment of the input received" (true for a click). The wiki gives no order for a Down-registered `OnClick` between the two |
| I8 typing a character fires `OnChar(self, char)` then `OnTextChanged(self, true)` | confirmed | wiki `UIHANDLER_OnChar`: signature "(self, text)", text is "The UTF-8 character.", "Fires before OnTextChanged."; `UIHANDLER_OnTextChanged`: "True when changing as a result of user input". Per character only for typing: "When pasting text, this script fires once for each character pasted (OnTextChanged will only fire once at the end)." |
| I9 `GetMouseFoci()` returns `{}` when nothing has the mouse | confirmed | wiki `API_GetMouseFoci`: "This function can return an empty table in cases where the mouse is off-screen, or is over the WorldFrame without first enabling it for mouse motion events."; returns a table, never nil: `Interface/AddOns/Blizzard_APIDocumentationGenerated/InputDocumentation.lua:54-60` (live; `classic_era` line 30), `Nilable = false` |
| I10 over the 3D world the focus is `WorldFrame` only when its mouse motion is enabled, else none (`GetMouseFoci()` → `{}`) (`s:hover`) | confirmed (user ruling 2026-10-20; spec updated) | was CONTRADICTED by wiki `API_GetMouseFoci`: "This function can return an empty table in cases where the mouse is off-screen, or is over the WorldFrame without first enabling it for mouse motion events." (over the world the new API gives `{}` unless the addon enabled motion on `WorldFrame`). Only the removed `GetMouseFocus` is documented to return it: wiki `API_GetMouseFocus` example `/dump GetMouseFocus():GetName() -- WorldFrame`. `Interface/AddOns/Blizzard_Menu/Menu.lua:67-72` guards `foci[1]` against nil |
| I11 (added by this plan) the mouse focus is already the frame while its `OnEnter` runs and already cleared while its `OnLeave` runs | assumed | no source: no wiki page (`UIHANDLER_OnEnter`, `UIHANDLER_OnLeave`, `API_ScriptRegion_IsMouseOver`) says when focus changes relative to the handler, and no `Blizzard_Menu` handler reads the focus inside `OnEnter`/`OnLeave` (`MenuTemplates.lua:173` reads `IsMouseMotionFocus` at init, not in a handler) |

## Phase 3

## Phase 4

## Phase 5
