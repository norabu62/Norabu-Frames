-- Bar text for the player, target and pet frames. Blizzard's own bar text is left hidden; each
-- bar gets three font strings (left / center / right) whose format comes from
-- NF.db.text[unit].hp / .mp. Health and power values can be protected in instances, so they
-- are only ever passed to the client's own formatters and into string.format.
local ADDON, NF = ...
local L = NF.layout

local Text = {}
NF.Text = Text

-- { key, menu label }; order is the order shown in the options panel
Text.FORMATS = {
  { "none", "None" },
  { "raw", "Raw value" },
  { "abbr", "Abbreviated" },
  { "pct", "Percent" },
  { "raw_pct", "Raw (percent)" },
  { "abbr_pct", "Abbreviated (percent)" },
  { "raw_max", "Raw / max" },
  { "abbr_max", "Abbreviated / max" },
}

local function Whole(value)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
  return value
end

local function Short(value)
  local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
  if abbreviate then return abbreviate(value) end
  return Whole(value)
end

-- 0-100 percent. Only available through the client's percent APIs (no arithmetic here).
local function Percent(unit, kind)
  local curve = CurveConstants and CurveConstants.ScaleTo100
  if not curve then return nil end
  if kind == "hp" then
    return UnitHealthPercent(unit, true, curve)
  end
  return UnitPowerPercent(unit, nil, false, curve)
end

local function Render(format, unit, kind)
  if format == "none" or not format then return "" end
  local cur, max
  if kind == "hp" then
    cur, max = UnitHealth(unit), UnitHealthMax(unit)
  else
    cur, max = UnitPower(unit), UnitPowerMax(unit)
  end
  if format == "raw" then return string.format("%s", Whole(cur)) end
  if format == "abbr" then return string.format("%s", Short(cur)) end
  if format == "raw_max" then return string.format("%s / %s", Whole(cur), Whole(max)) end
  if format == "abbr_max" then return string.format("%s / %s", Short(cur), Short(max)) end
  local pct = Percent(unit, kind)
  if pct == nil then return "" end
  if format == "pct" then return string.format("%.0f%%", pct) end
  if format == "raw_pct" then return string.format("%s (%.0f%%)", Whole(cur), pct) end
  if format == "abbr_pct" then return string.format("%s (%.0f%%)", Short(cur), pct) end
  return ""
end

local function UpdateKind(u, kind)
  local slots = u.slots and u.slots[kind]
  if not slots then return end
  local unit = u.unit
  local formats = NF.db.text[unit] and NF.db.text[unit][kind]
  if not formats or not UnitExists(unit) then return end
  for where, fs in pairs(slots) do
    local format = formats[where]
    if format == "none" then
      fs:SetText("")
    else
      local ok, text = pcall(Render, format, unit, kind)
      fs:SetText(ok and text or "")
    end
  end
end

function Text.UpdateHealth(u) UpdateKind(u, "hp") end
function Text.UpdatePower(u) UpdateKind(u, "mp") end

function Text.Update(u)
  UpdateKind(u, "hp")
  UpdateKind(u, "mp")
end

-- Font size follows the bar height.
function Text.Resize(u)
  if not u.slots then return end
  local hpSize = math.max(8, math.min(13, math.floor(u.size.hpHeight * .5)))
  local mpSize = math.max(8, math.min(11, math.floor(u.size.powerHeight * .8)))
  for kind, slots in pairs(u.slots) do
    local size = kind == "hp" and hpSize or mpSize
    for _, fs in pairs(slots) do fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
  end
end

function Text.Create(u)
  local pad = L.textPad
  -- the side facing the portrait gets extra padding so numbers clear the overlapping ring
  local near = pad + (u.spec.portrait and u.spec.overlap or 0)
  local leftPad = u.mirrored and pad or near
  local rightPad = u.mirrored and near or pad
  u.slots = {}
  for _, kind in ipairs({ "hp", "mp" }) do
    local bar = kind == "hp" and u.hp or u.power
    local slots = {}
    for _, where in ipairs({ "left", "center", "right" }) do
      local fs = u.overlay:CreateFontString(nil, "OVERLAY")
      fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
      fs:SetTextColor(1, 1, 1)
      if where == "left" then
        fs:SetPoint("LEFT", bar, "LEFT", leftPad, 0)
        fs:SetJustifyH("LEFT")
      elseif where == "right" then
        fs:SetPoint("RIGHT", bar, "RIGHT", -rightPad, 0)
        fs:SetJustifyH("RIGHT")
      else
        fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
      end
      slots[where] = fs
    end
    u.slots[kind] = slots
  end
  Text.Resize(u)
end
