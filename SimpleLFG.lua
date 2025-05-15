-- SimpleLFG: Addon para centralizar solicitudes de grupo del canal mundial
local addonName, SimpleLFG = "SimpleLFG", {}
local SIMPLELFG_VERSION = "1.0"

-- Flag de debug global
local SimpleLFGDebug = false

-- Patrones de detección
local LFG_PATTERNS = {
    "lfg",
    "busco grupo",
    "busco party",
    "busco raid",
    "necesito grupo",
    "necesito party",
    "necesito raid"
}

local LFM_PATTERNS = {
    "lfm",
    "busco gente",
    "busco jugadores",
    "armando grupo",
    "armando party",
    "armando raid",
    "necesito gente",
    "necesito jugadores",
    "armo",
    "lf1m",
    "lf2m",
    "lf3m",
    "lf4m",
    "necesito",
    "nito",
}

-- Configuración predeterminada
local defaultConfig = {
    enabled = true,
    minimap = {
        hide = false,
        position = 45,
    },
    entryTimeout = 300, -- 5 minutos para expirar entradas
    worldChannelName = "world",
}

-- Variables locales
local entries = {
    lfg = {}, -- Los que buscan grupo
    lfm = {}, -- Los que arman grupo
}
local frameCreated = false
local activeTab = 1 -- 1 = LFG, 2 = LFM
local iconFrame = nil
local strmatch = (getglobal and getglobal("string") and getglobal("string").match) or (string and string.match)

-- Función para inicializar el addon
function SimpleLFG:Initialize()
    -- Cargar configuración guardada inmediatamente
    if not SimpleLFGConfig then
        SimpleLFGConfig = {}
        -- Copiar la configuración predeterminada
        for k, v in pairs(defaultConfig) do
            SimpleLFGConfig[k] = v
        end
    end
    
    -- Actualizar configuración si faltan campos
    for k, v in pairs(defaultConfig) do
        if SimpleLFGConfig[k] == nil then
            SimpleLFGConfig[k] = v
        end
    end
    
    -- Registrar eventos
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CHAT_MSG_SAY")
    
    eventFrame:SetScript("OnEvent", function()
        if event == "CHAT_MSG_CHANNEL" then
            SimpleLFG:ProcessChannelMessage(arg1, arg2, arg4, arg8)
        elseif event == "CHAT_MSG_SAY" and SimpleLFGDebug then
            -- Procesar /say como si fuera del canal World
            SimpleLFG:ProcessChannelMessage(arg1, arg2, nil, SimpleLFGConfig.worldChannelName)
        elseif event == "PLAYER_ENTERING_WORLD" then
            SimpleLFG:CreateMinimapIcon()
        end
    end)
    
    -- Iniciar temporizador para limpiar entradas expiradas
    SimpleLFG:StartCleanupTimer()
    
    -- Registrar comandos slash
    SLASH_SIMPLELFG1 = "/simplelfg"
    SLASH_SIMPLELFG2 = "/slfg"
    SlashCmdList["SIMPLELFG"] = function(msg)
        SimpleLFG:ProcessSlashCommand(msg)
    end
    
    -- Mensaje de carga
    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r v" .. SIMPLELFG_VERSION .. " cargado. Usa /simplelfg para abrir la interfaz.")
end

-- Procesar mensajes del canal
function SimpleLFG:ProcessChannelMessage(message, sender, _, channelName)
        
    if not sender then sender = "?" end
    if SimpleLFGDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SimpleLFG]|r Leyendo mensaje: "..message)
    end
    
    local playerName = "?"
    if type(sender) == "string" and sender ~= "" then
        local match = strmatch and strmatch(sender, "([^-]+)") or nil
        if match and match ~= "" then
            playerName = match
        else
            playerName = sender
        end
    end
    
    local msgLower = string.lower(message)
    
    -- Verificar patrones LFG
    for _, pattern in ipairs(LFG_PATTERNS) do
        if string.find(msgLower, pattern) then
            if SimpleLFGDebug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[SimpleLFG]|r Detectado LFG de "..playerName)
            end
            SimpleLFG:AddEntry("lfg", playerName, {
                message = message,
                timestamp = GetTime(),
            })
            return
        end
    end
    
    -- Verificar patrones LFM
    for _, pattern in ipairs(LFM_PATTERNS) do
        if string.find(msgLower, pattern) then
            if SimpleLFGDebug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[SimpleLFG]|r Detectado LFM de "..playerName)
            end
            SimpleLFG:AddEntry("lfm", playerName, {
                message = message,
                timestamp = GetTime(),
            })
            return
        end
    end
