-- Menu API picks (menu_pick.lua): which open levels a response re-initializes, and the frames' enabled state.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function open(generator)
  return _G.MenuUtil.CreateContextMenu(_G.CreateFrame("Frame", nil, _G.UIParent), generator)
end

local function frameAt(w, depth, index)
  return w.menus[depth].entries[index].frame
end

-- isSelected reads flag.on; setSelected flips it and returns nothing, so a checkbox answers Refresh.
local function flagCheckbox(description, text, flag)
  return description:CreateCheckbox(text, function()
    return flag.on
  end, function()
    flag.on = not flag.on
  end)
end

-- Menu.lua:2259-2262: a non-closing response from a level-2 pick re-initializes level 1.
local function test_submenu_checkbox_pick_rereads_level_one()
  withFrameXML("retail", function(w)
    local flag = { on = false }
    open(function(_, root)
      flagCheckbox(root, "Shown", flag)
      flagCheckbox(root:CreateButton("More"), "Toggle", flag)
    end)
    Input.enter(w, frameAt(w, 1, 2))
    Input.click(w, frameAt(w, 2, 1), "LeftButton")
    A.eq(w.menus[1].entries[1].checked, true)
  end)
end

-- Menu.lua:2247-2254: Refresh on a checkbox that is also a submenu root re-initializes its open submenu.
local function test_refresh_on_a_submenu_root_checkbox_rereads_its_open_submenu()
  withFrameXML("retail", function(w)
    local flag = { on = false }
    open(function(_, root)
      flagCheckbox(flagCheckbox(root, "Mode", flag), "Child", flag)
    end)
    Input.enter(w, frameAt(w, 1, 1))
    Input.click(w, frameAt(w, 1, 1), "LeftButton")
    A.eq(#w.menus, 2)
    A.eq(w.menus[2].entries[1].checked, true)
  end)
end

-- MenuTemplates.lua:109-113: a re-initialize re-applies enabled to the entry's frame, so it becomes clickable.
local function test_refresh_that_enables_an_entry_makes_its_frame_clickable()
  withFrameXML("retail", function(w)
    local flag, picked = { on = false }, false
    open(function(_, root)
      flagCheckbox(root, "Allow", flag)
      local go = root:CreateButton("Go", function()
        picked = true
      end)
      go:SetEnabled(function()
        return flag.on
      end)
    end)
    A.eq(Input.blockedReason(w, frameAt(w, 1, 2), "click") ~= nil, true)
    Input.click(w, frameAt(w, 1, 1), "LeftButton")
    A.eq(Input.blockedReason(w, frameAt(w, 1, 2), "click"), nil)
    Input.click(w, frameAt(w, 1, 2), "LeftButton")
    A.eq(picked, true)
  end)
end

return function()
  test_submenu_checkbox_pick_rereads_level_one()
  test_refresh_on_a_submenu_root_checkbox_rereads_its_open_submenu()
  test_refresh_that_enables_an_entry_makes_its_frame_clickable()
end
