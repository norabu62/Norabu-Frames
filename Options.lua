-- Options panel (Esc > Options > AddOns > norabu_frames). Opened with /nf or /norabu.
-- Plain widgets on a scrolling canvas; every change is saved and applied live, except the
-- master enable switch, which needs a reload.
local ADDON, NF = ...

local Options = {}
NF.Options = Options

local widgets = {}
local function RefreshAll()
  for _, w in ipairs(widgets) do w.Refresh() end
end
Options.RefreshAll = RefreshAll

-- Small widget kit --------------------------------------------------------

local function Label(parent, x, y, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function Header(parent, y, text)
  local fs = Label(parent, 10, y, text, "GameFontNormalLarge")
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(.5, .5, .5, .5)
  line:SetPoint("TOPLEFT", 10, y - 24)
  line:SetSize(570, 1)
  return fs
end

local function Button(parent, x, y, width, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b:SetSize(width, 24)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Checkbox(parent, x, y, text, get, set)
  local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b:SetSize(26, 26)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
  fs:SetText(text)
  b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  widgets[#widgets + 1] = { Refresh = function() b:SetChecked(get()) end }
  return b
end

local function Slider(parent, x, y, text, min, max, get, set)
  Label(parent, x, y, text, "GameFontNormalSmall")
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", x, y - 22)
  s:SetWidth(200)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  if s.Low then s.Low:SetText(min) end
  if s.High then s.High:SetText(max) end
  if s.Text then s.Text:SetText("") end
  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", s, "RIGHT", 10, 0)
  local refreshing = false
  s:SetScript("OnValueChanged", function(_, v)
    if refreshing then return end
    v = math.floor(v + .5)
    value:SetText(v)
    set(v)
  end)
  widgets[#widgets + 1] = {
    Refresh = function()
      refreshing = true
      local v = get()
      s:SetValue(v)
      value:SetText(v)
      refreshing = false
    end,
  }
  return s
end

-- One shared pop-up list; a transparent full-screen button behind it closes it on any outside click.
local menu, catcher
local menuRows = {}

local function CloseMenu()
  if menu then menu:Hide() end
  if catcher then catcher:Hide() end
end

local function OpenMenu(anchor, choices, current, onSelect)
  if not menu then
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetScript("OnClick", CloseMenu)
    catcher:Hide()
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    menu:SetBackdropColor(.06, .06, .06, .97)
    menu:SetBackdropBorderColor(.4, .4, .4, 1)
    menu:EnableMouse(true)
    menu:Hide()
  end
  local rowHeight = 20
  menu:SetSize(math.max(anchor:GetWidth(), 150), rowHeight * #choices + 4)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  for i, choice in ipairs(choices) do
    local row = menuRows[i]
    if not row then
      row = CreateFrame("Button", nil, menu)
      row:SetHeight(rowHeight)
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.text:SetPoint("LEFT", 8, 0)
      local hover = row:CreateTexture(nil, "HIGHLIGHT")
      hover:SetAllPoints()
      hover:SetColorTexture(1, 1, 1, .12)
      menuRows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowHeight)
    row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * rowHeight)
    row.text:SetText(choice[2])
    if choice[1] == current then row.text:SetTextColor(1, .82, 0) else row.text:SetTextColor(.85, .85, .85) end
    row:SetScript("OnClick", function()
      CloseMenu()
      onSelect(choice[1])
    end)
    row:Show()
  end
  for i = #choices + 1, #menuRows do menuRows[i]:Hide() end
  catcher:Show()
  menu:Show()
end

local function Dropdown(parent, x, y, width, choices, get, set)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b:SetSize(width, 24)
  local function nameOf(value)
    for _, choice in ipairs(choices) do
      if choice[1] == value then return choice[2] end
    end
    return tostring(value)
  end
  b:SetScript("OnClick", function()
    OpenMenu(b, choices, get(), function(value)
      set(value)
      b:SetText(nameOf(value))
    end)
  end)
  widgets[#widgets + 1] = { Refresh = function() b:SetText(nameOf(get())) end }
  return b
end

-- Panel content ------------------------------------------------------------

local TEXTURES = { { "client", "Client (standard)" }, { "flat", "Flat" }, { "soft", "Soft gradient" } }
local ICON_SETS = { { "stormx", "Stormx painted (personal use)" }, { "client", "Client icons" } }
local ELITE = { { "classic", "Classic dragons (personal use)" }, { "retail", "Retail (client art)" } }
local CASTBAR = { { "above", "Above the name" }, { "below", "Below the bars" } }
local TEXT_FRAMES = { { "player", "Player" }, { "target", "Target" }, { "pet", "Pet" } }

Options.textFrame = "player"

local function TextRow(content, y, kind, title)
  Label(content, 10, y, title, "GameFontNormal")
  local columns = { { "left", "Left", 10 }, { "center", "Center", 210 }, { "right", "Right", 410 } }
  for _, col in ipairs(columns) do
    local where, caption, x = col[1], col[2], col[3]
    Label(content, x, y - 20, caption, "GameFontNormalSmall")
    Dropdown(content, x, y - 38, 190, NF.Text.FORMATS,
      function() return NF.db.text[Options.textFrame][kind][where] end,
      function(value)
        NF.db.text[Options.textFrame][kind][where] = value
        NF.ApplyText()
      end)
  end
end

local function Build(content)
  local db = function() return NF.db end

  Header(content, -10, "General")
  Button(content, 10, -42, 150, "Reset to defaults", function()
    NF.ResetDB()
    NF.ApplyAll()
    RefreshAll()
  end)
  Button(content, 170, -42, 110, "Reload UI", function() ReloadUI() end)

  Header(content, -82, "Appearance")
  Label(content, 10, -116, "Bar texture", "GameFontNormalSmall")
  Dropdown(content, 10, -134, 270, TEXTURES, function() return db().barTexture end, function(value)
    db().barTexture = value
    NF.ApplyBarTexture()
  end)
  Label(content, 300, -116, "Class icons", "GameFontNormalSmall")
  Dropdown(content, 300, -134, 270, ICON_SETS, function() return db().classIconSet end, function(value)
    db().classIconSet = value
    NF.ApplyIcons()
  end)
  Label(content, 10, -168, "Elite / rare art", "GameFontNormalSmall")
  Dropdown(content, 10, -186, 270, ELITE, function() return db().eliteStyle end, function(value)
    db().eliteStyle = value
    NF.ApplyIcons()
  end)
  Label(content, 300, -168, "Cast bar position (target and focus)", "GameFontNormalSmall")
  Dropdown(content, 300, -186, 270, CASTBAR, function() return db().castbarPosition end, function(value)
    db().castbarPosition = value
    if NF.CastBars then NF.CastBars.Apply() end
  end)

  Header(content, -228, "Sizes")
  local function size(group, key)
    return function() return db().sizes[group][key] end,
      function(value)
        db().sizes[group][key] = value
        NF.ApplySizes()
      end
  end
  Label(content, 10, -262, "Player and target frames", "GameFontNormal")
  Slider(content, 10, -286, "Bar width", 80, 200, size("main", "barWidth"))
  Slider(content, 300, -286, "Health bar height", 12, 45, size("main", "hpHeight"))
  Slider(content, 10, -342, "Power bar height", 4, 22, size("main", "powerHeight"))
  Label(content, 10, -398, "Focus, pet and target-of-target frames", "GameFontNormal")
  Slider(content, 10, -422, "Bar width", 50, 150, size("compact", "barWidth"))
  Slider(content, 300, -422, "Health bar height", 8, 32, size("compact", "hpHeight"))
  Slider(content, 10, -478, "Power bar height", 3, 16, size("compact", "powerHeight"))

  Header(content, -534, "Bar text")
  Label(content, 10, -568, "Frame", "GameFontNormalSmall")
  Dropdown(content, 10, -586, 190, TEXT_FRAMES, function() return Options.textFrame end, function(value)
    Options.textFrame = value
    RefreshAll()
  end)
  TextRow(content, -630, "hp", "Health text")
  TextRow(content, -710, "mp", "Power text")
  Label(content, 10, -786, "Focus and target-of-target show no numbers. Open this panel any time with /nf or /norabu.", "GameFontDisableSmall")
end

-- Registration -------------------------------------------------------------

function Options.Init()
  if Options.category or not NF.db then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local panel = CreateFrame("Frame")
  panel.name = "norabu_frames"
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(600, 816)
  scroll:SetScrollChild(content)
  Build(content)
  panel:SetScript("OnShow", RefreshAll)
  content:SetScript("OnShow", RefreshAll)
  panel.OnRefresh = RefreshAll
  panel.OnCommit = function() end
  panel.OnDefault = function() end
  local category = Settings.RegisterCanvasLayoutCategory(panel, "norabu_frames")
  Settings.RegisterAddOnCategory(category)
  Options.category = category
  -- show the saved values right away; the controls keep themselves in sync after that
  RefreshAll()
end

function Options.Open()
  Options.Init()
  if Options.category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(Options.category:GetID())
    RefreshAll()
  else
    print("|cffffd200norabu_frames:|r the Settings panel is not available on this client.")
  end
end

SLASH_NORABUFRAMES1 = "/nf"
SLASH_NORABUFRAMES2 = "/norabu"
SlashCmdList.NORABUFRAMES = function() Options.Open() end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() Options.Init() end)
