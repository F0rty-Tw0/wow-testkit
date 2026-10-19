# Scenario input steps: click, hover, typing, menus

Date: 2026-10-19. Status: design, awaiting review (revision 3, after three review rounds).

## Goal

Let agents drive an addon's UI the way the user does by hand in the live client, so manual testing moves into
scenarios: click buttons and checkboxes, hover frames, type into edit boxes, open and pick menu entries. Each step
fires the same handlers, in the same order and with the same arguments, as the live client.

The idea comes from WowSim (github.com/Photronix2020/WowSim). It has no license, so nothing is copied from it; this
is the kit's own design.

The user's real target is WhisperMessenger (installed at
`F:\Battle.net\World of Warcraft\_retail_\Interface\AddOns\WhisperMessenger`). It uses both menu systems and picks
between them by what the menu needs, not by flavor (`UI/ChatBubble/ContextMenu.lua:101-102`):

- Menu API: `MenuUtil.CreateContextMenu` with `CreateButton`/`CreateCheckbox`/`CreateRadio`/`CreateTitle`/
  `CreateDivider`/`SetScrollMode`; `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")` with
  `SetupMenu`; `Menu.ModifyMenu` on Blizzard's friend menus; `UnitPopup_OpenMenu` for player rows
  (`UI/ContactsList/ContextMenu.lua:209-229`).
- UIDropDownMenu: `UIDropDownMenu_Initialize`/`UIDropDownMenu_CreateInfo`/`UIDropDownMenu_AddButton`, display mode
  `"MENU"` (`UI/ChatBubble/ContextMenu.lua:144-166`).

The kit's generated data lists both systems on all five flavors (`"MenuUtil.CreateContextMenu"` and
`UIDropDownMenu_Initialize` in each `api/<flavor>/globals.lua` framexml section), so both are faked on every flavor
that lists them.

## Scope

Five slices, each built on the one before; the plan ships one PR per slice, in this order, and each slice must be
green (tests and lint) before the next starts:

1. Reference sources: `fetch.sh` checks out Blizzard's menu Lua on every branch.
2. Input: widget input methods, `input.lua`, mouse focus API, the click/hover/typing scenario steps.
3. Menu frames and UIDropDownMenu, the menu scenario steps, the menu snapshot.
4. Menu API: `MenuUtil`, `MenuResponse`, `Menu.ModifyMenu`, `UnitPopup_OpenMenu`, `s:openMenu`.
5. `DropdownButton` widget type and `WowStyle1DropdownTemplate`, then the WhisperMessenger manual check.

Out of scope, later projects: targeting by screen coordinates (needs a layout engine; comes with the viewer), the
HTML viewer, a long-running session process, SavedVariables round trip across `/reload`, keyboard input to frames
other than edit boxes (`OnKeyDown`/`OnKeyUp`, key bindings), drag and drop, mouse wheel, Blizzard's own entries
inside Blizzard-owned menus.

## Behavior source (slice 1)

Handler order, arguments and menu rules come from authoritative offline sources, never from a live client:

1. Blizzard's Lua in Gethe's `wow-ui-source`, same branches as `fetch.sh` today (`live` = Retail, `classic`,
   `classic_era`, `classic_anniversary`, `forever`). Every branch has `Interface/AddOns/Blizzard_Menu/` and an
   `UIDropDownMenu.lua` (`Blizzard_SharedXML/Mainline/` on live and forever, `.../Classic/` on the Classic
   branches). Both are added to the sparse checkout as reference files the kit never loads.
2. For engine-side rules that no Lua shows (handler order and arguments of C widgets): handler parameter names
   used in Blizzard's Lua, then warcraft.wiki.gg widget script pages.

`fetch.sh` runs `sparse-checkout set` on every fetch, not only on a fresh clone (today the update path at
`tools/fetch.sh:30-33` keeps the old patterns).

