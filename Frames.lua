local ADDON, NF = ...
local L = NF.layout
local MEDIA = NF.media

local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"

-- Bar fill texture, chosen in the options: the client's own, a flat fill, or a soft gradient.
local BAR_TEXTURES = {
  client = "Interface\\TargetingFrame\\UI-StatusBar",
  flat = "Interface\\Buttons\\WHITE8X8",
  soft = MEDIA .. "bar_soft.tga",
}
local function BarTexture()
  return BAR_TEXTURES[NF.db and NF.db.barTexture] or BAR_TEXTURES.client
end
NF.BarTexture = BarTexture

-- Bar sizes are loaded from the saved settings in Setup / ApplySizes; these tables are shared
-- by every frame of that kind, so changing them in place resizes them all.
local MAIN = { barWidth = L.barWidth, hpHeight = L.hpHeight, powerHeight = L.powerHeight, border = L.border }
local COMPACT = L.compact
NF.MAIN, NF.COMPACT = MAIN, COMPACT

local units = {}
NF.units = units

-- Small helpers ------------------------------------------------------------

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function Place(region, point, relative, relPoint, x, y)
  if not region or not relative then return end
  region:ClearAllPoints()
  region:SetPoint(point, relative, relPoint, x or 0, y or 0)
end

local function Collect(...)
  local list = {}
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value then list[#list + 1] = value end
  end
  return list
end

local function HookGlobal(name, fn)
  if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
end

local function HookMethod(object, name, fn)
  if object and type(object[name]) == "function" then hooksecurefunc(object, name, fn) end
end

-- Soft black border --------------------------------------------------------
-- Nine-slice built from media/border.tga (64x64: 16-texel corners, 32-texel
-- straight edges, ring 8 texels thick starting 3 texels in). One texel is
-- T/8 px, so a corner piece is 2T px and the ring's inner edge sits 11 texels
-- (T*11/8 px) inside the piece's outer edge. `inset` pulls the whole ring that
-- many px inward so its inner edge overlaps the content (no dark seam).

local function CreateBorder(parent, target, T, inset)
  local off = T * 11 / 8 - (inset or 0)
  local corner = T * 2
  local q, h = 16 / 64, 48 / 64
  local function piece(l, r, t, b)
    local tex = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    tex:SetTexture(MEDIA .. "border.tga")
    tex:SetTexCoord(l, r, t, b)
    return tex
  end
  local tl = piece(0, q, 0, q)
  tl:SetSize(corner, corner)
  tl:SetPoint("TOPLEFT", target, "TOPLEFT", -off, off)
  local tr = piece(h, 1, 0, q)
  tr:SetSize(corner, corner)
  tr:SetPoint("TOPRIGHT", target, "TOPRIGHT", off, off)
  local bl = piece(0, q, h, 1)
  bl:SetSize(corner, corner)
  bl:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -off, -off)
  local br = piece(h, 1, h, 1)
  br:SetSize(corner, corner)
  br:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", off, -off)

  local top = piece(q, h, 0, q)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bottom = piece(q, h, h, 1)
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = piece(0, q, q, h)
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local right = piece(h, 1, q, h)
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
end
NF.CreateBorder = CreateBorder

-- Native pieces we re-use --------------------------------------------------
-- Names follow the native frame layout that ClassicFrames also relies on.
-- Every lookup is nil-safe so a missing piece costs one feature, not the addon.

local function PlayerParts()
  local pf = PlayerFrame
  local content = pf.PlayerFrameContent
  local main = content and content.PlayerFrameContentMain
  local ctx = content and content.PlayerFrameContentContextual
  local cont = pf.PlayerFrameContainer
  local hpc = main and main.HealthBarsContainer
  local hpBar = hpc and hpc.HealthBar
  local mpc = main and main.ManaBarArea
  local mpBar = mpc and mpc.ManaBar
  return {
    main = main,
    ctx = ctx,
    name = _G.PlayerName or (main and main.Name),
    level = _G.PlayerLevelText or (main and main.LevelText),
    hp = {
      center = hpBar and hpBar.TextString,
      left = hpBar and hpBar.LeftText,
      right = hpBar and hpBar.RightText,
    },
    mp = {
      center = mpBar and mpBar.TextString,
      left = mpBar and mpBar.LeftText,
      right = mpBar and mpBar.RightText,
    },
    suppress = Collect(
      cont and cont.FrameTexture, cont and cont.AlternatePowerFrameTexture,
      cont and cont.VehicleFrameTexture, cont and cont.FrameFlash, cont and cont.PlayerPortrait,
      main and main.StatusTexture, main and main.LevelBackgroundCircle,
      hpc, mpc,
      ctx and ctx.PlayerRestLoop, ctx and ctx.AttackIcon, ctx and ctx.PlayerPortraitCornerIcon
    ),
  }
end

-- target and focus share one native template
local function TargetParts(native)
  local content = native.TargetFrameContent
  local main = content and content.TargetFrameContentMain
  local ctx = content and content.TargetFrameContentContextual
  local cont = native.TargetFrameContainer
  local hpc = main and main.HealthBarsContainer
  local hpBar = hpc and hpc.HealthBar
  local mpBar = main and main.ManaBar
  return {
    main = main,
    ctx = ctx,
    name = main and main.Name,
    level = main and main.LevelText,
    hp = {
      center = hpBar and hpBar.TextString,
      left = hpc and hpc.LeftText,
      right = hpc and hpc.RightText,
      dead = hpc and hpc.DeadText,
      unconscious = hpc and hpc.UnconsciousText,
    },
    mp = {
      center = mpBar and mpBar.TextString,
      left = mpBar and mpBar.LeftText,
      right = mpBar and mpBar.RightText,
    },
    suppress = Collect(
      cont and cont.FrameTexture, cont and cont.Flash, cont and cont.BossPortraitFrameTexture,
      cont and cont.Portrait,
      main and main.ReputationColor, main and main.LevelBackgroundCircle,
      hpc, mpBar,
      ctx and ctx.BossIcon
    ),
  }
end

