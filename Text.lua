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

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- 0-100 percent. Only available through the client's percent APIs (no arithmetic here).
-- kind: "hp" health, "mp" the unit's main power, "alt" mana (the druid mana bar in cat / bear form).
local function Percent(unit, kind)
  local curve = CurveConstants and CurveConstants.ScaleTo100
  if not curve then return nil end
  if kind == "hp" then
    return UnitHealthPercent(unit, true, curve)
  end
  return UnitPowerPercent(unit, kind == "alt" and MANA or nil, false, curve)
end

local function Render(format, unit, kind)
  if format == "none" or not format then return "" end
  local cur, max
  if kind == "hp" then
    cur, max = UnitHealth(unit), UnitHealthMax(unit)
  elseif kind == "alt" then
    cur, max = UnitPower(unit, MANA), UnitPowerMax(unit, MANA)
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
function Text.UpdateAlt(u)
  if u.altShown then UpdateKind(u, "alt") end
end

function Text.Update(u)
  UpdateKind(u, "hp")
  UpdateKind(u, "mp")
  Text.UpdateAlt(u)
end

-- Font size comes from the options (per frame: health and power; the druid mana bar uses the
-- power size).
function Text.Resize(u)
  if not u.slots then return end
  local sizes = NF.db.fontSize and NF.db.fontSize[u.unit]
  local hpSize = sizes and sizes.hp or 12
  local mpSize = sizes and sizes.mp or 12
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
  local kinds = { "hp", "mp" }
  if u.alt then kinds[#kinds + 1] = "alt" end
  for _, kind in ipairs(kinds) do
    local bar = (kind == "hp" and u.hp) or (kind == "alt" and u.alt) or u.power
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
      -- the druid mana text only exists while its bar does
      if kind == "alt" then fs:SetShown(u.altShown and true or false) end
      slots[where] = fs
    end
    u.slots[kind] = slots
  end
  Text.Resize(u)
end