end

-- Añadir o actualizar entrada
function SimpleLFG:AddEntry(type, playerName, data)
    -- Eliminar al jugador de ambas listas antes de agregarlo
    entries.lfg[playerName] = nil
    entries.lfm[playerName] = nil

    -- Agregarlo a la lista correspondiente
    entries[type][playerName] = data

    -- Actualizar la UI si está visible
    if frameCreated and SimpleLFGFrame and SimpleLFGFrame:IsVisible() then
        SimpleLFG:UpdateDisplay()
    end
end

-- Limpiar entradas expiradas
function SimpleLFG:CleanExpiredEntries()
    local currentTime = GetTime()
    local timeout = SimpleLFGConfig.entryTimeout
    
    for type, typeEntries in pairs(entries) do
        for playerName, data in pairs(typeEntries) do
            if (currentTime - data.timestamp) > timeout then
                typeEntries[playerName] = nil
            end
        end
    end
    
    -- Actualizar la UI si está visible
    if frameCreated and SimpleLFGFrame and SimpleLFGFrame:IsVisible() then
        SimpleLFG:UpdateDisplay()
    end
end

-- Iniciar temporizador de limpieza
function SimpleLFG:StartCleanupTimer()
    local cleanupFrame = CreateFrame("Frame")
    cleanupFrame:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed > 10 then -- Verificar cada 10 segundos
            this.elapsed = 0
            SimpleLFG:CleanExpiredEntries()
        end
    end)
end

-- Procesar comandos slash
function SimpleLFG:ProcessSlashCommand(msg)
    if msg == "config" then
        SimpleLFG:ShowConfig()
    elseif msg == "clear" then
        entries.lfg = {}
        entries.lfm = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Todas las entradas han sido eliminadas.")
        if frameCreated and SimpleLFGFrame and SimpleLFGFrame:IsVisible() then
            SimpleLFG:UpdateDisplay()
        end
    elseif msg == "debug" then
        SimpleLFGDebug = not SimpleLFGDebug
        if SimpleLFGDebug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Debug activado.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Debug desactivado.")
        end
    else
        if frameCreated and SimpleLFGFrame:IsVisible() then
            SimpleLFGFrame:Hide()
        else
            SimpleLFG:ShowMainFrame()
        end
    end
end

-- Mostrar ventana principal
function SimpleLFG:ShowMainFrame()
    if not SimpleLFGFrame then
        SimpleLFG:CreateMainFrame()
    end
    SimpleLFGFrame:Show()
    SimpleLFG:UpdateDisplay()
end