-- Focus shows only the name, bars and raid marker: level, faction/PvP badge, leader,
-- quest, threat and hit text are all pinned hidden.
local function FocusParts(native)
  local parts = TargetParts(native)
  local ctx, main = parts.ctx, parts.main
  local hidden = Collect(
    parts.level, main and main.HitIndicator,
    ctx and ctx.HighLevelTexture, ctx and ctx.LeaderIcon, ctx and ctx.GuideIcon, ctx and ctx.QuestIcon,
    ctx and ctx.PvpBackgroundIcon, ctx and ctx.NumericalThreat
  )
  for _, region in ipairs(hidden) do parts.suppress[#parts.suppress + 1] = region end
  parts.level = nil
  return parts
end

local function ToTParts(tf)
  if not tf then return nil end
  local hpBar, mpBar = tf.HealthBar, tf.ManaBar
  return {
    name = tf.Name,
    hp = { dead = hpBar and hpBar.DeadText, unconscious = hpBar and hpBar.UnconsciousText },
    mp = {},
    suppress = Collect(tf.FrameTexture, tf.Portrait, hpBar, mpBar),
  }
end

local function PetParts()
  if not _G.PetFrame then return nil end
  return {
    name = _G.PetName,
    hp = {
      center = _G.PetFrameHealthBarText,
      left = _G.PetFrameHealthBarTextLeft,
      right = _G.PetFrameHealthBarTextRight,
    },
    mp = {
      center = _G.PetFrameManaBarText,
      left = _G.PetFrameManaBarTextLeft,
      right = _G.PetFrameManaBarTextRight,
    },
    happiness = _G.PetFrameHappiness,
    hitText = _G.PetHitIndicatorText,
    suppress = Collect(
      _G.PetFrameTexture, _G.PetFrameFlash, _G.PetPortrait, _G.PetFrameHealthBar, _G.PetFrameManaBar,
      _G.PetAttackModeTexture, _G.PetFrameOverAbsorbGlow
    ),
  }
end

-- Where each kept native decoration goes, relative to my portrait/bar block.
-- add(region, point, relativeTo, relativePoint, x, y, width, height, keepParent)

local function AddLevel(u, add, region, w, h)
  local lp = u.levelPos
  if lp then add(region, lp[1], lp[2], lp[3], lp[4], lp[5], w, h) end
end

local function PlayerDecorations(u, add)
  local p, por = u.parts, u.portrait
  local ctx, main = p.ctx, p.main
  AddLevel(u, add, p.level)
  if ctx then
    add(ctx.LeaderIcon, "CENTER", por, "TOPLEFT", 8, -6, 16, 16)
    add(ctx.GuideIcon, "CENTER", por, "TOPLEFT", 8, -6, 19, 19)
    add(ctx.RoleIcon, "CENTER", por, "TOPRIGHT", -8, -6, 19, 19)
    add(ctx.RaidTargetIcon, "CENTER", por, "TOP", 0, -3)
    add(ctx.GroupIndicator, "TOP", por, "BOTTOM", 0, -(L.border + 18))
  end
  if main then
    -- the PvP crest sits fully outside the ring so it never covers the portrait
    add(main.PvpBackgroundIcon, "CENTER", por, "CENTER", -L.pvpOffset, 4, 40, 40)
    add(_G.PlayerPVPTimerText, "TOP", main.PvpBackgroundIcon, "BOTTOM", 0, 2)
    -- the hit-text keeps its parent: Blizzard's feedback code fades and hides it there
    if main.HitIndicator then add(main.HitIndicator.HitText, "CENTER", por, "CENTER", 0, 0, nil, nil, true) end
  end
end

local function TargetDecorations(u, add)
  local p, por = u.parts, u.portrait
  local ctx, main = p.ctx, p.main
  AddLevel(u, add, p.level)
  if ctx then
    AddLevel(u, add, ctx.HighLevelTexture, 16, 16)
    add(ctx.LeaderIcon, "CENTER", por, "TOPRIGHT", -8, -6, 16, 16)
    add(ctx.GuideIcon, "CENTER", por, "TOPRIGHT", -8, -6, 19, 19)
    add(ctx.QuestIcon, "CENTER", por, "TOPLEFT", 8, -6, 26, 26)
    add(ctx.RaidTargetIcon, "CENTER", por, "TOP", 0, -3)
    add(ctx.PvpBackgroundIcon, "CENTER", por, "CENTER", L.pvpOffset, 4, 40, 40)
    add(ctx.NumericalThreat, "TOPRIGHT", u.block, "BOTTOMRIGHT", 0, -(L.border + 3))
  end
  if main and main.HitIndicator then
    add(main.HitIndicator.HitText, "CENTER", por, "CENTER", 0, 0, nil, nil, true)
  end
end

-- focus keeps only the raid marker (everything else is hidden in FocusParts); it sits to the
-- left of the bars so it never collides with the cast bar above
local function FocusDecorations(u, add)
  local p = u.parts
  if p.ctx then add(p.ctx.RaidTargetIcon, "RIGHT", u.block, "LEFT", -(u.size.border + 2), 0) end
end

local function PetDecorations(u, add)
  local p, blk = u.parts, u.block
  add(p.happiness, "RIGHT", blk, "LEFT", -(u.size.border + 2), 0)
  add(p.hitText, "CENTER", blk, "CENTER", 0, 0, nil, nil, true)
end

-- the native ToT debuff icons keep working: they are taken out of the (now invisible)
-- native frame and placed beside the new bars
local function ToTDecorations(prefix)
  return function(u, add)
    local T = u.size.border
    for i = 1, 4 do
      local icon = _G[prefix .. "Debuff" .. i]
      add(icon, "TOPLEFT", u.block, "TOPRIGHT", T + 3 + ((i - 1) % 2) * 15, -(math.floor((i - 1) / 2) * 15))
    end
  end
end

-- Building one frame -------------------------------------------------------
-- spec: unit, native, mirrored, parts, decorations, size (MAIN/COMPACT),
--   portrait (px, nil = none), portraitPos {x, y}, blockPos {x, y} (offsets from the
--   portrait-side top corner), overlap (px the ring reaches over the bars),
--   level ("ring" | "corner" | nil), refresh {events}, unitRefresh {event = unit},
--   placement (native frame anchor), hideAuras, auraMaxWidth, elite (draw elite/rare art),
--   noText (leave native bar text hidden), nameInside (name centred in the health bar),
--   detach (native frame becomes an invisible click target), levelBase / strata (explicit stacking)

local function Create(spec)
  local unit, native, mirrored, parts, size = spec.unit, spec.native, spec.mirrored, spec.parts, spec.size
  local u = { unit = unit, native = native, mirrored = mirrored, parts = parts, spec = spec, size = size }
  local side = mirrored and "TOPRIGHT" or "TOPLEFT"
  local sign = mirrored and -1 or 1
  local T = size.border
  local blockH = size.hpHeight + size.powerHeight
  u.extent = spec.blockPos[2] + blockH + T -- how far below the frame's top the border reaches

  -- `detach`: the native frame is only kept as an invisible click target (alpha 0, no
  -- art of its own can leak) and my frame lives under UIParent, shown/hidden with it.
  local f = CreateFrame("Frame", nil, spec.detach and UIParent or native)
  if spec.strata then f:SetFrameStrata(spec.strata) end
  f:SetAllPoints(native)
  f:SetFrameLevel(spec.levelBase or (native:GetFrameLevel() + 2))
  u.frame = f

  -- Layering, bottom to top (all children of f, so the level is what orders them):
  --   bar block (f+1 and up)
  --   overlay        f+8   border, divider, bar text
  --   portraitFrame  f+9   black well, icon, ring: sits over the bar edge
  --   top            f+10  level, icons and the other adopted decorations
  local overlay = CreateFrame("Frame", nil, f)
  overlay:SetAllPoints(f)
  overlay:SetFrameLevel(f:GetFrameLevel() + 8)
  u.overlay = overlay

  local portraitFrame = CreateFrame("Frame", nil, f)
  portraitFrame:SetAllPoints(f)
  portraitFrame:SetFrameLevel(f:GetFrameLevel() + 9)

  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 10)
  u.top = top

  -- portrait (main frames and the target's ToT): class icon, or the unit's portrait for
  -- NPCs, in a black well with a soft ring
  local portrait
  if spec.portrait then
    local ps = spec.portrait
    local scale = ps / L.portrait
    portrait = portraitFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    portrait:SetSize(ps, ps)
    portrait:SetPoint(side, f, side, sign * spec.portraitPos[1], -spec.portraitPos[2])
    u.portrait = portrait

    local disc = portraitFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    disc:SetTexture(MEDIA .. "disc.tga")
    disc:SetSize(L.discSize * scale, L.discSize * scale)
    disc:SetPoint("CENTER", portrait, "CENTER")

    local mask = portraitFrame:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(portrait)
    portrait:AddMaskTexture(mask)

    local ring = portraitFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    ring:SetTexture(MEDIA .. "ring.tga")
    ring:SetSize(L.ringSize * scale, L.ringSize * scale)
    ring:SetPoint("CENTER", portrait, "CENTER")
  end

  -- bar block: health bar on top, power bar under it, one soft border around both
  local block = CreateFrame("Frame", nil, f)
  block:SetSize(size.barWidth, blockH)
  block:SetPoint(side, f, side, sign * spec.blockPos[1], -spec.blockPos[2])
  u.block = block

  local bg = block:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, .85)

  local hp = CreateFrame("StatusBar", nil, block)
  hp:SetSize(size.barWidth, size.hpHeight)
  hp:SetPoint("TOPLEFT")
  hp:SetStatusBarTexture(BarTexture())
  hp:SetMinMaxValues(0, 1)
  hp:SetValue(1)
  u.hp = hp

  local power = CreateFrame("StatusBar", nil, block)
  power:SetSize(size.barWidth, size.powerHeight)
  power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT")
  power:SetStatusBarTexture(BarTexture())
  power:SetMinMaxValues(0, 1)
  power:SetValue(1)
  u.power = power

  local divider = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
  divider:SetColorTexture(0, 0, 0, 1)
  divider:SetHeight(2)
  divider:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 1)
  divider:SetPoint("TOPRIGHT", power, "TOPRIGHT", 0, 1)

  -- druid mana bar: a third bar under the power bar, only while a druid is in a form that does
  -- not run on mana (cat, bear, dire bear). The block, and with it the border, grows downward
  -- while it shows; nothing else is anchored to the block's bottom edge on this frame.
  if spec.altPower then
    local alt = CreateFrame("StatusBar", nil, block)
    alt:SetSize(size.barWidth, size.powerHeight)
    alt:SetPoint("TOPLEFT", power, "BOTTOMLEFT")
    alt:SetStatusBarTexture(BarTexture())
    alt:SetMinMaxValues(0, 1)
    alt:SetValue(1)
    alt:Hide()
    u.alt = alt
    local altDivider = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    altDivider:SetColorTexture(0, 0, 0, 1)
    altDivider:SetHeight(2)
    altDivider:SetPoint("TOPLEFT", alt, "TOPLEFT", 0, 1)
    altDivider:SetPoint("TOPRIGHT", alt, "TOPRIGHT", 0, 1)
    altDivider:Hide()
    u.altDivider = altDivider
  end

  CreateBorder(overlay, block, T, L.borderInset)

  -- level badge: a miniature of the portrait (dark disc + soft ring). The pieces are
  -- regions of `top` drawn below the level text, so the number stays on top; Layout
  -- shows them only while a level is shown.
  if spec.level then
    if spec.level == "ring" then
      -- 45 degrees round the portrait ring from the bottom, on the outer side
      u.levelPos = { "CENTER", portrait, "CENTER", (mirrored and 1 or -1) * L.levelOffset, -L.levelOffset }
    else
      u.levelPos = { "CENTER", block, "TOPLEFT", 0, 0 }
    end
    local disc = top:CreateTexture(nil, "ARTWORK", nil, 1)
    disc:SetTexture(MEDIA .. "disc.tga")
    disc:SetSize(L.levelBadge * L.discSize / L.portrait, L.levelBadge * L.discSize / L.portrait)
    disc:SetPoint("CENTER", u.levelPos[2], u.levelPos[3], u.levelPos[4], u.levelPos[5])
    disc:SetAlpha(.92)
    local ring = top:CreateTexture(nil, "ARTWORK", nil, 2)
    ring:SetTexture(MEDIA .. "ring.tga")
    ring:SetSize(L.levelBadge * L.ringSize / L.portrait, L.levelBadge * L.ringSize / L.portrait)
    ring:SetPoint("CENTER", disc, "CENTER")
    u.badge = { disc, ring }
  end

  -- elite / rare portrait art: above the portrait and ring, below the level badge and icons
  if spec.elite and spec.portrait then
    local art = top:CreateTexture(nil, "ARTWORK", nil, 0)
    art:Hide()
    u.eliteArt = art
  end

  -- incoming heals extend the health fill
  if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
    local calc = CreateUnitHealPredictionCalculator()
    if calc and calc.SetToDefaults then calc:SetToDefaults() end
    -- begins at the live end of the health fill and spans the rest of the bar,
    -- so no arithmetic on protected health values is needed
    local predict = CreateFrame("StatusBar", nil, hp)
    predict:SetStatusBarTexture(BarTexture())
    predict:SetStatusBarColor(.25, 1, .35, .7)
    predict:SetFrameLevel(hp:GetFrameLevel() + 2)
    predict:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
    predict:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT")
    predict:Hide()
    u.healCalc, u.healBar = calc, predict
  end

  -- adopt the native name/level/text/icons so they live on top of my frame
  local function adopt(region, parent)
    if region and region.SetParent then region:SetParent(parent or overlay) end
  end

  u.texts = {}
  local function text(fs, point, rel, x)
    if not fs then return end
    adopt(fs)
    u.texts[#u.texts + 1] = { fs = fs, point = point, rel = rel, x = x }
  end
  local hpt, mpt = parts.hp, parts.mp
  -- Frames with ownText (player, target, pet) draw their numbers through Text.lua; the native
  -- bar text stays under the hidden bars apart from the Dead / Unconscious labels. noText
  -- frames (focus, target of target) show no numbers at all.
  if spec.ownText then
    text(hpt.dead, "CENTER", hp, 0)
    text(hpt.unconscious, "CENTER", hp, 0)
    NF.Text.Create(u)
  elseif not spec.noText then
    -- the side facing the portrait gets extra padding so numbers clear the overlapping ring
    local near = L.textPad + (spec.portrait and spec.overlap or 0)
    local leftPad = mirrored and L.textPad or near
    local rightPad = mirrored and near or L.textPad
    text(hpt.center, "CENTER", hp, 0)
    text(hpt.left, "LEFT", hp, leftPad)
    text(hpt.right, "RIGHT", hp, -rightPad)
    text(hpt.dead, "CENTER", hp, 0)
    text(hpt.unconscious, "CENTER", hp, 0)
    text(mpt.center, "CENTER", power, 0)
    text(mpt.left, "LEFT", power, leftPad)
    text(mpt.right, "RIGHT", power, -rightPad)
  end

  adopt(parts.name)

  u.deco = {}
  spec.decorations(u, function(region, point, rel, relPoint, x, y, w, h, keepParent)
    if not region or not rel then return end
    if not keepParent then adopt(region, top) end
    if region.SetDrawLayer then region:SetDrawLayer("OVERLAY", 7) end
    u.deco[#u.deco + 1] = { region = region, point = point, rel = rel, relPoint = relPoint, x = x, y = y, w = w, h = h }
  end)

  -- hide Blizzard's art and bars last, after the pieces we keep have been moved out
  NF.SuppressAll(unpack(parts.suppress))

  if spec.detach then
    f:SetShown(native:IsShown())
    native:HookScript("OnShow", function() f:Show() end)
    native:HookScript("OnHide", function() f:Hide() end)
    NF.Suppress(native)
    -- the Edit Mode selection box must stay visible so the frame can still be moved there
    local selection = native.Selection
    if selection and selection.SetIgnoreParentAlpha then selection:SetIgnoreParentAlpha(true) end
  end

  return u
end

-- Layout (idempotent; Blizzard re-anchors things during its own updates) -----

-- The target-of-target frames hang off their parent frame: the native frame is
-- moved (out of combat only) so its click area follows the new bars.
local function PlaceNative(u)
  local p = u.spec.placement
  if not p then return end
  if InCombat() then u.placePending = true return end
  u.placePending = false
  u.native:ClearAllPoints()
  u.native:SetPoint("TOPLEFT", p.parent, "TOPLEFT", p.x, -p.y)
  -- the invisible click target matches the visible frame
  if p.width then u.native:SetSize(p.width, p.height) end
end

-- The name and level float over the world, so they get an outline. Blizzard
-- re-applies its own font during updates, so this runs from Layout too.
local function Outline(fs)
  if not fs or not fs.GetFont then return end
  local file, size, flags = fs:GetFont()
  if file and not (flags and flags:find("OUTLINE")) then fs:SetFont(file, size, "OUTLINE") end
end

-- Elite / rare art: the client's own portrait-decoration atlases, drawn by me (the
-- native texture stays hidden) so strata and position are under my control. Atlas
-- and offsets come from GetBossPortraitFrameData when the client has it, else from
-- this table. Offsets are measured from the native portrait centre, which sits
-- 55px in from the native frame's right edge and 48px down.
local ELITE_ART = {
  elite = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", 0, 1 },
  worldboss = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", 11, -4 },
  rare = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", 8, -7 },
  rareelite = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", 8, -7 },
}
local NATIVE_PORTRAIT = { 55, 48 }

-- Classic style (the default): the original dragon overlays (media/dragon, copied from
-- DarkMode). Each is a 256x128 sheet laid out for the classic target frame, whose
-- centre sits 54px left of and 20px below the portrait centre.
local CLASSIC_DRAGON = {
  elite = "UI-TargetingFrame-Elite_Dragon",
  worldboss = "UI-TargetingFrame-Elite_Dragon",
  rare = "UI-TargetingFrame-Rare_Dragon",
  rareelite = "UI-TargetingFrame-Rare-Elite_Dragon",
}

-- Returns true if the classic dragon for `classification` is now showing.
local function ShowClassicElite(u, classification)
  local file = CLASSIC_DRAGON[classification]
  if not file then return false end
  local art = u.eliteArt
  local key = "classic:" .. classification
  if u.eliteKey ~= key then
    art:SetTexCoord(0, 1, 0, 1)
    if art:SetTexture(MEDIA .. "dragon\\" .. file) == false then return false end
    art:SetSize(256, 128)
    art:ClearAllPoints()
    art:SetPoint("CENTER", u.portrait, "CENTER", -54, -20)
    u.eliteKey = key
  end
  art:Show()
  return true
end

local function UpdateElite(u)
  local art = u.eliteArt
  if not art then return end
  local classification = UnitClassification and UnitClassification(u.unit)
  local data = NF.Readable(classification) and type(classification) == "string" and ELITE_ART[classification]
  if not data or not UnitExists(u.unit) then
    art:Hide()
    u.eliteKey = nil
    return
  end
  if ((NF.db and NF.db.eliteStyle) or "classic") == "classic" and ShowClassicElite(u, classification) then return end
  local atlas, x, y = data[1], data[2], data[3]
  if GetBossPortraitFrameData then
    local ok, native, nx, ny = pcall(GetBossPortraitFrameData, u.unit, classification)
    if ok and NF.Readable(native) and type(native) == "string" and NF.Readable(nx) and NF.Readable(ny)
        and type(nx) == "number" and type(ny) == "number" then
      atlas, x, y = native, nx, ny
    end
  end
  if u.eliteKey ~= atlas or u.eliteX ~= x or u.eliteY ~= y then
    local ok, result = pcall(art.SetAtlas, art, atlas, true)
    if not ok or result == false then
      art:Hide()
      u.eliteKey = nil
      return
    end
    local ps, pos = u.spec.portrait, u.spec.portraitPos
    -- shift from the native portrait centre to mine
    local dx = -(pos[1] + ps / 2) + NATIVE_PORTRAIT[1]
    local dy = -(pos[2] + ps / 2) + NATIVE_PORTRAIT[2]
    art:ClearAllPoints()
    art:SetPoint("TOPRIGHT", u.frame, "TOPRIGHT", x + dx, y + dy)
    u.eliteKey, u.eliteX, u.eliteY = atlas, x, y
  end
  art:Show()
end

-- Level number: outlined and a couple of points smaller than Blizzard's so it sits
-- inside the badge. Blizzard resets the font from time to time, so the size applied
-- last is remembered and re-applied only when something else changed it.
local function StyleLevel(fs)
  if not fs or not fs.GetFont then return end
  local file, size, flags = fs:GetFont()
  if not file or type(size) ~= "number" then return end
  if fs.nfSize and size == fs.nfSize and flags and flags:find("OUTLINE") then return end
  local wanted = math.max(size - L.levelFontDrop, 6)
  fs:SetFont(file, wanted, "OUTLINE")
  fs.nfSize = wanted
end

local function Layout(u)
  local T = u.size.border
  local p = u.parts
  if p.name then
    if u.spec.nameInside then
      -- name sits inside the health bar (focus, target of target)
      Place(p.name, "CENTER", u.hp, "CENTER", 0, 0)
      p.name:SetWidth(u.size.barWidth - 8)
    else
      Place(p.name, "BOTTOM", u.block, "TOP", 0, T + L.namePad)
      p.name:SetWidth(u.size.barWidth + 2 * T + 24)
    end
    p.name:SetJustifyH("CENTER")
    if p.name.SetWordWrap then p.name:SetWordWrap(false) end
    Outline(p.name)
  end
  StyleLevel(p.level)
  UpdateElite(u)
  if u.badge then
    local ctx = p.ctx
    local skull = ctx and ctx.HighLevelTexture
    local hasLevel = (p.level and p.level:IsShown()) or (skull and skull:IsShown())
    for _, piece in ipairs(u.badge) do piece:SetShown(hasLevel and true or false) end
  end
  for _, t in ipairs(u.texts) do Place(t.fs, t.point, t.rel, t.point, t.x, 0) end
  for _, d in ipairs(u.deco) do
    Place(d.region, d.point, d.rel, d.relPoint, d.x, d.y)
    if d.w then d.region:SetSize(d.w, d.h) end
  end
  PlaceNative(u)
end

-- Auras stay native; they are re-anchored under the bars (and under the ToT frame
-- while it is showing). Focus shows none: its container is pinned to alpha 0.
local function AnchorAuras(u)
  if not NF.active or not u or not u.ready then return end
  local container = u.native.GetAuraContainer and u.native:GetAuraContainer()
  if not container then return end
  if u.spec.hideAuras then NF.Suppress(container) return end
  if InCombat() then u.auraPending = true return end
  u.auraPending = false
  Place(container, "TOPLEFT", u.block, "BOTTOMLEFT", 0, -(u.size.border + 4))
  -- keep the rows narrower than the space left of the target-of-target icon
  if u.spec.auraMaxWidth and container.SetFlowLayoutMaximumLineSize then
    pcall(container.SetFlowLayoutMaximumLineSize, container, u.spec.auraMaxWidth)
  end
end

-- Updates -----------------------------------------------------------------

local function UpdateHealthColor(u)
  if not UnitExists(u.unit) then return end
  u.hp:SetStatusBarColor(NF.HealthColor(u.unit))
end

local function UpdateHealPrediction(u)
  local bar, calc = u.healBar, u.healCalc
  if not bar then return end
  if not calc or not UnitExists(u.unit) then bar:Hide() return end
  -- the calculator's outputs are protected in instances: they go straight into
  -- the bar, never through comparisons or arithmetic
  local ok, updated = pcall(function()
    UnitGetDetailedHealPrediction(u.unit, "player", calc)
    if calc.GetMaximumIncomingHeals and calc.GetTotalIncomingHeals then
      bar:SetMinMaxValues(0, calc:GetMaximumIncomingHeals())
      bar:SetValue(calc:GetTotalIncomingHeals())
    elseif calc.GetMaximumHealth and calc.GetIncomingHeals then
      bar:SetMinMaxValues(0, calc:GetMaximumHealth())
      bar:SetValue(calc:GetIncomingHeals())
    else
      return false
    end
    return true
  end)
  -- a failed calculator must never leave the previous unit's heals on screen
  bar:SetShown(ok and updated == true)
end

local function UpdateHealth(u)
  local unit = u.unit
  if not UnitExists(unit) then return end
  -- values go straight into the bar: in instances they can be protected
  u.hp:SetMinMaxValues(0, UnitHealthMax(unit))
  u.hp:SetValue(UnitHealth(unit))
  UpdateHealPrediction(u)
  if u.slots then NF.Text.UpdateHealth(u) end
end

-- Mana (or other resource) the current cast will use, taken from the spell's
-- cost data. Only costs in the power type the bar is showing are drawn.
local function CastCost(spellID)
  if not NF.Readable(spellID) or type(spellID) ~= "number" then return nil end
  local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  if not get then return nil end
  local ok, costs = pcall(get, spellID)
  if not ok or type(costs) ~= "table" then return nil end
  local powerType = UnitPowerType("player")
  local matchType = NF.Readable(powerType)
  for _, entry in ipairs(costs) do
    if type(entry) == "table" and NF.Readable(entry.cost) and type(entry.cost) == "number"
        and entry.cost > 0 and (not matchType or entry.type == powerType) then
      return entry.cost
    end
  end
end

local function UpdateCost(u)
  local gauge = u.costGauge
  if not gauge then return end
  local cost = u.casting and CastCost(u.castSpell)
  if not cost then gauge:Hide() return end
  -- a reverse-fill bar hung off the right end of the power fill: the cost
  -- segment is (cost / max) of the bar width, no arithmetic on protected power
  gauge:SetMinMaxValues(0, UnitPowerMax("player"))
  gauge:SetValue(cost)
  gauge:Show()
end

-- Druid mana bar -------------------------------------------------------------
-- Shown while a druid's main power is not mana (cat form: energy, bear / dire bear: rage).

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local isDruid
local function AltWanted()
  if isDruid == nil then
    local token = NF.ClassToken("player")
    if token == nil then return false end -- not known yet: ask again next time
    isDruid = NF.Readable(token) and token == "DRUID"
  end
  if not isDruid then return false end
  local powerType = UnitPowerType("player")
  return NF.Readable(powerType) and powerType ~= MANA
end

local function SetAltShown(u, shown)
  u.altShown = shown
  u.alt:SetShown(shown)
  u.altDivider:SetShown(shown)
  u.block:SetHeight(u.size.hpHeight + u.size.powerHeight + (shown and u.size.powerHeight or 0))
  if u.slots and u.slots.alt then
    for _, fs in pairs(u.slots.alt) do fs:SetShown(shown) end
  end
end

local function UpdateAlt(u)
  if not u.alt then return end
  local wanted = AltWanted()
  if wanted ~= (u.altShown or false) then SetAltShown(u, wanted) end
  if not wanted then return end
  local c = PowerBarColor and (PowerBarColor.MANA or PowerBarColor[MANA])
  if c then u.alt:SetStatusBarColor(c.r, c.g, c.b) else u.alt:SetStatusBarColor(0, 0, 1) end
  -- values go straight into the bar: in instances they can be protected
  u.alt:SetMinMaxValues(0, UnitPowerMax("player", MANA))
  u.alt:SetValue(UnitPower("player", MANA))
  if u.slots then NF.Text.UpdateAlt(u) end
end

-- Value only: runs on every UNIT_POWER_FREQUENT, so it stays cheap.
local function UpdatePowerValue(u)
  local unit = u.unit
  if not UnitExists(unit) then return end
  u.power:SetMinMaxValues(0, UnitPowerMax(unit))
  u.power:SetValue(UnitPower(unit))
  UpdateCost(u)
  if u.slots then NF.Text.UpdatePower(u) end
  UpdateAlt(u)
end

local function UpdatePower(u)
  local unit = u.unit
  if not UnitExists(unit) then return end
  u.power:SetStatusBarColor(NF.PowerColor(unit))
  UpdatePowerValue(u)
end

local function UpdatePortrait(u)
  if not u.portrait then return end
  local unit = u.unit
  if not UnitExists(unit) then return end
  if (unit == "player" or NF.Bool(UnitIsPlayer, unit)) and NF.SetClassIcon(u.portrait, unit) then return end
  SetPortraitTexture(u.portrait, unit)
  u.portrait:SetTexCoord(0, 1, 0, 1)
end

local function UpdateStatus(u)
  if not u or not u.rest then return end
  local combat = NF.Bool(UnitAffectingCombat, "player")
  local resting = IsResting() and true or false
  u.rest:SetShown(resting and not combat)
  u.attack:SetShown(combat)
end

local function FullUpdate(u)
  if not u.ready or not UnitExists(u.unit) then return end
  UpdatePortrait(u)
  UpdateHealthColor(u)
  UpdateHealth(u)
  UpdatePower(u)
  Layout(u)
  UpdateStatus(u)
end

local function OnEvent(u, event, ...)
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    UpdateHealth(u)
  elseif event == "UNIT_HEAL_PREDICTION" then
    UpdateHealPrediction(u)
  elseif event == "UNIT_POWER_FREQUENT" then
    UpdatePowerValue(u)
  elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
    UpdatePower(u)
  elseif event == "UNIT_SPELLCAST_START" then
    local _, castGUID, spellID = ...
    u.casting, u.castGUID, u.castSpell = true, castGUID, spellID
    UpdateCost(u)
  elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    local _, castGUID = ...
    -- a failed attempt at some other spell must not clear the cast in progress
    if NF.Readable(castGUID) and NF.Readable(u.castGUID) and u.castGUID ~= nil and castGUID ~= u.castGUID then return end
    u.casting, u.castGUID, u.castSpell = false, nil, nil
    UpdateCost(u)
  elseif event == "UNIT_FACTION" then
    UpdateHealthColor(u)
  elseif event == "UNIT_PORTRAIT_UPDATE" or event == "PORTRAITS_UPDATED" then
    UpdatePortrait(u)
  elseif event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_REGEN_DISABLED" then
    UpdateStatus(u)
  elseif event == "PLAYER_REGEN_ENABLED" then
    UpdateStatus(u)
    if u.auraPending then AnchorAuras(u) end
    if u.placePending then PlaceNative(u) end
  else -- PLAYER_ENTERING_WORLD and each frame's own refresh events (target/focus change, UNIT_TARGET, UNIT_PET)
    FullUpdate(u)
  end
end

local function WireEvents(u)
  local f, unit = u.frame, u.unit
  for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_POWER_UPDATE",
      "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_FACTION", "UNIT_PORTRAIT_UPDATE" }) do
    f:RegisterUnitEvent(event, unit)
  end
  -- continuous regen (energy, mana ticks) only arrives on the FREQUENT event;
  -- UNIT_POWER_UPDATE alone makes the bar move in lumps
  pcall(f.RegisterUnitEvent, f, "UNIT_POWER_FREQUENT", unit)
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PORTRAITS_UPDATED", "PLAYER_REGEN_ENABLED" }) do
    f:RegisterEvent(event)
  end
  for _, event in ipairs(u.spec.refresh or {}) do f:RegisterEvent(event) end
  for event, eventUnit in pairs(u.spec.unitRefresh or {}) do f:RegisterUnitEvent(event, eventUnit) end
  if unit == "player" then
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED" }) do
      f:RegisterUnitEvent(event, "player")
    end
  end
  f:SetScript("OnEvent", function(_, event, ...) OnEvent(u, event, ...) end)
  f:SetScript("OnShow", function() FullUpdate(u) end)
