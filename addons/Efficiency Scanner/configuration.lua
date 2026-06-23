local function ConfigurationWindow(configuration)
    local this =
    {
        title = "Efficiency Scanner - Configuration",
        open = false,
        changed = false,
    }

    local _configuration = configuration

    local _showWindowSettings = function()
        local success
        local anchorList =
        {
            "Top Left (Disabled)", "Left", "Bottom Left",
            "Top", "Center", "Bottom",
            "Top Right", "Right", "Bottom Right",
        }

        if imgui.TreeNodeEx("General", "DefaultOpen") then
            if imgui.Checkbox("Enable", _configuration.enable) then
                _configuration.enable = not _configuration.enable
                this.changed = true
            end
            imgui.TreePop()
        end

        if imgui.TreeNodeEx("Drop Tracking") then
            local success

            imgui.PushItemWidth(80)
            success, _configuration.dropTechLevel = imgui.InputInt("Min tech disk level##ES", _configuration.dropTechLevel)
            imgui.PopItemWidth()
            if success then
                _configuration.dropTechLevel = math.max(1, math.min(30, _configuration.dropTechLevel))
                this.changed = true
            end

            imgui.PushItemWidth(80)
            success, _configuration.dropHitPercent = imgui.InputInt("Min hit %%##ES", _configuration.dropHitPercent)
            imgui.PopItemWidth()
            if success then
                _configuration.dropHitPercent = math.max(0, math.min(100, _configuration.dropHitPercent))
                this.changed = true
            end

            if imgui.Checkbox("Track rare drops##ES", _configuration.dropRareEnabled) then
                _configuration.dropRareEnabled = not _configuration.dropRareEnabled
                this.changed = true
            end

            if imgui.Checkbox("Count player-dropped items (debug)##ES", _configuration.dropCountPlayerDrops) then
                _configuration.dropCountPlayerDrops = not _configuration.dropCountPlayerDrops
                this.changed = true
            end

            imgui.TreePop()
        end

        if imgui.TreeNodeEx("Window") then
            if imgui.Checkbox("No title bar", _configuration.windowNoTitleBar == "NoTitleBar") then
                if _configuration.windowNoTitleBar == "NoTitleBar" then
                    _configuration.windowNoTitleBar = ""
                else
                    _configuration.windowNoTitleBar = "NoTitleBar"
                end
                this.changed = true
            end

            if imgui.Checkbox("No resize", _configuration.windowNoResize == "NoResize") then
                if _configuration.windowNoResize == "NoResize" then
                    _configuration.windowNoResize = ""
                else
                    _configuration.windowNoResize = "NoResize"
                end
                this.changed = true
            end

            if imgui.Checkbox("No move", _configuration.windowNoMove == "NoMove") then
                if _configuration.windowNoMove == "NoMove" then
                    _configuration.windowNoMove = ""
                else
                    _configuration.windowNoMove = "NoMove"
                end
                this.changed = true
            end

            if imgui.Checkbox("Auto resize", _configuration.windowAlwaysAutoResize == "AlwaysAutoResize") then
                if _configuration.windowAlwaysAutoResize == "AlwaysAutoResize" then
                    _configuration.windowAlwaysAutoResize = ""
                else
                    _configuration.windowAlwaysAutoResize = "AlwaysAutoResize"
                end
                _configuration.windowChanged = true
                this.changed = true
            end

            if imgui.Checkbox("Transparent", _configuration.windowTransparent) then
                _configuration.windowTransparent = not _configuration.windowTransparent
                this.changed = true
            end

            imgui.Text("Position and Size")

            imgui.PushItemWidth(200)
            success, _configuration.windowAnchor = imgui.Combo("Anchor", _configuration.windowAnchor, anchorList, table.getn(anchorList))
            imgui.PopItemWidth()
            if success then
                _configuration.windowChanged = true
                this.changed = true
            end

            imgui.PushItemWidth(100)
            success, _configuration.windowX = imgui.InputInt("X", _configuration.windowX)
            imgui.PopItemWidth()
            if success then
                _configuration.windowChanged = true
                this.changed = true
            end

            imgui.SameLine(0, 38)
            imgui.PushItemWidth(100)
            success, _configuration.windowY = imgui.InputInt("Y", _configuration.windowY)
            imgui.PopItemWidth()
            if success then
                _configuration.windowChanged = true
                this.changed = true
            end

            imgui.PushItemWidth(100)
            success, _configuration.windowW = imgui.InputInt("Width", _configuration.windowW)
            imgui.PopItemWidth()
            if success then
                _configuration.windowChanged = true
                this.changed = true
            end

            imgui.SameLine(0, 10)
            imgui.PushItemWidth(100)
            success, _configuration.windowH = imgui.InputInt("Height", _configuration.windowH)
            imgui.PopItemWidth()
            if success then
                _configuration.windowChanged = true
                this.changed = true
            end

            imgui.TreePop()
        end
    end

    this.Update = function()
        if this.open == false then
            return
        end

        local success
        imgui.SetNextWindowSize(420, 300, "FirstUseEver")
        success, this.open = imgui.Begin(this.title, this.open)

        _showWindowSettings()

        imgui.End()
    end

    return this
end

return
{
    ConfigurationWindow = ConfigurationWindow,
}
