local addonName = ...

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -200,
    width = 420,
    scale = 1,
    alpha = 1,
    hideInCombat = false,
    hideAtMaxLevel = false,
    showRepAtMaxLevel = true,
    locked = true,
}

local BAR_HEIGHT = 14
local FRAME_HEIGHT = 62
local TEXT_UPDATE_INTERVAL = 0.25
local SMOOTH_SPEED = 10

local frame = CreateFrame("Frame", "WrathXPBarFrame", UIParent)
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:EnableMouse(false)
frame:SetClampedToScreen(true)

local db = nil

local sessionInitialized = false
local xpStartTime = time()
local sessionStartTime = time()
local sessionXP = 0
local lastXP = 0
local lastMaxXP = 1
local lastLevel = 1
local lastRested = 0

local currentValue = 0
local targetValue = 0
local currentRestedValue = 0
local targetRestedValue = 0

local textTicker = 0

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end

    return dst
end

local function FormatNumber(n)
    n = math.floor(n or 0)

    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(n)
    end
end

local function FormatTime(sec)
    sec = math.floor(sec or 0)
    if sec < 0 then
        sec = 0
    end

    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60

    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function GetPlayerMaxLevel()
    if MAX_PLAYER_LEVEL and MAX_PLAYER_LEVEL > 0 then
        return MAX_PLAYER_LEVEL
    end
    return 80
end

local function IsAtMaxLevel()
    return (UnitLevel("player") or 1) >= GetPlayerMaxLevel()
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db.point = point or "CENTER"
    db.relativePoint = relativePoint or "CENTER"
    db.x = x or 0
    db.y = y or 0
end

local function ApplyFrameSettings()
    frame:SetScale(db.scale or 1)
    frame:SetAlpha(db.alpha or 1)
    frame:SetWidth(db.width or DEFAULTS.width)
    frame:SetHeight(FRAME_HEIGHT)

    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or -200)
end

local function SetLocked(locked)
    db.locked = locked

    if locked then
        frame:EnableMouse(false)
        frame:RegisterForDrag()
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
    else
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SavePosition()
        end)
    end
end

local function ResetLevelTimer()
    xpStartTime = time()
end

local function ShouldShowBar()
    if db.hideInCombat and InCombatLockdown() then
        return false
    end

    if IsAtMaxLevel() then
        if db.showRepAtMaxLevel then
            local name = GetWatchedFactionInfo()
            if name then
                return true
            end
        end

        if db.hideAtMaxLevel then
            return false
        end
    end

    return true
end

frame:SetWidth(DEFAULTS.width)
frame:SetHeight(FRAME_HEIGHT)

frame.topLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.topLeft:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -15)
frame.topLeft:SetJustifyH("LEFT")

frame.topRight = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.topRight:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -15)
frame.topRight:SetJustifyH("RIGHT")

frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -18)
frame.bg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -18)
frame.bg:SetHeight(BAR_HEIGHT)
frame.bg:SetVertexColor(0.04, 0.04, 0.04, 0.85)

frame.shadow = frame:CreateTexture(nil, "BORDER")
frame.shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
frame.shadow:SetPoint("TOPLEFT", frame.bg, "TOPLEFT", -1, 1)
frame.shadow:SetPoint("BOTTOMRIGHT", frame.bg, "BOTTOMRIGHT", 1, -1)
frame.shadow:SetVertexColor(0, 0, 0, 0.65)

frame.bar = frame:CreateTexture(nil, "ARTWORK")
frame.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
frame.bar:SetPoint("LEFT", frame.bg, "LEFT", 0, 0)
frame.bar:SetHeight(BAR_HEIGHT)
frame.bar:SetWidth(1)
frame.bar:SetVertexColor(0.62, 0.18, 0.88, 0.95)

