local ADDON, NF = ...

NF.name = ADDON
NF.version = "0.1.0"
NF.media = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

-- Pixel layout shared by every module. border.tga / ring.tga / disc.tga are
-- generated for these exact numbers by tools/make_textures.py - change both
-- together (ring thickness is baked in, the rectangle border scales with `border`).
NF.layout = {
  portrait = 64,
  ringSize = 76,     -- drawn size of ring.tga around the portrait
  discSize = 68,     -- drawn size of disc.tga behind the portrait
  border = 4,        -- visible thickness of the soft black border
  borderInset = 1,   -- how far the border's inner edge overlaps the bars (no dark seam)
  barWidth = 119,    -- classic bar width
  hpHeight = 27,     -- classic name strip (15) + health bar (12) merged
  powerHeight = 12,  -- classic power bar
  portraitInset = 14,
  portraitTop = 18,
  portraitOverlap = 5, -- how far the portrait ring reaches over the bars (0 = just touching)
  barTop = 31,
  namePad = 3,       -- gap between the border and the name above it
  textPad = 4,       -- bar text distance from the bar's edge
  levelOffset = 24,  -- level number sits 45 degrees round the portrait ring: this far out and down
  levelBadge = 20,   -- inner diameter of the dark circle behind the level number
  levelFontDrop = 2, -- level number font is this many points smaller than Blizzard's, so it fits the circle
  pvpOffset = 46,    -- PvP crest centre, measured out from the portrait centre (clear of the ring)
  totAngle = 45,     -- target-of-target icon sits this many degrees round the target icon from the bottom, to the left
  totShiftX = 4,     -- ... then the whole ToT frame is nudged this far right
  totGap = 4,        -- gap between the target icon's ring and the top edge of the ToT bars
}
-- focus, pet and the two target-of-target frames: smaller bars, thinner border, no thick merge
NF.layout.compact = { barWidth = 83, hpHeight = 18, powerHeight = 8, border = 3 }
-- bar block distance from the frame's outer edge: the ring's outer edge is 4px
-- past the portrait, pulled back by the overlap
NF.layout.barInset = NF.layout.portraitInset + NF.layout.portrait + 4 - NF.layout.portraitOverlap

-- Bar text: one format per slot (left / center / right) for health and power, per frame.
-- Formats: none, raw, abbr, pct, raw_pct, abbr_pct, raw_max, abbr_max (see Text.lua).
local function TextDefaults(hp, mp)
  return { hp = hp, mp = mp }
end

local DEFAULTS = {
  classIconSet = "stormx",   -- "stormx" (bundled, personal use) or "client" (Blizzard atlas)
  eliteStyle = "classic",    -- elite/rare art: "classic" (bundled dragons, personal use) or "retail" (client atlases)
  castbarPosition = "above", -- target/focus cast bars: "above" the name, or "below" the bars
  barTexture = "client",     -- "client" | "flat" | "soft"
  sizes = {
    main = { barWidth = 119, hpHeight = 27, powerHeight = 12 },    -- player and target
    compact = { barWidth = 83, hpHeight = 18, powerHeight = 8 },   -- focus, pet, target of target
  },
  text = {
    player = TextDefaults({ left = "pct", center = "none", right = "raw" }, { left = "pct", center = "none", right = "raw" }),
    target = TextDefaults({ left = "pct", center = "none", right = "raw" }, { left = "pct", center = "none", right = "raw" }),
    pet = TextDefaults({ left = "none", center = "abbr", right = "none" }, { left = "none", center = "none", right = "none" }),
  },
}
NF.DEFAULTS = DEFAULTS

-- Fills in anything missing from `db` (recursively) without touching what is already set.
local function Merge(db, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(db[key]) ~= "table" then db[key] = {} end
      Merge(db[key], value)
    elseif db[key] == nil then
      db[key] = value
    end
  end
end

-- Back to the defaults, in place (the same table stays NF.db).
function NF.ResetDB()
  for key in pairs(NF.db) do NF.db[key] = nil end
  Merge(NF.db, DEFAULTS)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= ADDON then return end
  NorabuFramesDB = NorabuFramesDB or {}
  Merge(NorabuFramesDB, DEFAULTS)
  NorabuFramesDB.enabled = nil -- removed option: the addon always loads
  NF.db = NorabuFramesDB
  self:UnregisterEvent("ADDON_LOADED")
end)

-- Conflicts ----------------------------------------------------------------

function NF.FindConflict()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if loaded("ClassicFrames") then return "ClassicFrames" end
  if loaded("StormxUI") and not (StormxFramesDB and StormxFramesDB.unitFramesEnabled == false) then
    return "StormxUI unit frames"
  end
end

-- Protected ("secret") values ----------------------------------------------
-- In instances the client can hand back values addon code may not compare,
-- index or do maths on. They may still be passed straight to widget setters.

local issecret = issecretvalue or function() return false end
local canaccess = canaccessvalue or function() return true end

function NF.Readable(value)
  return not issecret(value) and canaccess(value)
end

-- Call a Unit* boolean query without ever testing a protected result.
function NF.Bool(fn, ...)
  if not fn then return false end
  local ok, value = pcall(fn, ...)
  return ok and NF.Readable(value) and (value and true or false)
end

-- Colors -------------------------------------------------------------------

local CLASS_COLORS = {
  WARRIOR = { .78, .61, .43 }, PALADIN = { .96, .55, .73 }, HUNTER = { .67, .83, .45 },
  ROGUE = { 1, .96, .41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0, .44, .87 },
  MAGE = { .41, .80, .94 }, WARLOCK = { .58, .51, .79 }, DRUID = { 1, .49, .04 },
}
NF.CLASS_COLORS = CLASS_COLORS