-- Crear ventana principal
function SimpleLFG:CreateMainFrame()
    if SimpleLFGFrame then return end
    SimpleLFGFrame = CreateFrame("Frame", "SimpleLFGFrame", UIParent)
    local frame = SimpleLFGFrame
    frame:SetWidth(400)
    frame:SetHeight(300)
    frame:SetPoint("CENTER", 0, 0)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    
    -- Título
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("SimpleLFG")
    
    -- Botón de cerrar
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    
    -- Botón de limpiar
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetWidth(80)
    clearButton:SetHeight(25)
    clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
    clearButton:SetText("Limpiar")
    clearButton:SetScript("OnClick", function()
        entries.lfg = {}
        entries.lfm = {}
        SimpleLFG:UpdateDisplay()
    end)
    
    -- Pestañas
    frame.selectedTab = 1
    -- Crear pestañas personalizadas
    local lfgTab = CreateFrame("Button", nil, frame) -- sin nombre global
    lfgTab:SetWidth(120)
    lfgTab:SetHeight(24)
    lfgTab:SetPoint("TOPLEFT", 20, -30)
    local lfgTabBg = lfgTab:CreateTexture(nil, "BACKGROUND")
    lfgTabBg:SetAllPoints()
    lfgTabBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    lfgTabBg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    local lfgTabText = lfgTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lfgTabText:SetPoint("CENTER", 0, 0)
    lfgTabText:SetText("Buscando Grupo")
    lfgTab.text = lfgTabText
    local lfmTab = CreateFrame("Button", nil, frame) -- sin nombre global
    lfmTab:SetWidth(120)
    lfmTab:SetHeight(24)
    lfmTab:SetPoint("LEFT", lfgTab, "RIGHT", 10, 0)
    local lfmTabBg = lfmTab:CreateTexture(nil, "BACKGROUND")
    lfmTabBg:SetAllPoints()
    lfmTabBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    lfmTabBg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    local lfmTabText = lfmTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lfmTabText:SetPoint("CENTER", 0, 0)
    lfmTabText:SetText("Armando Grupo")
    lfmTab.text = lfmTabText
    frame.lfgTab = lfgTab
    frame.lfmTab = lfmTab
    frame.lfgTabBg = lfgTabBg
    frame.lfmTabBg = lfmTabBg
    -- Función para seleccionar pestaña
    local function SelectTab(tabIndex)
        if tabIndex == 1 then
            lfgTabBg:SetVertexColor(0.3, 0.3, 0.3, 1)
            lfgTab.text:SetTextColor(1, 1, 1, 1)
            lfmTabBg:SetVertexColor(0.15, 0.15, 0.15, 0.7)
            lfmTab.text:SetTextColor(0.7, 0.7, 0.7, 1)
        else
            lfgTabBg:SetVertexColor(0.15, 0.15, 0.15, 0.7)
            lfgTab.text:SetTextColor(0.7, 0.7, 0.7, 1)
            lfmTabBg:SetVertexColor(0.3, 0.3, 0.3, 1)
            lfmTab.text:SetTextColor(1, 1, 1, 1)
        end
        frame.selectedTab = tabIndex
        activeTab = tabIndex
        SimpleLFG:UpdateDisplay()
    end
    lfgTab:SetScript("OnClick", function() SelectTab(1) end)
    lfmTab:SetScript("OnClick", function() SelectTab(2) end)
    SelectTab(1)
    
    -- Crear líneas para entradas
    local alternate = false
    frame.entries = {}
    for i = 1, 13 do -- Mostrar 13 entradas a la vez
        local entry = CreateFrame("Button", nil, frame)
        entry.bg = entry:CreateTexture(nil, "BACKGROUND")
        entry.bg:SetAllPoints()
        -- if alternate then
        --     entry.bg:SetColorTexture(0.13, 0.13, 0.13, 0.7)
        -- else
        --     entry.bg:SetColorTexture(0.18, 0.18, 0.18, 0.7)
        -- end
        -- alternate = not alternate
        entry:SetWidth(370)
        entry:SetHeight(16)
        entry:SetPoint("TOPLEFT", 15, -80 + ((i-1) * 16))
        entry.playerName = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        entry.playerName:SetPoint("LEFT", 5, 0)
        entry.playerName:SetWidth(80)
        entry.playerName:SetJustifyH("LEFT")
        entry.level = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        entry.level:SetPoint("LEFT", entry.playerName, "RIGHT", 0, 0)
        entry.level:SetWidth(40)
        entry.level:SetJustifyH("CENTER")
        entry.dungeon = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        entry.dungeon:SetPoint("LEFT", entry.level, "RIGHT", 0, 0)
        entry.dungeon:SetWidth(170)
        entry.dungeon:SetJustifyH("LEFT")
        entry.timer = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        entry.timer:SetPoint("LEFT", entry.dungeon, "RIGHT", 0, 0)
        entry.timer:SetWidth(50)
        entry.timer:SetJustifyH("RIGHT")
        -- Tooltip claro y consistente
        entry:SetScript("OnEnter", function()
            if not this.playerData then return end
            local data = entries.lfg[this.playerData] or entries.lfm[this.playerData]
            if not data then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cffffff00"..this.playerData.."|r", 1, 1, 1)
            GameTooltip:AddLine("|cffccccccNivel:|r "..(SimpleLFG:GetPlayerLevel(this.playerData) or "-"))
            GameTooltip:AddLine("|cffccccccMensaje:|r "..(data.message or ""))
            GameTooltip:AddLine("|cffccccccHace:|r "..SimpleLFG:FormatTime(GetTime() - data.timestamp))
            GameTooltip:Show()
        end)
        entry:SetScript("OnLeave", function() GameTooltip:Hide() end)
        entry:SetScript("OnClick", function()
            if this.playerData then
                ChatFrame_OpenChat("/w " .. this.playerData .. " ")
            end
        end)
        frame.entries[i] = entry
    end
    
    -- Mover encabezados más abajo para que no se superpongan
    local headerPlayer = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerPlayer:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -60)
    headerPlayer:SetWidth(80)
    headerPlayer:SetText("Jugador")
    
    local headerLevel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerLevel:SetPoint("LEFT", headerPlayer, "RIGHT", 0, 0)
    headerLevel:SetWidth(40)
    headerLevel:SetText("Nivel")
    
    local headerDungeon = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerDungeon:SetPoint("LEFT", headerLevel, "RIGHT", 0, 0)
    headerDungeon:SetWidth(170)
    headerDungeon:SetText("Mensaje")
    
    local headerTime = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerTime:SetPoint("LEFT", headerDungeon, "RIGHT", 0, 0)
    headerTime:SetWidth(50)
    headerTime:SetText("Tiempo")
    
    local headerInfo = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerInfo:SetPoint("LEFT", headerDungeon, "RIGHT", 100, 0)
    headerInfo:Hide() -- Ocultamos la columna de detalles
    
    frameCreated = true