frame.rested = frame:CreateTexture(nil, "OVERLAY")
frame.rested:SetTexture("Interface\\Buttons\\WHITE8X8")
frame.rested:SetPoint("LEFT", frame.bar, "RIGHT", 0, 0)
frame.rested:SetHeight(BAR_HEIGHT)
frame.rested:SetWidth(0)
frame.rested:SetVertexColor(0.25, 0.52, 1.0, 0.30)

frame.spark = frame:CreateTexture(nil, "OVERLAY")
frame.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
frame.spark:SetBlendMode("ADD")
frame.spark:SetWidth(18)
frame.spark:SetHeight(30)
frame.spark:SetAlpha(0.75)

frame.barLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.barLeft:SetPoint("LEFT", frame.bg, "LEFT", 5, 0)
frame.barLeft:SetJustifyH("LEFT")

frame.barCenter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.barCenter:SetPoint("CENTER", frame.bg, "CENTER", 0, 0)
frame.barCenter:SetJustifyH("CENTER")

frame.barRight = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.barRight:SetPoint("RIGHT", frame.bg, "RIGHT", -5, 0)
frame.barRight:SetJustifyH("RIGHT")

frame.bottomLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.bottomLeft:SetPoint("TOPLEFT", frame.bg, "BOTTOMLEFT", 0, -4)
frame.bottomLeft:SetJustifyH("LEFT")

frame.bottomRight = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.bottomRight:SetPoint("TOPRIGHT", frame.bg, "BOTTOMRIGHT", 0, -4)
frame.bottomRight:SetJustifyH("RIGHT")

frame.mouse = CreateFrame("Frame", nil, frame)
frame.mouse:SetAllPoints(frame)
frame.mouse:EnableMouse(true)