end

-- Rest / combat state icon (player only) ------------------------------------

local function CreateStatusIcons(u)
  -- bottom centre of the ring: the level number owns the lower-left
  local rest = u.top:CreateTexture(nil, "OVERLAY", nil, 7)
  rest:SetSize(28, 28)
  rest:SetTexture(STATE_ICON)
  rest:SetTexCoord(0, .5, 0, .421875)
  rest:SetPoint("CENTER", u.portrait, "BOTTOM", 0, -2)
  local attack = u.top:CreateTexture(nil, "OVERLAY", nil, 7)
  attack:SetSize(28, 28)
  attack:SetTexture(STATE_ICON)
  attack:SetTexCoord(.5, 1, 0, .484375)
  attack:SetPoint("CENTER", u.portrait, "BOTTOM", 0, -2)
  u.rest, u.attack = rest, attack
end

-- Predicted resource use for the cast in progress (player only) ---------------

local function CreateCostPrediction(u)
  -- clip to the power bar so a cost larger than the current power can't spill out
  local clip = CreateFrame("Frame", nil, u.block)
  clip:SetAllPoints(u.power)
  clip:SetClipsChildren(true)
  clip:SetFrameLevel(u.power:GetFrameLevel() + 2)
  local gauge = CreateFrame("StatusBar", nil, clip)
  gauge:SetSize(u.size.barWidth, u.size.powerHeight)
  gauge:SetPoint("TOPRIGHT", u.power:GetStatusBarTexture(), "TOPRIGHT")
  gauge:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  gauge:SetStatusBarColor(1, 1, 1, .45)
  gauge:SetReverseFill(true)
  gauge:Hide()
  u.costGauge = gauge