end

-- Actualizar la visualización
function SimpleLFG:UpdateDisplay()
    if not SimpleLFGFrame or not SimpleLFGFrame.entries or not SimpleLFGFrame:IsVisible() then return end
    local displayEntries = activeTab == 1 and entries.lfg or entries.lfm
    local sortedEntries = {}
    for playerName, data in pairs(displayEntries) do
        table.insert(sortedEntries, {name = playerName, data = data})
    end
    
    -- Ordenar por timestamp descendente (más reciente primero)
    table.sort(sortedEntries, function(a, b)
        return a.data.timestamp > b.data.timestamp
    end)
    
    -- Ajustar el espaciado vertical
    local entryHeight = 20 -- Aumentar el espacio entre entradas
    local startY = -80 -- Ajustar la posición inicial
    
    -- Limpiar todas las entradas primero
    for i = 1, 13 do
        SimpleLFGFrame.entries[i]:Hide()
    end
    
    -- Mostrar las entradas en orden (más recientes arriba)
    for i = 1, 13 do
        local entry = SimpleLFGFrame.entries[i]
        local playerData = sortedEntries[i]
        if playerData then
            local playerName = playerData.name
            local data = playerData.data
            local currentTime = GetTime()
            entry.playerData = playerName
            -- Cachear el nivel si alguna vez se obtiene
            local level = data.level or SimpleLFG:GetPlayerLevel(playerName)
            if level and level ~= "-" then
                data.level = level
            else
                level = "-"
            end
            entry.level:SetText(level)
            local msg = data.message or ""
            if string.len(msg) > 50 then
                msg = string.sub(msg, 1, 47).."..."
            end
            entry.playerName:SetText(playerName)
            entry.dungeon:SetText(msg)
            entry.timer:SetText(SimpleLFG:FormatTime(currentTime - data.timestamp))
            
            -- Ajustar la posición vertical (más recientes arriba)
            entry:SetPoint("TOPLEFT", 15, startY - ((i-1) * entryHeight))
            entry:Show()
        end
    end
