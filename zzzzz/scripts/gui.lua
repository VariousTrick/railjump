-- /scripts/gui.lua
-- 【传送门 Mod - GUI 模块 v1.0】(本地化修复版)
-- 功能：集中管理所有与玩家图形界面 (GUI) 相关的功能。
-- 设计原则：将视图 (View) 与控制器 (Controller) 逻辑分离，使界面代码内聚，易于修改。

local GUI = {}

-- =================================================================================
-- 模块本地变量 (用于存储依赖)
-- =================================================================================
local State = nil
local Chuansongmen = nil
local CybersynCompat = nil
local log_debug = function() end

local function is_resource_cost_enabled()
    return settings.startup["chuansongmen-enable-resource-cost"] and
        settings.startup["chuansongmen-enable-resource-cost"].value or false
end

--- 依赖注入函数
function GUI.init(dependencies)
    State = dependencies.State
    Chuansongmen = dependencies.Chuansongmen
    CybersynCompat = dependencies.CybersynCompat
    log_debug = dependencies.log_debug
    if log_debug then
        log_debug("传送门 GUI 模块: 依赖注入成功。")
    end
end

-- =================================================================================
-- GUI 创建与更新
-- =================================================================================

--- 【新增/修正】构建“显示名称”状态的UI (视图函数)
-- 备注：此版本使用单一的 label 来显示富文本“图标+名称”，移除了独立的图标方块。
-- @param parent_flow LuaGuiElement 将要添加UI元素的容器 (即 name_flow)
-- @param my_data table 当前传送门的数据
function GUI.build_display_name_flow(parent_flow, my_data)
    parent_flow.clear()

    -- 1. 构建包含图标和名称的富文本字符串
    local name_with_icon_richtext
    -- 【安全检查】确保 my_data.icon 有效，如果无效则只显示名称
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        name_with_icon_richtext = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "] " .. my_data.name
    else
        name_with_icon_richtext = my_data.name -- 如果图标无效，则安全地只显示名字
    end

    -- 2. 添加一个 label 来显示完整的富文本名称
    parent_flow.add({ type = "label", caption = name_with_icon_richtext, style = "bold_label" })

    -- 3. 添加重命名按钮 (保持不变)
    parent_flow.add({
        type = "sprite-button",
        name = "chuansongmen_rename_button",
        sprite = "utility/rename_icon",
        tooltip = { "gui.chuansongmen-rename-tooltip" },
        style = "tool_button"
    })
end

--- 【新增/修正】构建“编辑名称”状态的UI (视图函数)
-- 备注：采用 icon_selector=true 属性实现，简化了所有图标选择逻辑。
-- @param parent_flow LuaGuiElement 将要添加UI元素的容器 (即 name_flow)
-- @param my_data table 当前传送门的数据
-- @param player LuaPlayer
function GUI.build_edit_name_flow(parent_flow, my_data, player)
    parent_flow.clear()

    -- 1. 构建初始文本: 将当前的图标和名称组合成文本框的初始内容
    local current_icon_richtext = ""
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        current_icon_richtext = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "] "
    end
    local initial_text = current_icon_richtext .. my_data.name

    -- 2. 添加带有图标选择器的文本输入框
    local textfield = parent_flow.add({
        type = "textfield",
        name = "chuansongmen_rename_textfield",
        text = initial_text,         -- 使用包含富文本的初始文本
        icon_selector = true,        -- 【核心修正】启用游戏内置的图标选择功能
        handler = "on_gui_confirmed" -- 监听回车键事件
    })
    textfield.style.width = 300      -- 加宽文本框以容纳图标
    textfield.focus()                -- 自动聚焦，让玩家可以直接输入
    textfield.select_all()           -- 自动全选，方便玩家直接覆盖输入

    -- 3. 添加确认按钮
    parent_flow.add({
        type = "sprite-button",
        name = "chuansongmen_confirm_rename_button",
        sprite = "utility/check_mark",
        tooltip = { "gui.chuansongmen-rename-confirm-tooltip" },
        style = "tool_button_green"
    })