end

-- Setup --------------------------------------------------------------------

local function InstallHooks()
  local player, target, focus = units.player, units.target, units.focus
  local function relayout(u) return function() if NF.active and u and u.ready then Layout(u) end end end

  for _, name in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateLevel",
      "PlayerFrame_UpdatePartyLeader", "PlayerFrame_UpdatePlayerNameTextAnchor",
      "PlayerFrame_UpdatePvPStatus", "PlayerFrame_UpdateRolesAssigned" }) do
    HookGlobal(name, relayout(player))
  end
  HookGlobal("PlayerFrame_UpdateStatus", function()
    if NF.active and player.ready then Layout(player) UpdateStatus(player) end
  end)

  for _, pair in ipairs({ { TargetFrame, target, units.tot }, { FocusFrame, focus } }) do
    local native, u, tot = pair[1], pair[2], pair[3]
    if u then
      for _, name in ipairs({ "CheckClassification", "CheckFaction", "CheckLevel" }) do
        HookMethod(native, name, function()
          relayout(u)()
          if tot then relayout(tot)() end
        end)
      end
      HookMethod(native, "AnchorAuraContainer", function() AnchorAuras(u) end)
    end
  end

end

-- Every native glow / flash (threat, combat, selection) plus any leftover native portrait or
-- boss/elite art is pinned hidden. Found by name: any child, region or field whose key or
-- atlas contains one of `words`. Our own frames are skipped.
local function Sweep(native, skip, words)
  local seen = {}
  local function matches(text)
    local t = text:lower()
    for _, word in ipairs(words) do
      if t:find(word, 1, true) then return true end
    end
    return false
  end
  local function check(key, region)
    if type(region) ~= "table" or skip[region] or type(region.SetAlpha) ~= "function" then return end
    if type(key) == "string" and matches(key) then NF.Banish(region) return end
    if region.GetObjectType and region:GetObjectType() == "Texture" and region.GetAtlas then
      local ok, atlas = pcall(region.GetAtlas, region)
      if ok and NF.Readable(atlas) and type(atlas) == "string" and matches(atlas) then NF.Banish(region) end
    end
  end
  local function walk(frame, depth)
    if not frame or seen[frame] or skip[frame] or depth > 5 then return end
    seen[frame] = true
    if frame.IsForbidden and frame:IsForbidden() then return end
    for key, value in pairs(frame) do check(key, value) end
    if frame.GetRegions then
      for _, region in ipairs({ frame:GetRegions() }) do check(nil, region) end
    end
    if frame.GetChildren then
      for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
    end
  end
  walk(native, 0)