end

-- Formatear tiempo en formato legible
function SimpleLFG:FormatTime(seconds)
    seconds = math.floor(seconds)
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    else
        return math.floor(seconds / 3600) .. "h"
    end
end

-- Crear icono del minimapa
function SimpleLFG:CreateMinimapIcon()
    if iconFrame then return end
    
    -- Asegurarse de que SimpleLFGConfig existe antes de continuar
    if not SimpleLFGConfig then
        SimpleLFG:Initialize()
    end
    
    iconFrame = CreateFrame("Button", "SimpleLFGMinimapIcon", Minimap)
    iconFrame:SetWidth(31)
    iconFrame:SetHeight(31)
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:SetFrameLevel(8)
    iconFrame:SetMovable(true)
    iconFrame:EnableMouse(true)
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Textura del icono
    iconFrame.icon = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    iconFrame.icon:SetWidth(20)
    iconFrame.icon:SetHeight(20)
    iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 7, -5)
    
    -- Borde del icono
    iconFrame.border = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    iconFrame.border:SetWidth(53)
    iconFrame.border:SetHeight(53)
    iconFrame.border:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    
    -- Scripts
    iconFrame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    
    iconFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local xpos, ypos = GetCursorPosition()
        local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
        
        xpos = xmin - xpos / UIParent:GetScale() + 70
        ypos = ypos / UIParent:GetScale() - ymin - 70
        
        SimpleLFGConfig.minimap.position = math.deg(math.atan2(ypos, xpos))
        SimpleLFG:UpdateMinimapIcon()
    end)
    
    iconFrame:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            SimpleLFGDebug = not SimpleLFGDebug
            if SimpleLFGDebug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Debug activado desde el minimapa.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Debug desactivado desde el minimapa.")
            end
        else
            if SimpleLFGFrame and SimpleLFGFrame:IsVisible() then
                SimpleLFGFrame:Hide()
            else
                SimpleLFG:ShowMainFrame()
            end
        end
    end)
    
    iconFrame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("SimpleLFG")
        GameTooltip:AddLine("Click izquierdo: Mostrar/Ocultar lista")
        GameTooltip:AddLine("Click derecho: Alternar debug")
        if SimpleLFGDebug then
            GameTooltip:AddLine("|cff55ff55Debug: ACTIVADO|r")
        else
            GameTooltip:AddLine("|cffff5555Debug: DESACTIVADO|r")
        end
        GameTooltip:Show()
    end)
    
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Posicionar alrededor del minimapa
    SimpleLFG:UpdateMinimapIcon()
end

-- Actualizar posición del icono del minimapa
function SimpleLFG:UpdateMinimapIcon()
    if not iconFrame then return end
    
    -- Verificar que SimpleLFGConfig existe
    if not SimpleLFGConfig then
        SimpleLFGConfig = {}
        for k, v in pairs(defaultConfig) do
            SimpleLFGConfig[k] = v
        end
    end
    
    -- Asegurarse de que la propiedad minimap existe
    if not SimpleLFGConfig.minimap then
        SimpleLFGConfig.minimap = {}
    end
    
    -- Asegurarse de que todas las propiedades del minimapa existen
    if SimpleLFGConfig.minimap.hide == nil then
        SimpleLFGConfig.minimap.hide = defaultConfig.minimap.hide
    end
    
    if SimpleLFGConfig.minimap.position == nil then
        SimpleLFGConfig.minimap.position = defaultConfig.minimap.position
    end
    
    if SimpleLFGConfig.minimap.hide then
        iconFrame:Hide()
        return
    else
        iconFrame:Show()
    end
    
    -- Posicionar alrededor del minimapa
    local angle = math.rad(SimpleLFGConfig.minimap.position)
    local x = 54 - (80 * math.cos(angle))
    local y = (80 * math.sin(angle)) - 55
    
    iconFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", x, y)
end