-- May return a protected token; callers must check NF.Readable before indexing.
function NF.ClassToken(unit)
  if UnitClassBase then
    local ok, token = pcall(UnitClassBase, unit)
    if ok then return token end
  end
  local ok, _, token = pcall(UnitClass, unit)
  if ok then return token end
end

-- Returns found, r, g, b. `found` is always a plain boolean; r/g/b may be
-- protected numbers and must only go to widget setters.
function NF.ClassColor(token)
  if NF.Readable(token) then
    if type(token) ~= "string" then return false end
    local c = CLASS_COLORS[token] or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
    if not c then return false end
    if c.r then return true, c.r, c.g, c.b end
    return true, c[1], c[2], c[3]
  end
  if C_ClassColor and C_ClassColor.GetClassColor then
    local ok, r, g, b = pcall(function() return C_ClassColor.GetClassColor(token):GetRGB() end)
    if ok then return true, r, g, b end
  end
  return false
end

function NF.HealthColor(unit)
  if NF.Bool(UnitIsPlayer, unit) then
    local found, r, g, b = NF.ClassColor(NF.ClassToken(unit))
    if found then return r, g, b end
    return .5, .5, .5
  end
  if NF.Bool(UnitIsTapDenied, unit) then return .5, .5, .5 end
  local ok, reaction = pcall(UnitReaction, unit, "player")
  if ok and NF.Readable(reaction) and reaction then
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
  end
  if NF.Bool(UnitIsFriend, "player", unit) then return 0, 1, 0 end
  if NF.Bool(UnitCanAttack, "player", unit) then return 1, 0, 0 end
  return 1, 1, 0
end

function NF.PowerColor(unit)
  local _, token, r, g, b = UnitPowerType(unit)
  local c = NF.Readable(token) and token and PowerBarColor and PowerBarColor[token]
  if c then return c.r, c.g, c.b end
  if NF.Readable(r) and r then return r, g, b end
  return 0, 0, 1
end

-- Class icons --------------------------------------------------------------

-- Sets `tex` to the unit's class icon. Returns true if an icon was applied.
-- "stormx" uses the bundled painted portraits (falls back to the client atlas
-- for classes without one); "client" uses Blizzard's classicon-* atlases.
function NF.SetClassIcon(tex, unit)
  local token = NF.ClassToken(unit)
  local readable = NF.Readable(token)
  if readable and type(token) ~= "string" then return false end
  tex:SetTexCoord(0, 1, 0, 1)
  local set = NF.db and NF.db.classIconSet or DEFAULTS.classIconSet
  if set == "stormx" and (not readable or CLASS_COLORS[token]) then
    -- A protected token is concatenated, never inspected, so the client resolves it.
    local ok, applied = pcall(function()
      return tex:SetTexture(NF.media .. "classportraits\\Class_" .. token .. ".tga")
    end)
    if ok and (not NF.Readable(applied) or applied ~= false) then return true end
  end
  local ok, applied = pcall(function() return tex:SetAtlas("classicon-" .. token) end)
  return ok and (not NF.Readable(applied) or applied ~= false)
end

-- Hiding native art -------------------------------------------------------
-- Blizzard re-shows and re-tints art during its own updates, so a one-off
-- SetAlpha(0) does not stick. Suppressed regions snap back to alpha 0 whenever
-- anything changes their alpha.

local suppressed = setmetatable({}, { __mode = "k" })

function NF.Suppress(region, on)
  if not region or not region.SetAlpha then return end
  local state = suppressed[region]
  if not state then
    state = { on = false }
    suppressed[region] = state
    hooksecurefunc(region, "SetAlpha", function()
      if state.on and not state.guard then
        state.guard = true
        region:SetAlpha(0)
        state.guard = false
      end
    end)
  end
  state.on = on ~= false
  state.guard = true
  region:SetAlpha(state.on and 0 or 1)
  state.guard = false
end

-- Pinning alpha is not enough for textures Blizzard animates or re-shows (glows and flashes
-- run alpha animations that ignore the base alpha). Textures and font strings are therefore
-- also moved under a frame that is never shown, which hides them whatever the client does to
-- them. Frames only get the alpha pin (moving them would disturb the native layout).
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local BANISHABLE = { Texture = true, MaskTexture = true, FontString = true }

function NF.Banish(region)
  if not region then return end
  if region.GetObjectType and BANISHABLE[region:GetObjectType()] and region.SetParent then
    region:SetParent(hiddenParent)
  end
  NF.Suppress(region)
end

-- Frames that must never be seen (native cast bars: their interrupted / failed states play
-- animations that would show a pinned-transparent frame). Every Show / SetShown(true) is undone.
local forcedHidden = setmetatable({}, { __mode = "k" })

function NF.HideFrame(frame)
  if not frame or not frame.Hide then return end
  NF.Suppress(frame)
  if not forcedHidden[frame] then
    forcedHidden[frame] = true
    hooksecurefunc(frame, "Show", function(self) self:Hide() end)
    if frame.SetShown then
      hooksecurefunc(frame, "SetShown", function(self, shown) if shown then self:Hide() end end)
    end
  end
  frame:Hide()
end

function NF.SuppressAll(...)
  for i = 1, select("#", ...) do
    local region = select(i, ...)
    if region then NF.Banish(region) end
  end
end