end

-- Geometry that depends on the adjustable bar sizes ------------------------------------------
-- The tables the frame specs point at are updated in place, so a resize reaches every frame.

local geo = {
  W = 232,
  mainBlockPos = { L.barInset, L.barTop },
  totPortraitPos = { 3, 4 },
  totBlockPos = { 0, 0 },
  totPlacement = {},
}

-- copies the saved sizes into the shared MAIN / COMPACT tables
local function LoadSizes()
  local sizes = NF.db.sizes
  for _, pair in ipairs({ { MAIN, sizes.main }, { COMPACT, sizes.compact } }) do
    local shared, saved = pair[1], pair[2]
    shared.barWidth, shared.hpHeight, shared.powerHeight = saved.barWidth, saved.hpHeight, saved.powerHeight
  end
end

-- Target-of-target: its icon touches the target's icon at L.totAngle degrees to the lower left
-- (ring against ring), then the whole frame is nudged L.totShiftX right and dropped until the
-- outer top edge of its border sits L.totGap below the bottom of the target icon's ring. Its
-- bars run right from the icon, level with it. The ToT stack sits below the target's in the
-- frame levels, so any overlap tucks under the target.
local function ComputeGeometry()
  local W = geo.W
  local mainBlockH = MAIN.hpHeight + MAIN.powerHeight
  -- the main bars stay vertically centred on the portrait
  geo.mainBlockPos[2] = math.floor(L.portraitTop + L.portrait / 2 - mainBlockH / 2 + .5)

  local totPortrait = 34
  local totRing = 4 * totPortrait / L.portrait                      -- ring thickness past the icon
  local targetCx = W - (L.portraitInset + L.portrait / 2)           -- target icon centre, from the left
  local targetCy = L.portraitTop + L.portrait / 2                   -- ... and from the top
  local touch = (L.portrait / 2 + 4) + (totPortrait / 2 + totRing)  -- ring radius + ring radius
  local totIconX = targetCx - touch * math.sin(math.rad(L.totAngle)) - totPortrait / 2
  local pos = geo.totPortraitPos
  local totBlockH = COMPACT.hpHeight + COMPACT.powerHeight
  geo.totPortrait, geo.totRing = totPortrait, totRing
  geo.totBlockPos[1] = pos[1] + totPortrait + totRing - 3           -- 3px overlap
  geo.totBlockPos[2] = pos[2] + totPortrait / 2 - totBlockH / 2     -- bars level with the icon
  local ringBottom = targetCy + L.portrait / 2 + 4
  local totBarTop = ringBottom + L.totGap + (COMPACT.border - L.borderInset)
  local p = geo.totPlacement
  p.x = totIconX - pos[1] + L.totShiftX
  p.y = totBarTop - geo.totBlockPos[2]
  p.width = geo.totBlockPos[1] + COMPACT.barWidth + COMPACT.border
  p.height = math.max(pos[2] + totPortrait + totRing, geo.totBlockPos[2] + totBlockH + COMPACT.border)