-- Ventana de configuración
function SimpleLFG:ShowConfig()
    if ConfigFrame and ConfigFrame:IsVisible() then
        ConfigFrame:Hide()
        return
    end
    
    if not ConfigFrame then
        -- Crear la ventana de configuración
        local frame = CreateFrame("Frame", "ConfigFrame", UIParent)
        frame:SetWidth(350)
        frame:SetHeight(300)
        frame:SetPoint("CENTER", 0, 0)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function() this:StartMoving() end)
        frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        frame:SetBackdropColor(0, 0, 0, 1)
        
        -- Título
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -15)
        title:SetText("SimpleLFG - Configuración")
        
        -- Botón de cerrar
        local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        
        -- Checkbox para activar/desactivar el addon
        local enabledCB = CreateFrame("CheckButton", "SimpleLFGEnabledCB", frame, "UICheckButtonTemplate")
        enabledCB:SetPoint("TOPLEFT", 15, -40)
        SimpleLFGEnabledCBText:SetText("Activar SimpleLFG")
        enabledCB:SetChecked(SimpleLFGConfig.enabled)
        enabledCB:SetScript("OnClick", function()
            SimpleLFGConfig.enabled = this:GetChecked()
        end)
        
        -- Checkbox para ocultar ícono del minimapa
        local hideMiniCB = CreateFrame("CheckButton", "SimpleLFGHideMiniCB", frame, "UICheckButtonTemplate")
        hideMiniCB:SetPoint("TOPLEFT", 15, -70)
        SimpleLFGHideMiniCBText:SetText("Ocultar ícono del minimapa")
        hideMiniCB:SetChecked(SimpleLFGConfig.minimap.hide)
        hideMiniCB:SetScript("OnClick", function()
            SimpleLFGConfig.minimap.hide = this:GetChecked()
            SimpleLFG:UpdateMinimapIcon()
        end)
        
        -- Tiempo de expiración
        local timeoutLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        timeoutLabel:SetPoint("TOPLEFT", 15, -100)
        timeoutLabel:SetText("Tiempo de expiración (segundos):")
        
        local timeoutEditBox = CreateFrame("EditBox", "SimpleLFGTimeoutEditBox", frame, "InputBoxTemplate")
        timeoutEditBox:SetWidth(60)
        timeoutEditBox:SetHeight(20)
        timeoutEditBox:SetPoint("TOPLEFT", timeoutLabel, "BOTTOMLEFT", 5, -5)
        timeoutEditBox:SetAutoFocus(false)
        timeoutEditBox:SetNumeric(true)
        timeoutEditBox:SetText(SimpleLFGConfig.entryTimeout)
        timeoutEditBox:SetScript("OnEnterPressed", function()
            local value = tonumber(this:GetText())
            if value and value > 0 then
                SimpleLFGConfig.entryTimeout = value
            end
            this:ClearFocus()
        end)
        
        -- Patrones de búsqueda
        local patternsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        patternsLabel:SetPoint("TOPLEFT", 15, -140)
        patternsLabel:SetText("Patrones de búsqueda (uno por línea):")
        
        -- Botón de guardar
        local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        saveButton:SetWidth(80)
        saveButton:SetHeight(25)
        saveButton:SetPoint("BOTTOM", 0, 15)
        saveButton:SetText("Guardar")
        saveButton:SetScript("OnClick", function()
            frame:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[SimpleLFG]|r Configuración guardada.")
        end)
        
        ConfigFrame = frame
    end
    
    ConfigFrame:Show()
end

-- Inicializar el addon
SimpleLFG:Initialize()

-- Encontrar el nivel del jugador
function SimpleLFG:GetPlayerLevel(playerName)
    if playerName == UnitName("player") then
        return UnitLevel("player")
    end
    for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do
        local name, _, _, level = GetRaidRosterInfo and GetRaidRosterInfo(i) or UnitName("raid"..i), nil, nil, nil
        if name == playerName then
            return level or "-"
        end
    end
    for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
        local name = UnitName("party"..i)
        if name == playerName then
            return UnitLevel("party"..i) or "-"
        end
    end
    return "-"
end 