local function UpdateTooltip()
    if not GameTooltip:IsOwned(frame.mouse) then
        return
    end

    GameTooltip:ClearLines()

    if IsAtMaxLevel() and db.showRepAtMaxLevel then
        local name, standing, minBar, maxBar, value = GetWatchedFactionInfo()

        if name then
            local cur = value - minBar
            local maxv = maxBar - minBar
            local pct = 0
            if maxv > 0 then
                pct = (cur / maxv) * 100
            end

            GameTooltip:AddLine(name, 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Ruf:", string.format("%s / %s (%.1f%%)", FormatNumber(cur), FormatNumber(maxv), pct), 1, 1, 1, 0.85, 0.85, 0.85)
            GameTooltip:AddDoubleLine("Standing:", _G["FACTION_STANDING_LABEL" .. standing] or tostring(standing), 1, 1, 1, 0.85, 0.85, 0.85)
            GameTooltip:Show()
            return
        end
    end

    local curr = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    local rested = GetXPExhaustion() or 0
    local remaining = maxXP - curr
    local pct = (curr / maxXP) * 100
    local restedPct = (rested / maxXP) * 100
    local elapsedSession = time() - sessionStartTime

    local xpPerHour = 0
    if elapsedSession > 0 then
        xpPerHour = math.floor((sessionXP / elapsedSession) * 3600)
    end

    local eta = "--"
    if xpPerHour > 0 then
        eta = FormatTime((remaining / xpPerHour) * 3600)
    end

    GameTooltip:AddLine("Erfahrung", 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Aktuell:", string.format("%d / %d (%.1f%%)", curr, maxXP, pct), 1, 1, 1, 0.85, 0.85, 0.85)
    GameTooltip:AddDoubleLine("Fehlt:", tostring(remaining), 1, 1, 1, 0.85, 0.85, 0.85)
    GameTooltip:AddDoubleLine("Ausgeruht:", string.format("%d (%.1f%%)", rested, restedPct), 0.4, 0.7, 1, 0.4, 0.7, 1)
    GameTooltip:AddDoubleLine("Session XP:", tostring(sessionXP), 1, 1, 1, 0.85, 0.85, 0.85)
    GameTooltip:AddDoubleLine("XP/Stunde:", tostring(xpPerHour), 1, 1, 1, 0.85, 0.85, 0.85)
    GameTooltip:AddDoubleLine("Level in:", eta, 1, 1, 1, 0.85, 0.85, 0.85)
    GameTooltip:Show()
end

frame.mouse:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    UpdateTooltip()
end)

frame.mouse:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function GetXPModeData()

    if IsAtMaxLevel() then
        return {
            mode = "xp",
            left = "Level " .. UnitLevel("player"),
            center = "Max Level",
            right = "",
            current = 1,
            max = 1,
            rested = 0,
            color = {0.62, 0.18, 0.88, 0.95},
            topLeft = "Time this level: --",
            topRight = "Time this session: " .. FormatTime(time() - sessionStartTime),
        }
    end

    local curr = UnitXP("player") or 0
    local maxv = UnitXPMax("player") or 1
    local rested = GetXPExhaustion() or 0
    local level = UnitLevel("player") or 1

    if maxv < 1 then
        maxv = 1
    end

    return {
        mode = "xp",
        left = "Level " .. level,
        center = string.format("%s / %s", FormatNumber(curr), FormatNumber(maxv)),
        right = string.format("%.1f%%", (curr / maxv) * 100),
        current = curr,
        max = maxv,
        rested = rested,
        color = {0.62, 0.18, 0.88, 0.95},
        topLeft = "Time this level: " .. FormatTime(time() - xpStartTime),
        topRight = "Time this session: " .. FormatTime(time() - sessionStartTime),
    }
end

local function GetRepModeData()
    local name, standing, minBar, maxBar, value = GetWatchedFactionInfo()
    if not name then
        return nil
    end

    local curr = value - minBar
    local maxv = maxBar - minBar
    if maxv < 1 then
        maxv = 1
    end

    local standingText = _G["FACTION_STANDING_LABEL" .. standing] or tostring(standing)

    return {
        mode = "rep",
        left = name,
        center = string.format("%s / %s", FormatNumber(curr), FormatNumber(maxv)),
        right = string.format("%.1f%%", (curr / maxv) * 100),
        current = curr,
        max = maxv,
        rested = 0,
        color = { 0.15, 0.75, 0.35, 0.95 },
        topLeft = "Reputation watched",
        topRight = standingText,
    }
end

local function GetDisplayData()
    if IsAtMaxLevel() and db.showRepAtMaxLevel then
        local repData = GetRepModeData()
        if repData then
            return repData
        end
    end

    return GetXPModeData()
end

local function UpdateSessionXP()
    local newLevel = UnitLevel("player") or 1
    local newXP = UnitXP("player") or 0
    local newMaxXP = UnitXPMax("player") or 1

    if newMaxXP < 1 then
        newMaxXP = 1
    end

    if lastLevel == 0 then
        lastLevel = newLevel
        lastXP = newXP
        lastMaxXP = newMaxXP
        return
    end

    if newLevel > lastLevel then
        sessionXP = sessionXP + math.max(0, (lastMaxXP - lastXP))
        sessionXP = sessionXP + math.max(0, newXP)
        ResetLevelTimer()
    elseif newLevel == lastLevel then
        if newXP >= lastXP then
            sessionXP = sessionXP + (newXP - lastXP)
        end
    end

    lastLevel = newLevel
    lastXP = newXP
    lastMaxXP = newMaxXP
    lastRested = GetXPExhaustion() or 0
end

local function UpdateVisualImmediate(data)
    targetValue = data.current / data.max
    targetRestedValue = math.min((data.current + data.rested) / data.max, 1)

    if currentValue == 0 and targetValue > 0 then
        currentValue = targetValue
    end
    if currentRestedValue == 0 and targetRestedValue >= 0 then
        currentRestedValue = targetRestedValue
    end

    frame.bar:SetVertexColor(data.color[1], data.color[2], data.color[3], data.color[4])
    frame.barLeft:SetText(data.left)
    frame.barCenter:SetText(data.center)
    frame.barRight:SetText(data.right)
    frame.topLeft:SetText(data.topLeft)
    frame.topRight:SetText(data.topRight)

    if data.mode == "xp" then
        local completed = (data.current / data.max) * 100
        local restedPct = (data.rested / data.max) * 100

        local elapsedSession = time() - sessionStartTime
        local xpPerHour = 0
        if elapsedSession > 0 then
            xpPerHour = math.floor((sessionXP / elapsedSession) * 3600)
        end

        local remaining = data.max - data.current
        local eta = "--"
        if xpPerHour > 0 then
            eta = FormatTime((remaining / xpPerHour) * 3600)
        end

        frame.bottomLeft:SetText(string.format("Leveling in: %s (%s XP/Hour)", eta, FormatNumber(xpPerHour)))
        frame.bottomRight:SetText(string.format("Completed: %.0f%% - Rested: %.0f%%", completed, restedPct))
    else
        local completed = (data.current / data.max) * 100
        frame.bottomLeft:SetText("Max level reached")
        frame.bottomRight:SetText(string.format("Completed: %.0f%%", completed))
    end
end

local function UpdateBarVisibility()
    if ShouldShowBar() then
        frame:Show()
    else
        frame:Hide()
    end
end

local function RefreshData()
    local data = GetDisplayData()
    lastRested = GetXPExhaustion() or 0
    UpdateVisualImmediate(data)
    UpdateBarVisibility()
    UpdateTooltip()
end

local function RenderSmooth(elapsed)
    local changed = false

    if math.abs(currentValue - targetValue) > 0.001 then
        currentValue = currentValue + (targetValue - currentValue) * math.min(elapsed * SMOOTH_SPEED, 1)
        changed = true
    else
        currentValue = targetValue
    end

    if math.abs(currentRestedValue - targetRestedValue) > 0.001 then
        currentRestedValue = currentRestedValue + (targetRestedValue - currentRestedValue) * math.min(elapsed * SMOOTH_SPEED, 1)
        changed = true
    else
        currentRestedValue = targetRestedValue
    end

    local width = db.width or DEFAULTS.width
    local xpWidth = math.max(1, width * currentValue)
    local restedWidth = math.max(0, (width * currentRestedValue) - xpWidth)

    frame.bar:SetWidth(xpWidth)

    frame.rested:ClearAllPoints()
    frame.rested:SetPoint("LEFT", frame.bar, "RIGHT", 0, 0)
    frame.rested:SetWidth(restedWidth)

    frame.spark:ClearAllPoints()
    frame.spark:SetPoint("CENTER", frame.bar, "RIGHT", 0, 0)

    if currentValue <= 0.01 then
        frame.spark:Hide()
    else
        frame.spark:Show()
    end

    if changed then
        UpdateTooltip()
    end
end

local function FullRefresh()
    RefreshData()
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= addonName then
            return
        end

        WrathXPBarDB = CopyDefaults(DEFAULTS, WrathXPBarDB or {})
        db = WrathXPBarDB

        ApplyFrameSettings()
        SetLocked(db.locked)

        lastXP = UnitXP("player") or 0
        lastMaxXP = UnitXPMax("player") or 1
        lastLevel = UnitLevel("player") or 1
        lastRested = GetXPExhaustion() or 0

        FullRefresh()

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not sessionInitialized then
            sessionInitialized = true
            sessionStartTime = time()
            xpStartTime = time()
            sessionXP = 0
        end

        lastXP = UnitXP("player") or 0
        lastMaxXP = UnitXPMax("player") or 1
        lastLevel = UnitLevel("player") or 1
        lastRested = GetXPExhaustion() or 0

        FullRefresh()

    elseif event == "PLAYER_XP_UPDATE" then
        UpdateSessionXP()
        RefreshData()

    elseif event == "PLAYER_LEVEL_UP" then
        RefreshData()

    elseif event == "UPDATE_EXHAUSTION" then
        lastRested = GetXPExhaustion() or 0
        RefreshData()

    elseif event == "UPDATE_FACTION" then
        RefreshData()

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateBarVisibility()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UPDATE_EXHAUSTION")
frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", OnEvent)

frame:SetScript("OnUpdate", function(self, elapsed)
    RenderSmooth(elapsed)

    textTicker = textTicker + elapsed
    if textTicker >= TEXT_UPDATE_INTERVAL then
        textTicker = 0
        if frame:IsShown() then
            RefreshData()
        end
    end
end)

SLASH_WRATHXPBAR1 = "/wxp"
SlashCmdList["WRATHXPBAR"] = function(msg)
    if not db then
        return
    end

    msg = string.lower(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd or ""
    rest = rest or ""

    if cmd == "move" then
        SetLocked(false)
        print("WrathXPBar: Verschieben aktiviert.")

    elseif cmd == "lock" then
        SetLocked(true)
        SavePosition()
        print("WrathXPBar: Verschieben deaktiviert.")

    elseif cmd == "reset" then
        db.point = "CENTER"
        db.relativePoint = "CENTER"
        db.x = 0
        db.y = -200
        ApplyFrameSettings()
        print("WrathXPBar: Position zurueckgesetzt.")

    elseif cmd == "width" then
        local n = tonumber(rest)
        if n and n >= 200 and n <= 1200 then
            db.width = math.floor(n)
            ApplyFrameSettings()
            RefreshData()
            print("WrathXPBar: Breite = " .. db.width)
        else
            print("WrathXPBar: /wxp width 200-1200")
        end

    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 3 then
            db.scale = n
            ApplyFrameSettings()
            print("WrathXPBar: Scale = " .. db.scale)
        else
            print("WrathXPBar: /wxp scale 0.5-3")
        end

    elseif cmd == "alpha" then
        local n = tonumber(rest)
        if n and n >= 0.1 and n <= 1 then
            db.alpha = n
            ApplyFrameSettings()
            print("WrathXPBar: Alpha = " .. db.alpha)
        else
            print("WrathXPBar: /wxp alpha 0.1-1")
        end

    elseif cmd == "hidecombat" then
        db.hideInCombat = not db.hideInCombat
        UpdateBarVisibility()
        print("WrathXPBar: Hide in Combat = " .. tostring(db.hideInCombat))

    elseif cmd == "hidemax" then
        db.hideAtMaxLevel = not db.hideAtMaxLevel
        UpdateBarVisibility()
        print("WrathXPBar: Hide at Max Level = " .. tostring(db.hideAtMaxLevel))

    elseif cmd == "rep" then
        db.showRepAtMaxLevel = not db.showRepAtMaxLevel
        RefreshData()
        print("WrathXPBar: Reputation at Max Level = " .. tostring(db.showRepAtMaxLevel))

    elseif cmd == "test" then
        frame:Show()
        frame.bar:SetVertexColor(0.62, 0.18, 0.88, 0.95)
        frame.barLeft:SetText("Level 20")
        frame.barCenter:SetText("18.8k / 23.2k")
        frame.barRight:SetText("81.1%")
        frame.topLeft:SetText("Time this level: 3h 58m")
        frame.topRight:SetText("Time this session: 2h 11m")
        frame.bottomLeft:SetText("Leveling in: 22m (11.7k XP/Hour)")
        frame.bottomRight:SetText("Completed: 41% - Rested: 0%")

        currentValue = 0.811
        targetValue = 0.811
        currentRestedValue = 0.811
        targetRestedValue = 0.811
        RenderSmooth(1)

        print("WrathXPBar: Testanzeige aktiv.")

    else
        print("/wxp move        - Leiste verschieben")
        print("/wxp lock        - Leiste fixieren")
        print("/wxp reset       - Position zuruecksetzen")
        print("/wxp width 500   - Breite setzen")
        print("/wxp scale 1.2   - Skalierung setzen")
        print("/wxp alpha 0.8   - Transparenz setzen")
        print("/wxp hidecombat  - Im Kampf aus/ein")
        print("/wxp hidemax     - Auf Maxlevel aus/ein")
        print("/wxp rep         - Rufleiste auf Maxlevel aus/ein")
        print("/wxp test        - Testanzeige")
    end
end