end

-- Re-applies the current sizes to one frame.
local function Resize(u)
  local size, spec = u.size, u.spec
  local blockH = size.hpHeight + size.powerHeight
  local side = u.mirrored and "TOPRIGHT" or "TOPLEFT"
  local sign = u.mirrored and -1 or 1
  -- the druid mana bar (when showing) adds one more power-bar height; the block's top stays put
  u.block:SetSize(size.barWidth, blockH + (u.altShown and size.powerHeight or 0))
  u.block:ClearAllPoints()
  u.block:SetPoint(side, u.frame, side, sign * spec.blockPos[1], -spec.blockPos[2])
  u.hp:SetSize(size.barWidth, size.hpHeight)
  u.power:SetSize(size.barWidth, size.powerHeight)
  if u.alt then u.alt:SetSize(size.barWidth, size.powerHeight) end
  if u.costGauge then u.costGauge:SetSize(size.barWidth, size.powerHeight) end
  u.extent = spec.blockPos[2] + blockH + size.border
  if u.slots then NF.Text.Resize(u) end
end

-- Live-apply entry points used by the options panel -------------------------------------------

function NF.ApplySizes()
  if not NF.active then return end
  LoadSizes()
  ComputeGeometry()
  for _, u in pairs(units) do Resize(u) end
  for _, u in pairs(units) do Layout(u) end
  if units.target then AnchorAuras(units.target) end
  if NF.CastBars then NF.CastBars.Resize() end
