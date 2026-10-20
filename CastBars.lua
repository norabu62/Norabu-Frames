-- Target and focus cast bars. The native cast bars are pinned hidden (they keep running
-- invisibly) and replaced by one bar per frame, driven by the client's duration objects so
-- it keeps working when cast data is protected in instances. Player cast bar: untouched.
-- Pet cast bar: hidden in Frames.lua.
local ADDON, NF = ...
local L = NF.layout


local GAP = 4          -- space between the cast bar and what it is stacked against
local ICON_GAP = 6     -- icon to bar (clears both borders)
local HOLD = 0.6       -- how long "Interrupted" / "Failed" stays up
local EVENTS = {
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
  "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local CastBars = {}
NF.CastBars = CastBars
local bars = {}

local GOLD, GREEN, GRAY
local function InitColors()
  if GOLD then return end
  GOLD = CreateColor(1, .7, 0, 1)
  GREEN = CreateColor(0, 1, 0, 1)
  GRAY = CreateColor(.7, .7, .7, 1)
end

-- Above the name (or directly above the bars when the name is inside them), or below the
-- bars: set by NF.db.castbarPosition.
local function Place(c)
  local u = c.u
  local T = u.size.border
  local f = c.frame
  f:ClearAllPoints()
  if NF.db and NF.db.castbarPosition == "below" then
    f:SetPoint("TOPLEFT", u.block, "BOTTOMLEFT", 0, -(T + GAP))
  elseif u.parts.name and not u.spec.nameInside then
    f:SetPoint("BOTTOM", u.parts.name, "TOP", 0, GAP)
  else
    f:SetPoint("BOTTOMLEFT", u.block, "TOPLEFT", 0, T + GAP)
  end
end

-- Standard cast gold / channel green, gray when it cannot be interrupted. The flag is
-- often protected, so it goes straight to the texture instead of being tested.
local function Tint(c, base, notInterruptible)
  local texture = c.bar:GetStatusBarTexture()
  if not texture then return end
  if texture.SetVertexColorFromBoolean then
    if NF.Readable(notInterruptible) and notInterruptible == nil then notInterruptible = false end
    texture:SetVertexColorFromBoolean(notInterruptible, GRAY, base)
  else
    texture:SetVertexColor(base:GetRGBA())
  end
end

local function Refresh(c)
  local unit = c.unit
  if not UnitExists(unit) then
    c.holdUntil, c.duration = nil, nil
    c.feedback:Hide()
    c.frame:Hide()
    return
  end
  if c.holdUntil then
    if GetTime() < c.holdUntil then c.frame:Show() return end
    c.holdUntil = nil
    c.feedback:Hide()
  end
  local duration, channel = UnitCastingDuration(unit), false
  if not duration then
    duration = UnitChannelDuration(unit)
    channel = duration ~= nil
  end
  if not duration then
    c.duration = nil
    c.frame:Hide()
    return
  end
  local text, texture, notInterruptible
  if channel then
    local _, t, tex, _, _, _, ni = UnitChannelInfo(unit)
    text, texture, notInterruptible = t, tex, ni
  else
    local _, t, tex, _, _, _, _, ni = UnitCastingInfo(unit)
    text, texture, notInterruptible = t, tex, ni
  end
  c.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
    channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
  c.text:SetText(text)
  c.icon:SetTexture(texture)
  Tint(c, channel and GREEN or GOLD, notInterruptible)
  c.duration = duration
  -- the remaining time may be protected: it is only ever handed to the font string
  c.timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
  c.frame:Show()
end

local function Feedback(c, label)
  c.holdUntil = GetTime() + HOLD
  c.duration = nil
  c.feedback:Show()
  c.text:SetText(label)
  c.timer:SetText("")
  c.frame:Show()
end

-- "Interrupted" / "Failed" only ever describe the cast this bar is showing. A failed attempt
-- at anything else (an instant spell, a second cast while one is running) arrives as the same
-- event and must not put up a red bar, so the feedback needs a cast on the bar and, when both
-- ids can be read, the same cast id.
local function OnEvent(c, event, _, castGUID)
  if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    local sameCast = c.duration ~= nil
    if sameCast and NF.Readable(castGUID) and NF.Readable(c.castGUID) and castGUID ~= nil and c.castGUID ~= nil
        and castGUID ~= c.castGUID then
      sameCast = false
    end
    if sameCast then
      Feedback(c, event == "UNIT_SPELLCAST_INTERRUPTED" and (INTERRUPTED or "Interrupted") or (FAILED or "Failed"))
    else
      Refresh(c)
    end
  elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
    c.holdUntil = nil
    c.castGUID = castGUID
    c.feedback:Hide()
    Refresh(c)
  else -- stop, delayed, channel update/stop, (not) interruptible, target/focus changed
    Refresh(c)
  end
end

local function Create(u)
  local size = u.size
  local height = size.hpHeight >= 24 and 14 or 12
  local T = 3

  local frame = CreateFrame("Frame", nil, u.frame)
  frame:SetFrameLevel(u.frame:GetFrameLevel() + 11)
  frame:SetSize(size.barWidth, height)
  frame:Hide()

  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetAllPoints(frame)
  bar:SetStatusBarTexture(NF.BarTexture())
  if not bar.SetTimerDuration then return nil end

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, .85)

  -- red wash shown briefly when the cast is interrupted or fails
  local feedback = bar:CreateTexture(nil, "ARTWORK", nil, 7)
  feedback:SetAllPoints()
  feedback:SetColorTexture(.55, .08, .06, 1)
  feedback:Hide()

  -- border, icon and text sit one frame above the bar so the ring overlaps its edge
  local over = CreateFrame("Frame", nil, frame)
  over:SetAllPoints(frame)
  over:SetFrameLevel(bar:GetFrameLevel() + 2)
  NF.CreateBorder(over, bar, T, L.borderInset)

  local icon = over:CreateTexture(nil, "ARTWORK")
  icon:SetSize(height, height)
  icon:SetPoint("RIGHT", bar, "LEFT", -ICON_GAP, 0)
  icon:SetTexCoord(.07, .93, .07, .93)
  local iconBg = over:CreateTexture(nil, "BACKGROUND")
  iconBg:SetAllPoints(icon)
  iconBg:SetColorTexture(0, 0, 0, .85)
  NF.CreateBorder(over, icon, T, L.borderInset)

  local timer = over:CreateFontString(nil, "OVERLAY")
  timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
  timer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  timer:SetJustifyH("RIGHT")

  local text = over:CreateFontString(nil, "OVERLAY")
  text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
  text:SetPoint("LEFT", bar, "LEFT", 4, 0)
  text:SetPoint("RIGHT", timer, "LEFT", -4, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)

  local c = {
    u = u, unit = u.unit, frame = frame, bar = bar, icon = icon, text = text, timer = timer,
    feedback = feedback, elapsed = 0,
  }

  for _, event in ipairs(EVENTS) do pcall(frame.RegisterUnitEvent, frame, event, u.unit) end
  frame:RegisterEvent(u.unit == "focus" and "PLAYER_FOCUS_CHANGED" or "PLAYER_TARGET_CHANGED")
  frame:SetScript("OnEvent", function(_, event, ...) OnEvent(c, event, ...) end)
  -- native timers animate the fill; this only watches for the cast ending and updates the time
  frame:SetScript("OnUpdate", function(_, dt)
    c.elapsed = c.elapsed + dt
    if c.elapsed < .1 then return end
    c.elapsed = 0
    Refresh(c)
  end)

  Place(c)
  return c
end

function CastBars.Setup(units)
  if not (UnitCastingDuration and UnitChannelDuration and UnitCastingInfo and UnitChannelInfo
      and Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection and CreateColor) then
    return -- client lacks the duration APIs: leave the native cast bars alone
  end
  InitColors()
  for _, key in ipairs({ "target", "focus" }) do
    local u = units[key]
    if u then
      local c = Create(u)
      if c then
        bars[key] = c
        local native = u.native.spellbar or _G[key == "focus" and "FocusFrameSpellBar" or "TargetFrameSpellBar"]
        if native then NF.HideFrame(native) end
        Refresh(c)
      end
    end
  end
end

-- Re-reads the position setting (used by the options panel).
function CastBars.Apply()
  for _, c in pairs(bars) do Place(c) end
end

-- Bar width follows the frame's bar width; height and icon follow its size class.
function CastBars.Resize()
  for _, c in pairs(bars) do
    local size = c.u.size
    local height = size.hpHeight >= 24 and 14 or 12
    c.frame:SetSize(size.barWidth, height)
    c.icon:SetSize(height, height)
    Place(c)
  end
end

function CastBars.ApplyTexture()
  for _, c in pairs(bars) do c.bar:SetStatusBarTexture(NF.BarTexture()) end
end