Every rule below marked **(source)** is checked in slice 2-5's first task against those sources. A rule confirmed
gets the source path in a short code comment. A rule no source settles stays as written and its test name ends in
`_assumed` (for example `test_click_flips_check_before_onclick_assumed`). A rule a source contradicts is fixed in
this spec before code is written.

## Input (slice 2)

### Widget methods (`ui/behaviour_input.lua`)

Methods are keyed by name across all widget types (`ui/widgets.lua:134`) and later behaviour modules override
earlier ones (`ui/behaviour.lua:273-277`). Every method here therefore branches on the widget type
(`st.plan.isA.<type>`) and delegates to the previous implementation (or the generic one) for other types.

- Button: `Enable`, `Disable`, `SetEnabled(enabled)`, `IsEnabled` (default enabled); `Enable`/`Disable` fire
  `OnEnable`/`OnDisable` when the state changes **(source)**. `RegisterForClicks(...)`: default `"LeftButtonUp"`;
  accepts `"AnyUp"`, `"AnyDown"`, `"<Button>Up"`, `"<Button>Down"` **(source: default)**. `Click(button?)`: on an
  enabled button runs `PreClick`, `OnClick`, `PostClick` with `(self, button or "LeftButton", false)`, skipping
  mouse and visibility checks; on a disabled one does nothing **(source: both)**.
- CheckButton: `SetChecked(checked)`, `GetChecked`.
- EditBox: `SetFocus` (fires `OnEditFocusLost` on the box that had focus, then `OnEditFocusGained` on the new
  one), `ClearFocus`, `HasFocus`; `SetText` fires `OnTextChanged(self, false)` **(source; and whether
  `OnTextSet` fires too)**. Other types keep `behaviour_text.lua`'s `SetText`.