end

function NF.ApplyBarTexture()
  if not NF.active then return end
  local texture = BarTexture()
  for _, u in pairs(units) do
    u.hp:SetStatusBarTexture(texture)
    u.power:SetStatusBarTexture(texture)
    if u.alt then u.alt:SetStatusBarTexture(texture) end
    if u.healBar then u.healBar:SetStatusBarTexture(texture) end
  end
  if NF.CastBars then NF.CastBars.ApplyTexture() end
  -- a new texture can reset the fill colour
  for _, u in pairs(units) do FullUpdate(u) end
end

-- class icon set and elite/rare art style
function NF.ApplyIcons()
  if not NF.active then return end
  for _, u in pairs(units) do
    UpdatePortrait(u)
    if u.eliteArt then
      u.eliteKey = nil
      UpdateElite(u)
    end
  end
end

function NF.ApplyText()
  if not NF.active then return end
  for _, u in pairs(units) do
    if u.slots then NF.Text.Update(u) end
  end
end

-- bar text sizes (options sliders)
function NF.ApplyFonts()
  if not NF.active then return end
  for _, u in pairs(units) do
    if u.slots then NF.Text.Resize(u) end
  end
end

function NF.ApplyAll()
  if not NF.active then return end
  NF.ApplySizes()
  NF.ApplyBarTexture()
  NF.ApplyIcons()
  NF.ApplyText()
  if NF.CastBars then NF.CastBars.Apply() end
