TrufiGCD:define('units', function()
    local settingsModule = TrufiGCD:require('settings')
    local UnitFrame = TrufiGCD:require('UnitFrame')
    local blacklist = TrufiGCD:require('blacklist')
    local config = TrufiGCD:require('config')
    local utils = TrufiGCD:require('utils')

    -- settings
    local unitFramesSettings = nil

    local trinketIconAliance = 'Interface\\Icons\\inv_jewelry_trinketpvp_01'
    local trinketIconHorde = 'Interface\\Icons\\inv_jewelry_trinketpvp_01'

    local units = {}

    units.list = {}

    units.updateSettings = function()
        for i, el in pairs(units.list) do
            el:changeOptions(unitFramesSettings[i], settingsModule:getGeneral('tooltip'))
        end
    end

    local function loadSettings()
        unitFramesSettings = settingsModule:getProfileUnitFrames()
        units.updateSettings()
    end

    loadSettings()
    settingsModule:on('change', loadSettings)

    local _idCounter = 0

    local Unit = {}

    function Unit:new(options)
        local obj = {}

        _idCounter = _idCounter + 1

        obj.id = _idCounter

        obj.typeName = options.typeName

        obj.unitFrame = UnitFrame:new(unitFramesSettings[obj.typeName], settingsModule:getGeneral('tooltip'), {
            onDragStop = function() 
                settingsModule:setProfileUnitFrames(units.framesPositions())
            end
        })

        obj.isSpellCasting = false

        obj.canseledSpell = {
            id = 0,
            time = 0,
            iconId = 0
        }

        obj.enable = unitFramesSettings[obj.typeName].enable

        if obj.enable == nil then
            obj.enable = true
        end

        if not obj.enable then
            obj.unitFrame:hide()
        end

        self.__index = self

        metatable = setmetatable(obj, self)

        return metatable
    end

    function Unit:eventsHandler(event, spellId)
        if not self.enable then return end

        if event == 'UNIT_SPELLCAST_START' then self:spellCastStart(spellId)
        elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then self:spellCastSucceeded(spellId)
        elseif event == 'UNIT_SPELLCAST_STOP' then self:spellCastStop(spellId)
        elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then self:spellCastChannelStop(spellId)
        elseif event == 'UNIT_AURA' then self:buffSucceeded() end
    end

    function Unit:checkChangeIcon(spellId, spellIcon)
        if spellId == 42292 then
            if UnitFactionGroup(self.typeName) == 'Horde' then
                return trinketIconHorde
            else
                return trinketIconAliance
            end
        end

        return spellIcon
    end

    function Unit:addSpell(spellId, spellIcon)
        self.unitFrame:addSpell(spellId, self:checkChangeIcon(spellId, spellIcon))
    end

    function Unit:spellCastStart(spellId)
        local spellInfo, _, spellIcon, spellCastTime = GetSpellInfo(spellId)
        local spellLink = GetSpellLink(spellId)

        if blacklist:has(spellId) or spellLink == nil or spellIcon == nil then return end

        self.isSpellCasting = true
        self.unitFrame:stopMoving()

        self:addSpell(spellId, spellIcon)
    end

    function Unit:spellCastSucceeded(spellId)
        local spellInfo, _, spellIcon, spellCastTime = GetSpellInfo(spellId)
        local spellLink = GetSpellLink(spellId)

        if blacklist:has(spellId) or spellLink == nil or spellIcon == nil then return end

        local isChannel = UnitChannelInfo(self.typeName)

        if self.isSpellCasting then
            if not isChannel then
                self.isSpellCasting = false
                self.unitFrame:startMoving()
            end
        else
            local spellFromBuff = self:checkForInstanceBuff(spellId)

            if isChannel then
                self.isSpellCasting = true
                self.unitFrame:stopMoving()
            end

            if GetTime() - self.canseledSpell.time < 1 and self.canseledSpell.id == spellId then
                self.unitFrame:hideCansel(self.canseledSpell.iconId)
            end

            if spellCastTime <= 0 or spellFromBuff then
                self:addSpell(spellId, spellIcon)
            end
        end
    end

    function Unit:spellCastStop(spellId)
        if not self.isSpellCasting then return end

        if blacklist:has(spellId) then return end

        self.isSpellCasting = false
        self.unitFrame:startMoving()

        self.canseledSpell = {
            id = spellId,
            time = GetTime(),
            iconId = self.unitFrame:showCansel(spellId)
        }
    end

    function Unit:spellCastChannelStop(spellId)
        self.isSpellCasting = false
        self.unitFrame:startMoving()
    end

    function Unit:buffSucceeded()
        for i = 1, 20 do
            local buffId = select(11, UnitBuff(self.typeName, i))

            if config.instanceSpellBuffs[buffId] ~= nil then
                self.buffForInstanceSpell = buffId
                break
            end
        end
    end

    function Unit:checkForInstanceBuff(spellId)
        if self.buffForInstanceSpell ~= nil then
            return utils.contain(config.instanceSpellBuffs[self.buffForInstanceSpell], spellId)
        end
        return false
    end

    function Unit:update(time)
        if not self.enable then return end

        self.unitFrame:update(time)
    end

    function Unit:getState()
        return {
            isSpellCasting = self.isSpellCasting,
            canseledSpell = utils.clone(self.canseledSpell),
            unitFrame = self.unitFrame:getState()
        }
    end

    function Unit:setState(state)
        self.isSpellCasting = state.isSpellCasting
        self.canseledSpell = state.canseledSpell
        self.unitFrame:setState(state.unitFrame)
    end

    function Unit:clearFrame()
        self.unitFrame:clear()
    end

    function Unit:changeOptions(options, generalSettings)
        if options.enable ~= nil then
            self.enable = options.enable
        end

        if self.enable then
            self.unitFrame:show()
        else
            self.unitFrame:hide()
        end

        self.unitFrame:changeOptions(options, generalSettings)
    end

    units.create = function()
        for i, el in pairs(config.unitNames) do
            units.list[el] = Unit:new({typeName = el})
        end
    end

    units.showAnchorFrames = function()
        for i, el in pairs(units.list) do
            el.unitFrame:showAnchor()
        end
    end

    units.hideAnchorFrames = function()
        for i, el in pairs(units.list) do
            el.unitFrame:hideAnchor()
        end
    end

    units.framesPositions = function()
        local data = {}

        for i, el in pairs(units.list) do
            local point, ofsX, ofsY = el.unitFrame:getPoint()
            data[i] = {
                point = point,
                offset = {ofsX, ofsY}
            }
        end

        return data
    end

    return units
end)