end

function GUI.create_cybersyn_anchor_gui(player, entity)
    local left_gui = player.gui.left
    local anchor_frame_name = "chuansongmen_anchor_frame"
    if left_gui[anchor_frame_name] and left_gui[anchor_frame_name].valid then return end
    left_gui.add { type = "flow", name = anchor_frame_name, direction = "vertical" }
end

function GUI.build_or_update(player, entity)
    log_debug("传送门 GUI (build_or_update): 开始为玩家 " .. player.name .. " 构建/更新 GUI, 实体 unit_number: " .. entity.unit_number)
    if not (player and entity and entity.valid) then return end

    if storage.chuansongmen_player_settings == nil then storage.chuansongmen_player_settings = {} end
    if storage.chuansongmen_player_settings[player.index] == nil then storage.chuansongmen_player_settings[player.index] = {} end
    if storage.chuansongmen_player_settings[player.index].show_preview == nil then
        local default = player.mod_settings["chuansongmen_show_preview"] and
            player.mod_settings["chuansongmen_show_preview"].value
        storage.chuansongmen_player_settings[player.index].show_preview = (default == true)
    end
    local player_settings = { show_preview = storage.chuansongmen_player_settings[player.index].show_preview }

    local gui = player.gui.relative
    if gui.chuansongmen_main_frame then gui.chuansongmen_main_frame.destroy() end

    local my_data = State.get_struct(entity)
    if not my_data then
        log_debug("传送门 GUI 错误 (build_or_update): 未找到实体对应的传送门数据。")
        return
    end

    local anchor = {
        gui = defines.relative_gui_type.assembling_machine_gui,
        position = defines.relative_gui_position
            .right
    }
    local frame = gui.add({ type = "frame", name = "chuansongmen_main_frame", direction = "vertical", anchor = anchor, tags = { unit_number_str = tostring(entity.unit_number) } })

    -- 【修正】标题行：使其也能显示图标和名称
    local title_caption
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        -- 如果有图标，标题格式为：[图标] 名称 (ID: XX)
        title_caption = "[" ..
            my_data.icon.type .. "=" .. my_data.icon.name .. "] " .. my_data.name .. " (ID: " .. my_data.id .. ")"
    else
        -- 如果没有图标，则使用旧格式
        title_caption = "传送门 " .. my_data.name .. " (ID: " .. my_data.id .. ")"
    end
    frame.add({ type = "flow", name = "title_flow" }).add({
        type = "label",
        name = "title",
        caption = title_caption,
        style =
        "frame_title",
        ignored_by_interaction = true
    })

    -- Cybersyn 开关 (保持不变，因为其内部tooltip是简单字符串)
    if CybersynCompat and CybersynCompat.is_present then
        local cybersyn_flow = frame.add({ type = "flow", name = "cybersyn_flow", direction = "horizontal" })
        cybersyn_flow.style.horizontally_stretchable = true
        local is_paired_bool = (my_data.paired_to_id and State.get_opposite_struct(my_data)) ~= nil

        local tooltip_text
        if not is_paired_bool then
            tooltip_text = { "gui.chuansongmen-cybersyn-tooltip-unpaired" }
        elseif script.active_mods["space-exploration"] then
            tooltip_text = { "gui.chuansongmen-cybersyn-tooltip-enabled-se" }
        else
            tooltip_text = { "gui.chuansongmen-cybersyn-tooltip-enabled-no-se" }
        end

        cybersyn_flow.add({
            type = "switch",
            name = CybersynCompat.BUTTON_NAME,
            switch_state = my_data.cybersyn_connected and "right" or "left",
            right_label_caption = { "gui.chuansongmen-cybersyn-connected" },
            left_label_caption = { "gui.chuansongmen-cybersyn-disconnected" },
            allow_none_state = false,
            tooltip = tooltip_text,
            enabled = is_paired_bool,
            handler = "on_gui_checked_state_changed"
        })
    end

    -- 名称与重命名 (已重构)
    local name_flow = frame.add({ type = "flow", name = "name_flow", direction = "horizontal" })
    name_flow.style.left_padding = 8
    name_flow.style.vertical_align = "center" -- 让图标和文字垂直居中对齐
    GUI.build_display_name_flow(name_flow, my_data)

    local content_flow = frame.add({ type = "flow", name = "content_flow", direction = "vertical" })
    content_flow.style.padding = 8

    -- 【回退修复】状态显示：回归硬编码字符串拼接
    local status_flow = content_flow.add({ type = "flow", name = "status_flow", direction = "vertical" })
    local pair_status_flow = status_flow.add({ type = "flow", name = "pair_status_flow" })
    pair_status_flow.add({ type = "label", caption = "传送配对: " })
    if my_data.paired_to_id then
        local opposite = State.get_opposite_struct(my_data)
        pair_status_flow.add({
            type = "label",
            caption = "已连接到 " ..
                (opposite and opposite.name or "未知") ..
                " (ID: " ..
                tostring(my_data.paired_to_id) ..
                ") [" .. (opposite and opposite.entity and opposite.entity.surface.name or "未知地表") .. "]",
            style = "bold_label"
        })
    else
        pair_status_flow.add({ type = "label", caption = { "gui.chuansongmen-unlinked" } })
    end

    -- 目标选择下拉框
    local dropdown_flow = content_flow.add({ type = "flow", name = "dropdown_flow", direction = "vertical" })
    dropdown_flow.add({ type = "label", caption = { "gui.chuansongmen-select-target" } })
    local dropdown = dropdown_flow.add({ type = "drop-down", name = "target_dropdown" })

    -- 【优化】构建下拉框的全新逻辑 (参考 RiftRail)
    local dropdown_items = {}
    local dropdown_ids = {} -- [新增] 单独存储 ID，用于 tags
    local selected_idx_to_set = 0

    for _, data in pairs(MOD_DATA.portals) do
        -- 过滤逻辑：
        -- 1. 不是自己
        -- 2. 实体有效
        -- 3. 方向一致
        -- 4. [新增] 对方未配对，或者对方配对的就是我
        if data.id ~= my_data.id and
            data.entity and data.entity.valid and
            data.entity.direction == my_data.entity.direction and
            (not data.paired_to_id or data.paired_to_id == my_data.id)
        then
            -- 1. 准备富文本名称
            local icon_prefix = ""
            if data.icon and data.icon.type and data.icon.name then
                icon_prefix = "[" .. data.icon.type .. "=" .. data.icon.name .. "] "
            end
            local rich_name = icon_prefix .. data.name

            -- 2. 构建本地化条目
            local item_entry = { "gui.chuansongmen-dropdown-item-format", rich_name, tostring(data.id), data.entity
                .surface.name }

            table.insert(dropdown_items, item_entry)
            table.insert(dropdown_ids, data.id) -- [新增] 将 ID 存入 tags 列表

            -- 3. 检查是否为当前选中项
            if my_data.paired_to_id and my_data.paired_to_id == data.id then
                selected_idx_to_set = #dropdown_items
            end
        end
    end

    dropdown.items = dropdown_items

    -- [新增] 将 ID 列表存入 tags，彻底和显示文本解耦
    dropdown.tags = { ids = dropdown_ids }

    if selected_idx_to_set > 0 then dropdown.selected_index = selected_idx_to_set end
    dropdown.style.width = 300
    if #dropdown_items == 0 then dropdown.enabled = false end

    -- 按钮 (保持动态创建和本地化)
    local button_flow = content_flow.add({ type = "flow", name = "button_flow" })
    button_flow.style.top_margin = 8
    if my_data.paired_to_id then
        button_flow.add({ type = "button", name = "unpair_button", caption = { "gui.chuansongmen-button-unpair" } })
        if my_data.power_connection_status == "connected" then
            local power_button = button_flow.add({ type = "button", name = "disconnect_power_button", caption = { "gui.chuansongmen-button-disconnect-power" } })
            if not is_resource_cost_enabled() then
                power_button.tooltip = { "gui.chuansongmen-tooltip-disconnect-no-cost" }
            end
        else
            local power_button = button_flow.add({ type = "button", name = "connect_power_button", caption = { "gui.chuansongmen-button-connect-power" } })
            if is_resource_cost_enabled() then
                power_button.tooltip = { "gui.chuansongmen-tooltip-connect-cost" }
            else
                power_button.tooltip = { "gui.chuansongmen-tooltip-connect-no-cost" }
            end
        end
    else
        local pair_button = button_flow.add({ type = "button", name = "pair_button", caption = { "gui.chuansongmen-button-pair" } })
        if #dropdown.items == 0 then
            pair_button.enabled = false
        end
    end

    content_flow.add { type = "line", direction = "horizontal" }

    -- 选项 (保持本地化)
    local options_flow = content_flow.add({ type = "flow", name = "options_flow" })
    options_flow.add({
        type = "checkbox",
        name = "chuansongmen_preview_checkbox",
        state = player_settings.show_preview,
        caption = { "mod-setting-name.chuansongmen_show_preview" },
        handler =
        "on_gui_checked_state_changed"
    })

    -- 传送与观察按钮 (保持本地化)
    local teleport_flow = content_flow.add({ type = "flow", name = "teleport_flow" })
    teleport_flow.add({ type = "button", name = "player_teleport_button", caption = { "gui.chuansongmen-button-player-teleport" } })
    local view_caption = (remote.interfaces["space-exploration"] and { "gui.chuansongmen-button-remote-view" }) or
        { "gui.chuansongmen-button-map-view" }
    teleport_flow.add({ type = "button", name = "se_remote_view_button", caption = view_caption })

    -- 根据状态禁用按钮
    if not my_data.paired_to_id then
        teleport_flow.player_teleport_button.enabled = false
        teleport_flow.se_remote_view_button.enabled = false
        options_flow.chuansongmen_preview_checkbox.enabled = false
    end

    -- 【回退修复】远程预览摄像头：回归硬编码字符串拼接
    if my_data.paired_to_id and player_settings.show_preview then
        local opposite = State.get_opposite_struct(my_data)
        if opposite and opposite.entity and opposite.entity.valid then
            frame.add({ type = "label", style = "frame_title", caption = "远程预览: " .. opposite.name .. " [" .. opposite.entity.surface.name .. "]" }).style.left_padding = 8
            local preview_frame = frame.add({ type = "frame", name = "preview_frame", style = "inside_shallow_frame" })
            preview_frame.style.horizontally_stretchable = true
            preview_frame.style.vertically_stretchable = true
            local camera = preview_frame.add({
                type = "camera",
                name = "preview_camera",
                position = opposite.entity
                    .position,
                zoom = 0.15,
                surface_index = opposite.entity.surface.index
            })
            camera.style.horizontally_stretchable = true
            camera.style.vertically_stretchable = true
        end
    end
    log_debug("传送门 GUI (build_or_update): GUI 构建/更新完成。")