- Mouse state: `EnableMouse` (today in `ui/behaviour.lua:244`) sets click and motion together;
  `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `IsMouseClickEnabled`, `IsMouseMotionEnabled` set and read them
  separately; `IsMouseEnabled` is true when either is. Defaults: Button, CheckButton and EditBox start with mouse
  enabled; setting an `OnEnter`, `OnLeave`, `OnMouseDown` or `OnMouseUp` script implies `EnableMouse(true)` (click and
  motion both; wiki `API_ScriptRegion_EnableMouse`, user ruling 2026-10-20); `OnClick` enables nothing
  **(source: the per-type defaults; assumed when unsettled)**.
- `IsMouseOver()`: true when the frame or one of its descendants is `w.input.mouseFocus`. `IsMouseMotionFocus()`:
  true when the frame is `w.input.mouseFocus`.

### World state and globals (`input.lua`)

`Widgets.install` (`ui/widgets.lua:216-223`, next to `w.ui`) sets `w.input = { mouseFocus = nil, editFocus = nil }`,
so every world with widgets has it, including the test helpers that build worlds with `Widgets.install` or
`FrameXML.installStage1` alone. `Input.install(w)` installs `GetMouseFoci()` with
`w:install("GetMouseFoci", fn, { gate = "api" })`: returns `{ focus }`, or `{}` when nothing has focus
**(source: empty value)**. `GetMouseFocus` is listed on no flavor today, so it is not installed.
`FrameXML.installStage1` calls `Input.install` after `Widgets.install`.

### Blocked reasons

`Input.blockedReason(w, frame, kind)` returns a string or nil; `kind` is `"click"`, `"enter"` or `"type"`. Checked
in this order, each naming the frame by name or parent chain:

1. `not a frame` (not a kit widget, or a name that resolves to nothing)
2. `hidden: <frame> is not shown` (first frame up the parent chain with `IsShown() == false`)
3. `mouse disabled` (click: click not enabled; enter: motion not enabled)
4. `disabled` (click on a Button with `IsEnabled() == false`; the user chose to fail here, although the client
   would still fire `OnMouseDown`/`OnMouseUp` on it)
5. `not registered for <button>` (click on a Button registered for neither `<button>Up` nor `<button>Down`)
6. `not an EditBox` (type)

### Actions

`Input.click(w, frame, button)`: fire `OnMouseDown(self, button)`; when registered for `<button>Down`, run the
click handlers with `down = true`; fire `OnMouseUp(self, button, true)` **(source)**; when registered for
`<button>Up`, run the click handlers with `down = false`. The click handlers: a CheckButton flips its checked
state, then `PreClick`, `OnClick`, `PostClick` with `(self, button, down)` **(source: order of the flip)**. A frame
that is not a Button gets only `OnMouseDown`/`OnMouseUp`.

`Input.enter(w, frame)`: when another frame has mouse focus, fire its `OnLeave(self, true)` first; then
`OnEnter(frame, true)` and set `w.input.mouseFocus`. `Input.leave(w, frame)` fires `OnLeave(self, true)` and
clears focus; when `frame` is not the current focus it throws `"leave: <frame> does not have the mouse"`. `leave`
and `press` have no blocked check of their own: `leave` needs the frame to have focus, `press` uses the `type`
check.

The existing `s:hover(unit)` hovers a unit in the 3D world, not a frame. It keeps its tooltip behavior and gains
one step first: the current frame focus, if any, gets `OnLeave(self, true)`, and `w.input.mouseFocus` becomes
`WorldFrame` when `WorldFrame:IsMouseMotionEnabled()`, else nil, so `GetMouseFoci()` returns `{}` over the world
unless motion was enabled on `WorldFrame` (wiki `API_GetMouseFoci`, user ruling 2026-10-20). It has no blocked
check.

`Input.type(w, box, text)`: `SetFocus` the box, then for each UTF-8 character (code point, not byte) append it to
the box's stored text directly (not through `SetText`) and fire `OnChar(self, char)` then
`OnTextChanged(self, true)` **(source: order)**. The cursor is always at the end.

`Input.press(w, box, key)`: `"ENTER"` → `OnEnterPressed(self)`, `"ESCAPE"` → `OnEscapePressed(self)`, `"TAB"` →
`OnTabPressed(self)`; any other key is a usage error. The box must have edit focus (keys go to the focused box),
else the step throws `"press: <box> does not have focus"`.

Handlers run through `w:callScript`, so an addon error inside one is recorded (`w:recordError`) and the step goes
on.

## Menus (slices 3 and 4)

### Model

A menu level is `{ entries, parentIndex, pick, rebuild }`: `entries` is a list of
`{ kind, text, enabled, checked, hasSubmenu, frame }` with `kind` one of `"button"`, `"checkbox"`, `"radio"`,
`"title"`, `"divider"`; `parentIndex` is the index, in the level below, of the entry that opened this level (nil on
level 1); `pick` and `rebuild` are kit functions (run a pick, re-render for `Refresh`). `w.menus` is the stack of
open levels (level 1 first, the last element is the deepest). `MenuFrames.install(w)` sets `w.menus = {}` and
`w.notes = {}`; `Scenario:report` appends `w.notes` to the report's notes when the world has it (worlds built
without `MenuFrames.install` have none).

Opening a level-1 menu, from either system, first closes every open level. `ToggleDropDownMenu(1, ...)` for the
dropdown frame that owns the open level 1 closes it instead of reopening **(source)**.

UIDropDownMenu `info` → kind: `isTitle` → title; `notCheckable` → button; `isNotRadio` → checkbox; else radio.
`hasArrow` → `hasSubmenu`. A divider is an `info` with `isTitle` and no text **(source)**.

### Frames (`framexml/fakes/menu_frames.lua`)

`MenuFrames.render(w, level)` turns a level into real frames:

- Each entry is a Button with a FontString label holding the raw text (color escapes kept). Titles and dividers
  have mouse disabled; disabled entries are `Disable()`d.
- Each entry Button gets kit-owned scripts set through the world: `OnClick` runs the pick (below); `OnEnter`
  opens the entry's submenu when it has one, or closes deeper levels when it has none. An addon that replaces
  these scripts on an entry frame removes that behavior, as in the client.
- Closing a level hides its frames; when the frame with mouse focus is among them, it gets `OnLeave(self, false)`
  and `w.input.mouseFocus` is cleared **(source)**; a level's frames are reused when it opens again; unused entry frames are
  hidden.
- UIDropDownMenu levels use Blizzard's names: `DropDownList1`..`DropDownList3` are created hidden at install
  (before `framexml.fakes.frames` in STAGE1, so its lazy lookup does not make inert stand-ins for them;
  `api/<flavor>/globals.lua` lists them as frames), and `DropDownList<L>Button<i>` is created on first use.
- Menu API levels are unnamed frames parented to `UIParent`.

A pick runs addon callbacks with `w:callAsAddon`, changed to return `w:try`'s packed result
(`world_events.lua:36-54`; today it drops it), so the callback's `MenuResponse` can be read. `w:callScript` is not
used for menu callbacks.

### UIDropDownMenu (`framexml/fakes/dropdown.lua`)

Installed when `w.globals.framexml.UIDropDownMenu_Initialize` is true (all five flavors today). Provides
`UIDropDownMenu_Initialize(frame, init, displayMode, level, menuList)`, `UIDropDownMenu_CreateInfo()`,
`UIDropDownMenu_AddButton(info, level)`, `ToggleDropDownMenu(level, value, frame, anchor, x, y, menuList)` (calls
`init(frame, level, menuList)` and renders level `level`), `CloseDropDownMenus(level?)`,
`UIDropDownMenu_SetText`/`GetText`/`SetWidth`/`SetSelectedValue`/`GetSelectedValue`; each only where its name is
listed. `CreateFrame(..., "UIDropDownMenuTemplate")` already works on every flavor (`ui/templates.lua` entries
apply without a flavor check, `ui/widgets.lua:183-197`). `EasyMenu` is listed on no flavor and is not faked.

`UIDropDownMenu_Initialize` stores `init`, `displayMode` and `menuList` on the frame (`frame.initialize`,
`frame.displayMode`, `frame.menuList`) and calls `init(frame, level or 1, menuList)` right away, as the client
does; `AddButton` calls made then go into a hidden scratch level that is discarded and opens nothing.
`AddButton` with no Initialize or Toggle running is ignored. `ToggleDropDownMenu` with `frame = nil` (submenus)
uses the dropdown frame that owns the open level 1, and its stored `initialize`. All of this is **(source)**.

`info` fields honored: `text`, `func(self, arg1, arg2, checked)`, `arg1`, `arg2`, `checked` (bool or function),
`isNotRadio`, `notCheckable`, `hasArrow`, `value`, `menuList`, `disabled`, `isTitle`, `keepShownOnClick`. A pick
calls `func` and closes all levels unless `keepShownOnClick` **(source: order of close vs func, the `checked`
value passed)**. Entering an entry with `hasArrow` calls `ToggleDropDownMenu(level + 1, info.value, nil, nil, nil,
nil, info.menuList)` **(source: exact arguments)**.

### Menu API (`framexml/fakes/menu.lua`)

Installed when `w.globals.framexml["MenuUtil.CreateContextMenu"]` is true (all five flavors today); that one key
gates `MenuUtil`, `Menu`, `MenuResponse` and `MenuInputContext` together, since the Ketho lists do not carry the
others.

- `MenuUtil.CreateContextMenu(owner, generator)`: a root description, `generator(owner, rootDescription)`, render
  level 1.
- Descriptions: `CreateButton(text, callback, data)`, `CreateCheckbox(text, isSelected, setSelected, data)`,
  `CreateRadio(text, isSelected, setSelected, data)`, `CreateTitle(text)`, `CreateDivider()`,
  `SetScrollMode(height)` (recorded, no effect), `SetEnabled(boolOrFn)`, `SetTooltip(fn)` (recorded),
  `SetTag(tag, contextData)`. An element with children is a submenu; its children are its next level.
- Callback arguments **(source: all four)**: `callback(data, menuInputData, menu)`, `isSelected(data)` (called
  when a level renders and after each pick), `setSelected(data, menuInputData, menu)`, enabled predicate
  `fn(description)`. `menuInputData` is `{ context = MenuInputContext.MouseButton, buttonName = <button> }`, with
  `MenuInputContext` values taken from Blizzard's Lua **(source)**. `MenuUtil.CreateContextMenu` returns the menu
  object, which is also the `menu` callback argument: the level-1 menu frame with `Close()` added **(source)**.
- `MenuResponse`: after a pick the menu closes unless the callback returns `MenuResponse.Open` (stay) or
  `MenuResponse.Refresh` (stay and re-render from the generator into the same frames) **(source: values and the
  default per entry kind)**.
- `Menu.ModifyMenu(tag, fn)`: stores `fn` under `tag`. Opening a menu whose root has that tag runs every stored
  `fn(owner, rootDescription, contextData)` after the generator.
- `UnitPopup_OpenMenu(which, contextData)` (where listed: all five flavors today): opens a Blizzard-owned menu
  with no entries of its own, tag `"MENU_UNIT_" .. which` **(source: tag format)**, owner a fresh unnamed Frame
  parented to `UIParent`; runs the `ModifyMenu` hooks; adds the report note "Blizzard's own entries are not
  simulated".

## DropdownButton (slice 5)

No flavor's widget data lists `DropdownButton` as a type, so `CreateFrame` rejects it today
(`ui/widgets.lua:206-208`), and every per-type step (ancestors, plan, script support) keys off the flavor's widget
list (`ui/inherits.lua:58-77`, `ui/widgets.lua:64-75`, `ui/scripts.lua:10-29`). Plans and the manifest are cached
across worlds (`ui/widgets.lua:23-39`, `manifest.lua:62-70`), so the type must not be added to shared data.

New per-world hook: `Widgets.registerIntrinsic(w, name, baseType, methods)` stores
`{ baseType, methods }` in `w.ui.intrinsics[name]`. `CreateFrame` checks `w.ui.intrinsics` before the catalog;
the frame's plan is a copy of `baseType`'s plan with `methods` added, `type = name`, `scriptType = baseType`, and
`isA[name:lower()] = true` on top of the base type's `isA`. Intrinsic methods are `fn(w, obj, st, ...)` like
`ui/behaviour.lua`, bound over the base class's methods. `Scripts.supports` keeps its signature; `checkHandler` and
`HasScript` (`ui/behaviour_scripts.lua:12,32`) pass `st.plan.scriptType or st.plan.type`. The Menu API fake calls
`Widgets.registerIntrinsic(w, "DropdownButton", "Button", methods)` with `SetupMenu(generator)`, `GenerateMenu()`,
`OpenMenu()`, `CloseMenu()`, `IsMenuOpen()`, `SetDefaultText(text)`, `OverrideText(text)`, so it exists only in
worlds with the Menu API. The dropdown opens its menu like `MenuUtil.CreateContextMenu(self, generator)` from a
kit-owned `OnMouseDown`; on a dropdown whose menu is already open it closes the menu instead **(source: mouse
down vs click, and the toggle)**.

`ui/templates.lua` gets a `WowStyle1DropdownTemplate` entry (type `DropdownButton`). Template entries carry no
flavor; on a flavor without the Menu API, `CreateFrame("DropdownButton", ...)` already fails.

## Scenario steps and snapshot (slices 2 and 3)

Click, hover and typing steps ship in slice 2; menu steps and the snapshot in slice 3 (`s:openMenu` in slice 4).
`scenario.lua` is at 273 lines, so the new steps live in `scenario_input.lua`, which exports
`extend(Scenario)` adding its methods to the class; `scenario.lua` calls
`require("scenario_input").extend(Scenario)` right after defining the class (the class stays local, and the modules do not require each other). Each step runs under engine context like `s:hover`, and throws `"<step>: <reason>"` (ending the
flavor's run, reported as `fail`) when `Input.blockedReason` returns a reason.

| Step | Does |
|---|---|
| `s:click(frameOrName, button?)` | `Input.click`; `button` defaults to `"LeftButton"`; a string is looked up in the world's globals |
| `s:enter(frameOrName)` / `s:leave(frameOrName)` | `Input.enter` / `Input.leave` |
| `s:type(editBoxOrName, text)` | `Input.type` |
| `s:press(editBoxOrName, key)` | `Input.press` |
| `s:menu()` | returns `{ kind = "menu", levels = { { parentIndex, entries }, ... } }`: a fresh table per level and per entry (entry fields copied, `frame` kept as the same widget), without `pick`/`rebuild`; nil when no menu is open |
| `s:pick(textOrPath)` | a string matches one level-1 entry by its text with color escapes stripped; a path `{ "Sub", "Item" }` `s:enter`s each submenu entry (opening the next level), then `s:click`s the last; no match or several matches throws, listing that level's stripped entry texts |
| `s:openMenu(which, contextData)` | calls `UnitPopup_OpenMenu(which, contextData)`; on flavors without it, throws `"openMenu: UnitPopup_OpenMenu is not on <flavor>"` |
| `s:closeMenus()` | closes every open level |

`Snapshot.menu(value)` renders open levels only, one line per entry, indented two spaces per level: `[x] Text` /
`[ ] Text` (checkbox), `(o) Text` / `( ) Text` (radio), `Text` (button), `== Text ==` (title), `---` (divider),
`> Text` (submenu; a checkable entry with a submenu shows both, e.g. `[x] > Text`), ` (disabled)` appended to
disabled entries. An open submenu's entries follow its `> Text`
line; a closed submenu shows only that line. Text keeps color as runs, written the way `Snapshot.tooltip` writes
them (`Snapshot.runs`). `snapshotText` in `scenario.lua` checks `target.kind == "menu"` before calling
`GetObjectType`.

## Errors

- Blocked step or usage error (unknown key for `s:press`, `s:pick` with no open menu): throws at the scenario's
  call site; the flavor's report is `fail` and later steps do not run.
- Addon handler or menu callback error: recorded, the step continues.

## Install order

`framexml/fakes/init.lua` STAGE1 becomes: `core`, `minimap`, `colors`, `strings`, `slash`, `tooltip`,
`menu_frames`, `dropdown`, `menu`, `frames`. `menu_frames` creates the `DropDownList` frames, so it runs before
`frames`.

## Testing

TDD per `AGENTS.md`: one behavior per test, test files mirror sources.

- `tests/ui/test_behaviour_input.lua`, `tests/test_input.lua`, `tests/test_scenario_input.lua`,
  `tests/framexml/test_menu_frames.lua`, `tests/framexml/test_dropdown.lua`, `tests/framexml/test_menu.lua`; new
  cases in `tests/test_snapshot.lua` and `tests/test_scenario.lua` (menu snapshot target).
- Fixture addon `tests/fixtures/addons/Clicky`: a Button, a CheckButton, an EditBox, one Menu API context menu
  and one UIDropDownMenu menu (each with a submenu, a checkbox, a radio, a title, a divider, a disabled entry),
  and a `DropdownButton`. Both menus are exercised on every flavor that has them. The fixture grows per slice:
  each slice adds only the parts whose fakes it ships.
- Scenario `tests/fixtures/scenarios/scn_input.lua` clicks, hovers, types and picks, then snapshots both menus.
  Goldens are written only in a temp copy of the fixture, as `tests/test_cli.lua:29` does; the test asserts the
  snapshot texts directly.

Done when `bash scripts/test.sh`, `stylua --check .` and `luacheck .` pass, and one manual check holds: on a
scratch copy of WhisperMessenger (never the WoW folder), a scenario opens its contacts-list context menu for a
group row (`MenuUtil.CreateContextMenu`) and for a player row (`UnitPopup_OpenMenu` with its `ModifyMenu` hook) on
Retail and on Forever, and the snapshots list the entries its code builds.

## Branch

The uncommitted smoke work on `feat/loader-scenario` is committed or stashed first; this work starts on a new
branch from that point.