end

-- Setup --------------------------------------------------------------------

local function Setup()
  if units.player or not NF.db then return end
  local conflict = NF.FindConflict()
  if conflict then
    print("|cffffd200norabu_frames:|r " .. conflict .. " is enabled, so norabu_frames is standing down. Disable it and /reload.")
    return
  end
  if not (PlayerFrame and TargetFrame) then
    print("|cffffd200norabu_frames:|r could not find the native player/target frames, standing down.")
    return
  end
  NF.active = true

  local function width(frame)
    local w = frame:GetWidth()
    return (NF.Readable(w) and type(w) == "number" and w > 0) and w or 232
  end

  local tfLevel, tfStrata = TargetFrame:GetFrameLevel(), TargetFrame:GetFrameStrata()
  geo.W = width(TargetFrame)
  geo.totPlacement.parent = TargetFrame
  LoadSizes()
  ComputeGeometry()

  -- player and target: portrait + thick merged bars
  units.player = Create({
    unit = "player", native = PlayerFrame, mirrored = false, parts = PlayerParts(), decorations = PlayerDecorations,
    size = MAIN, portrait = L.portrait, portraitPos = { L.portraitInset, L.portraitTop },
    blockPos = geo.mainBlockPos, overlap = L.portraitOverlap, level = "ring", ownText = true,
    altPower = true, refresh = { "UPDATE_SHAPESHIFT_FORM" },
  })
  CreateStatusIcons(units.player)
  -- the native alternate power bar (the druid's mana in forms) is replaced by the bar above
  if _G.AlternatePowerBar then NF.HideFrame(_G.AlternatePowerBar) end
  CreateCostPrediction(units.player)

  units.target = Create({
    unit = "target", native = TargetFrame, mirrored = true, parts = TargetParts(TargetFrame), decorations = TargetDecorations,
    size = MAIN, portrait = L.portrait, portraitPos = { L.portraitInset, L.portraitTop },
    blockPos = geo.mainBlockPos, overlap = L.portraitOverlap, level = "ring", ownText = true,
    refresh = { "PLAYER_TARGET_CHANGED" }, unitRefresh = { UNIT_CLASSIFICATION_CHANGED = "target" }, elite = true,
    -- no auraMaxWidth: limiting the native aura container's row width made the target's
    -- buffs/debuffs disappear (twice), so the rows are left alone
    levelBase = tfLevel + 12,
  })

  -- the target's ToT: class icon / portrait + compact bars, name inside the health bar, no numbers
  local totParts = ToTParts(TargetFrame.totFrame)
  if totParts then
    units.tot = Create({
      unit = "targettarget", native = TargetFrame.totFrame, mirrored = false, parts = totParts,
      decorations = ToTDecorations("TargetFrameToT"), size = COMPACT, portrait = geo.totPortrait,
      portraitPos = geo.totPortraitPos, blockPos = geo.totBlockPos, overlap = 3,
      noText = true, nameInside = true, detach = true, levelBase = tfLevel + 1, strata = tfStrata,
      refresh = { "PLAYER_TARGET_CHANGED" }, unitRefresh = { UNIT_TARGET = "target" },
      placement = geo.totPlacement,
    })
  end

  -- focus: no portrait, compact bars, no auras, name (inside the bar) + bars + raid marker only
  if FocusFrame then
    -- detached: the native focus frame is only an invisible click target (alpha 0), so no
    -- native glow, strip or art can show whatever Blizzard does to it
    units.focus = Create({
      unit = "focus", native = FocusFrame, mirrored = false, parts = FocusParts(FocusFrame), decorations = FocusDecorations,
      size = COMPACT, blockPos = { 12, 31 }, hideAuras = true, noText = true, nameInside = true,
      detach = true, strata = FocusFrame:GetFrameStrata(),
      refresh = { "PLAYER_FOCUS_CHANGED" },
    })
    -- the focus's target-of-target is not wanted: its native frame is pinned hidden
    local focusTot = FocusFrame.totFrame
    if focusTot then
      NF.Suppress(focusTot)
      if not InCombat() then pcall(focusTot.EnableMouse, focusTot, false) end
    end
  end

  -- pet: no portrait, compact bars, cast bar hidden
  local petParts = PetParts()
  if petParts then
    units.pet = Create({
      unit = "pet", native = PetFrame, mirrored = false, parts = petParts, decorations = PetDecorations,
      size = COMPACT, blockPos = { 10, 22 }, ownText = true, unitRefresh = { UNIT_PET = "player" },
    })
  end

  -- the pet cast bar is hidden altogether
  if _G.PetCastingBarFrame then NF.HideFrame(_G.PetCastingBarFrame) end

  InstallHooks()
  for _, u in pairs(units) do
    WireEvents(u)
    u.ready = true
  end
  AnchorAuras(units.target)
  AnchorAuras(units.focus)

  -- hide every native glow/flash, and any native portrait or boss art that is still showing,
  -- inside the frames' art/content areas (never our own frames, never the aura containers)
  local skip = {}
  for _, u in pairs(units) do skip[u.frame] = true end
  for _, native in ipairs(Collect(TargetFrame, FocusFrame)) do
    local container = native.GetAuraContainer and native:GetAuraContainer()
    if container then skip[container] = true end
  end
  -- the focus has no auras to protect, so its whole native tree is swept
  local roots = Collect(
    PlayerFrame.PlayerFrameContent, PlayerFrame.PlayerFrameContainer,
    TargetFrame.TargetFrameContent, TargetFrame.TargetFrameContainer,
    FocusFrame, _G.PetFrame
  )
  local words = { "glow", "flash", "portrait", "boss", "reputation" }
  for _, root in ipairs(roots) do Sweep(root, skip, words) end

  -- target and focus cast bars (restyled, stacked against the name/bars)
  if NF.CastBars then NF.CastBars.Setup(units) end

  for _, u in pairs(units) do FullUpdate(u) end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Setup)