end

function GUI.open_fullscreen_camera_view(player, target_struct)
    log_debug("传送门 GUI (open_fullscreen_camera_view): 为玩家 " ..
        player.name .. " 打开全屏观察, 目标: " .. target_struct.name .. " (ID: " .. target_struct.id .. ")")
    local screen_gui = player.gui.screen
    if screen_gui.chuansongmen_fullscreen_view_frame then
        screen_gui.chuansongmen_fullscreen_view_frame.destroy()
    end

    local frame = screen_gui.add({
        type = "frame",
        name = "chuansongmen_fullscreen_view_frame",
        direction = "vertical",
        style =
        "frame"
    })
    frame.auto_center = true

    local title_flow = frame.add { type = "flow", direction = "horizontal" }
    -- 【回退修复】全屏观察标题：回归硬编码字符串拼接
    title_flow.add { type = "label", caption = target_struct.name .. " 远程观察" }
    title_flow.add { type = "empty-widget", style = "draggable_space_header" }
    title_flow.add { type = "button", name = "chuansongmen_close_fullscreen_view_button", caption = { "gui.chuansongmen-button-close-fullscreen-view" }, style = "red_button" }

    local camera = frame.add {
        type = "camera", name = "chuansongmen_fullscreen_camera",
        position = target_struct.position, surface_index = target_struct.surface.index, zoom = 0.25
    }
    camera.style.width = 1000
    camera.style.height = 700
    camera.style.horizontal_align = "center"
end

-- =================================================================================
-- GUI 事件处理
-- =================================================================================

function GUI.handle_click(event)
    if not (event.element and event.element.valid) then return end
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    if element_name == "chuansongmen_close_fullscreen_view_button" then
        local screen_gui = player.gui.screen
        if screen_gui.chuansongmen_fullscreen_view_frame then screen_gui.chuansongmen_fullscreen_view_frame.destroy() end
        return
    end

    local frame = player.gui.relative.chuansongmen_main_frame
    if not frame then return end
    local entity = player.opened
    if not (entity and entity.valid) then return end
    local my_data = State.get_struct(entity)
    if not my_data then return end

    log_debug("传送门 GUI (handle_click): 玩家 " .. player.name .. " 点击了 " .. element_name .. ", 传送门 ID: " .. my_data.id)

    if element_name == "pair_button" then
        local dropdown = frame.content_flow.dropdown_flow.target_dropdown
        if dropdown and dropdown.selected_index > 0 then
            -- 【优化】从 tags 读取 ID，不再解析字符串
            local target_id = nil
            if dropdown.tags and dropdown.tags.ids then
                target_id = dropdown.tags.ids[dropdown.selected_index]
            end

            if target_id then
                log_debug("GUI (配对): 选中索引 " .. dropdown.selected_index .. ", 从 tags 获取到目标 ID: " .. target_id)
                remote.call("zchuansongmen", "pair_portals", player.index, my_data.id, target_id)
            else
                player.print({ "messages.chuansongmen-error-no-target" })
                log_debug("GUI (配对) 错误: 无法从 tags 获取 ID。")
            end
        else
            player.print({ "messages.chuansongmen-error-select-first" })
        end
    elseif element_name == "unpair_button" then
        remote.call("zchuansongmen", "unpair_portals", player.index, my_data.id)
    elseif element_name == "connect_power_button" then
        remote.call("zchuansongmen", "connect_portal_power", player.index, my_data.id)
    elseif element_name == "disconnect_power_button" then
        remote.call("zchuansongmen", "disconnect_portal_power", player.index, my_data.id)
    elseif element_name == "player_teleport_button" then
        if not MOD_DATA.players_to_teleport then MOD_DATA.players_to_teleport = {} end
        MOD_DATA.players_to_teleport[player.index] = { portal_id = my_data.id }
    elseif element_name == "se_remote_view_button" then
        -- 获取对侧传送门的数据，这部分逻辑保持不变
        local opposite = State.get_opposite_struct(my_data)
        if not (opposite and opposite.entity and opposite.entity.valid) then
            player.print({ "messages.chuansongmen-error-invalid-target-simple" })
            return
        end

        -- 如果玩家安装了 Space Exploration (SE) Mod，则维持原有的、强大的 SE 远程观察逻辑
        if remote.interfaces["space-exploration"] and remote.interfaces["space-exploration"]["remote_view_start"] then
            if remote.call("space-exploration", "remote_view_is_unlocked", { player = player }) then
                local zone_info = remote.call("space-exploration", "get_zone_from_surface_index",
                    { surface_index = opposite.entity.surface.index })
                if zone_info and zone_info.name then
                    remote.call("space-exploration", "remote_view_start",
                        { player = player, zone_name = zone_info.name, position = opposite.entity.position })
                    player.opened = nil
                end
            else
                player.print({ "messages.chuansongmen-error-se-tech-required" })
            end
        else
            -- 【核心修改】如果玩家没有安装 SE，则使用我们在 2.0 版本中验证通过的 player.set_controller API

            -- 步骤 1: 获取玩家当前的摄像头缩放级别
            local current_zoom = player.zoom

            -- 步骤 2: 打印调试日志，记录我们将要执行的操作
            log_debug("传送门 GUI (handle_click): 玩家 " ..
                player.name .. " 正在使用 2.0 API (set_controller) 进行地图观察。缩放级别: " .. current_zoom)

            -- 步骤 3: 在打开新视图前，先关闭当前的传送门 GUI，这是个好习惯
            player.opened = nil

            -- 步骤 4: 调用新的 API，将玩家的控制器设置为“远程模式”
            player.set_controller({
                type = defines.controllers.remote,   -- 控制器类型：设置为远程模式
                position = opposite.entity.position, -- 目标坐标：设置为对侧传送门的位置
                surface = opposite.entity.surface,   -- 目标地表：设置为对侧传送门的地表
                zoom = current_zoom                  -- 缩放级别：设置为玩家当前的摄像头缩放级别
            })
        end

        -- 【重构】处理重命名逻辑
    elseif element_name == "chuansongmen_rename_button" then
        -- 调用函数切换到“编辑”视图
        GUI.build_edit_name_flow(frame.name_flow, my_data, player)
    elseif element_name == "chuansongmen_confirm_rename_button" then
        local textfield = frame.name_flow and frame.name_flow.chuansongmen_rename_textfield
        if not textfield then return end -- 安全检查

        local new_name_with_icon = textfield.text
        if new_name_with_icon and new_name_with_icon:match("%S") then -- 检查名称是否包含非空字符
            log_debug("传送门 GUI (handle_click): 玩家 " .. player.name .. " 确认修改。新字符串: '" .. new_name_with_icon .. "'")
            -- 调用后端函数进行更新 (新方案中后端会解析这个字符串)
            remote.call("zchuansongmen", "update_portal_details", player.index, my_data.id, new_name_with_icon)
        else
            player.print({ "messages.chuansongmen-error-name-cannot-be-empty" })
            -- 如果名称为空，则不提交任何修改，仅切换回显示视图
            GUI.build_display_name_flow(frame.name_flow, my_data)
        end
    elseif element_name == CybersynCompat.BUTTON_NAME then
        local is_paired = my_data.paired_to_id and State.get_opposite_struct(my_data)
        if not is_paired then
            player.print({ "messages.chuansongmen-error-cybersyn-unpaired" })
        else
            local new_state = not my_data.cybersyn_connected
            local opposite = State.get_opposite_struct(my_data)
            CybersynCompat.update_connection(my_data, opposite, new_state, player)
        end
        GUI.build_or_update(player, my_data.entity)
    end
end

function GUI.handle_checked_state_changed(event)
    if not (event.element and event.element.valid) then return end
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    if element_name == "chuansongmen_preview_checkbox" then
        local new_state = event.element.state
        storage.chuansongmen_player_settings[player.index].show_preview = new_state
        log_debug("传送门 GUI (handle_checked_state_changed): 预览复选框状态 -> " .. tostring(new_state))
        local entity = player.opened
        if entity and entity.valid then
            GUI.build_or_update(player, entity)
        end
    end
end

--- 【新增】处理回车键确认事件的函数
function GUI.handle_confirmed(event)
    if not (event.element and event.element.valid) then return end
    if event.element.name == "chuansongmen_rename_textfield" then
        local player = game.get_player(event.player_index)
        local frame = player.gui.relative.chuansongmen_main_frame
        if not frame then return end

        -- 伪造一个点击确认按钮的事件，并将其传递给 handle_click 函数进行统一处理
        local fake_event = {
            element = frame.name_flow.chuansongmen_confirm_rename_button,
            player_index = event.player_index
        }
        GUI.handle_click(fake_event)
    end
end

-- 【移除】handle_signal_selection 函数不再需要。

-- 导出模块
return GUI
