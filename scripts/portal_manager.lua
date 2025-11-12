-- /scripts/portal_manager.lua
-- 【传送门 Mod - 传送门管理器模块 v1.0】
-- 功能：集中管理传送门实体本身的生命周期，包括创建、销毁、配对和电网连接。
-- 设计原则：将对象管理逻辑内聚，与运行时的传送逻辑分离。

-- log("传送门 DEBUG (portal_manager.lua): 开始加载 portal_manager.lua ...") -- DEBUG: 确认文件被加载

local PortalManager = {}

-- =================================================================================
-- 模块本地变量 (用于存储依赖)
-- =================================================================================
-- 备注：这些变量将在 control.lua 中通过依赖注入进行初始化。
local State = nil
local GUI = nil
local Constants = nil
local Util = nil
local Chuansongmen = nil -- 用于访问 아직 남아있는 Chuansongmen 表中的函数
local log_debug = function() end

--- 依赖注入函数
function PortalManager.init(dependencies)
    State = dependencies.State
    GUI = dependencies.GUI
    Constants = dependencies.Constants
    Util = dependencies.Util
    Chuansongmen = dependencies.Chuansongmen
    log_debug = dependencies.log_debug
    if log_debug then
        log_debug("传送门 PortalManager 模块: 依赖注入成功。")
    end
end

-- =================================================================================
-- 内部实体设置
-- =================================================================================
-- 备注：从 control.lua 的 Chuansongmen.setup_internal_entities 移植。
-- 【v64 修正】固定内部实体的创建顺序以解决随机连接问题
function PortalManager.setup_internal_entities(struct)
    log_debug("传送门 DEBUG (setup_internal_entities): Function called. Struct ID: " .. (struct and struct.id or "N/A"))
    log_debug("传送门 DEBUG (setup_internal_entities): 开始为传送门 ID: " .. struct.id .. " 收集内部实体定义...")

    local entities_to_create = {} -- 用于收集所有待创建实体的列表
    local sub_entities = {}   -- 用于存储非特殊内部实体

    local se_direction
    if struct.direction == defines.direction.east or struct.direction == defines.direction.south then
        se_direction = defines.direction.east
    else
        se_direction = defines.direction.west
    end
    log_debug("传送门 DEBUG (setup_internal_entities): 实体方向: " ..
    struct.direction .. ", 映射到内部逻辑方向: " .. (se_direction == defines.direction.east and "east" or "west"))

    if not Constants.internals[se_direction] then
        log_debug("传送门 致命错误 (setup_internal_entities): 无法在 Constants.internals 中找到方向 " ..
        tostring(se_direction) .. " 的定义！")
        game.print("传送门 致命错误: 内部实体配置错误，请检查日志。")
        return
    end

    -- 1. 收集所有实体定义到一个列表中
    local entity_sets_to_process = { Constants.internals.shared, Constants.internals[se_direction] }
    for _, entity_set in pairs(entity_sets_to_process) do
        for proto_name, placements in pairs(entity_set) do
            for _, placement in pairs(placements) do
                table.insert(entities_to_create, {
                    name = proto_name,
                    position = Util.vectors_add(struct.position, placement.position),
                    direction = placement.direction,
                    force = struct.force_name
                })
            end
        end
    end
    log_debug("传送门 DEBUG (setup_internal_entities): 收集完毕，总计 " .. #entities_to_create .. " 个内部实体定义。")

    -- 2. 对列表进行排序 (按名称，然后按 x, y 坐标) 以确保顺序固定
    table.sort(entities_to_create, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        elseif a.position.x ~= b.position.x then
            return a.position.x < b.position.x
        else
            return a.position.y < b.position.y
        end
    end)
    log_debug("传送门 DEBUG (setup_internal_entities): 实体定义已排序。")

    -- 3. 按固定顺序创建实体
    log_debug("传送门 DEBUG (setup_internal_entities): 开始按固定顺序创建内部实体...")
    for i, creation_data in ipairs(entities_to_create) do
        log_debug("传送门 DEBUG (setup_internal_entities): 正在创建 [" ..
        i .. "/" .. #entities_to_create .. "]: " .. creation_data.name)
        local sub_entity = struct.surface.create_entity(creation_data)

        if not sub_entity then
            log_debug("传送门 致命错误 (setup_internal_entities): create_entity 失败！原型: " ..
            creation_data.name .. " 位置: " .. serpent.line(creation_data.position))
            game.print("传送门 致命错误: 内部实体创建失败！原型: " .. creation_data.name)
        else
            sub_entity.destructible = false
            -- 特殊实体处理
            if sub_entity.type == "train-stop" and sub_entity.name == "chuansongmen-train-stop" then
                log_debug("传送门 DEBUG (setup_internal_entities): 已创建 [train-stop], 存入 struct.station")
                sub_entity.backer_name = "[img=item/chuansongmen] " .. struct.name
                struct.station = sub_entity
            elseif sub_entity.name == "chuansongmen-energy-interface" then
                log_debug(
                "传送门 DEBUG (setup_internal_entities): 已创建 [energy-interface], 存入 struct.energy_interface_actual")
                struct.energy_interface_actual = sub_entity
                sub_entity.power_usage = 0
                sub_entity.energy = 0
            elseif sub_entity.type == "electric-pole" and sub_entity.name == "chuansongmen-energy-pole" then
                log_debug("传送门 DEBUG (setup_internal_entities): 已创建 [electric-pole], 存入 struct.electric_pole")
                struct.electric_pole = sub_entity
            elseif sub_entity.type == "power-switch" and sub_entity.name == "chuansongmen-power-switch" then
                log_debug("传送门 DEBUG (setup_internal_entities): 已创建 [power-switch], 存入 struct.power_switch")
                struct.power_switch = sub_entity
            else
                table.insert(sub_entities, sub_entity)
            end
        end
    end
    struct.sub_entities = sub_entities
    log_debug("传送门 DEBUG (setup_internal_entities): 普通内部实体 (轨道, 灯, 信号灯等) 创建完毕, 总数: " .. #sub_entities)

    -- 4. 创建碰撞器 (这个顺序不影响轨道连接)
    local collider_pos_offset = Constants.space_elevator_collider_position[se_direction]
    if not collider_pos_offset then
        log_debug("传送门 致命错误 (setup_internal_entities): 无法找到方向 " ..
        tostring(se_direction) .. " 的碰撞器位置 (collider_position)！")
    else
        log_debug("传送门 DEBUG (setup_internal_entities): 正在创建碰撞器 (chuansongmen-collider)...")
        struct.collider = struct.surface.create_entity { name = "chuansongmen-collider", position = Util.vectors_add(struct.position, collider_pos_offset), force = "neutral" }
        if struct.collider then
            log_debug("传送门 DEBUG (setup_internal_entities): 碰撞器创建成功。")
        else
            log_debug("传送门 错误 (setup_internal_entities): 碰撞器创建失败。")
        end
    end

    -- 5. 设置区域 (顺序不影响)
    local watch_rect = Constants.watch_rect_by_dir[se_direction]
    if watch_rect then
        struct.watch_area = { left_top = Util.vectors_add(struct.position, watch_rect.left_top), right_bottom = Util
        .vectors_add(struct.position, watch_rect.right_bottom) }
        log_debug("传送门 DEBUG (setup_internal_entities): watch_area 设置完毕。")
    else
        log_debug("传送门 错误 (setup_internal_entities): 无法设置 watch_area, 方向 " .. tostring(se_direction) .. " 定义缺失。")
    end

    local output_rect = Constants.output_area[se_direction]
    if output_rect then
        struct.output_area = { left_top = Util.vectors_add(struct.position, output_rect.left_top), right_bottom = Util
        .vectors_add(struct.position, output_rect.right_bottom) }
        log_debug("传送门 DEBUG (setup_internal_entities): output_area 设置完毕。")
    else
        log_debug("传送门 错误 (setup_internal_entities): 无法设置 output_area, 方向 " .. tostring(se_direction) .. " 定义缺失。")
    end

    log_debug("传送门 DEBUG (setup_internal_entities): setup_internal_entities 执行完毕。")
end

-- =================================================================================
-- 生命周期 (建造/拆除)
-- =================================================================================

--- 当传送门实体被建造时调用
-- 备注：从 control.lua 的 Chuansongmen.on_built 移植。
function PortalManager.on_built(entity)
    local id = MOD_DATA.next_id
    log_debug("传送门 DEBUG (on_built): 传送门被建造。新传送门 ID: " ..
    id .. ", 实体 unit_number: " .. entity.unit_number .. ", 名称: " .. entity.name)
    local struct = {
        id = id,
        name = tostring(id),
        entity = entity,
        unit_number = entity.unit_number,
        icon = { type = "item", name = "chuansongmen" }, -- 【新增】用于存储传送门的图标, 默认为传送门本身
        force_name = entity.force.name,
        surface = entity.surface,
        position = entity.position,
        direction = entity.direction,
        paired_to_id = nil,
        power_partner_id = nil,
        is_power_primary = false,
        -- =======================================================
        -- 【电网维持 - 状态机 v2.0】
        power_connection_status = "disconnected", -- "disconnected", "connected", "disconnected_by_system"
        power_grid_expires_at = 0,        -- 记录电网服务到期的游戏tick
        -- =======================================================
        cybersyn_connected = false,
        carriage_ahead = nil,
        carriage_behind = nil,
        lua_energy = 0,
        station = nil,
        power_switch = nil,
        electric_pole = nil,
        energy_interface_actual = nil,
        collider = nil,
        sub_entities = {},
        watch_area = nil,
        output_area = nil,
        carriage_ahead_manual_mode = false,
        old_train_speed = 0,
        carriage_ahead_current_stop = nil,
        saved_schedule_index = nil
    }
    PortalManager.setup_internal_entities(struct)
    if not struct.station or not struct.power_switch or not struct.electric_pole or not struct.energy_interface_actual then
        log_debug("传送门 致命错误 (on_built): setup_internal_entities 未能设置关键内部实体！传送门ID: " .. id)
        if not struct.station then log_debug("错误详情: station 为 nil") end
        if not struct.power_switch then log_debug("错误详情: power_switch 为 nil") end
        if not struct.electric_pole then log_debug("错误详情: electric_pole 为 nil") end
        if not struct.energy_interface_actual then log_debug("错误详情: energy_interface_actual 为 nil") end
        local player = game.get_player(entity.last_user)
        if player then player.print({ "messages.chuansongmen-error-internal-creation-failed" }) end
        MOD_DATA.portals[entity.unit_number] = struct
        MOD_DATA.next_id = id + 1
        log_debug("传送门 警告 (on_built): 关键内部实体创建失败，但仍尝试注册传送门 ID " .. id)
        return
    end

    log_debug("传送门 DEBUG (on_built): 内部实体创建成功。所有关键实体已链接。")
    MOD_DATA.portals[entity.unit_number] = struct
    MOD_DATA.next_id = id + 1
    log_debug("传送门 DEBUG (on_built): 传送门 ID " .. id .. " 已成功注册到全局表。")
end

--- 当传送门实体被拆除时调用
-- 备注：从 control.lua 的 Chuansongmen.on_mined 移植。
function PortalManager.on_mined(entity)
    log_debug("传送门 DEBUG (on_mined): 传送门被拆除/摧毁, 实体 unit_number: " .. entity.unit_number)
    local my_data = State.get_struct(entity)
    if my_data then
        log_debug("传送门 DEBUG (on_mined): 找到传送门数据, ID: " .. my_data.id .. ". 开始清理流程...")
        if my_data.paired_to_id then
            log_debug("传送门 DEBUG (on_mined): 此门已配对, 正在通知对侧解除配对...")
            local opposite = State.get_opposite_struct(my_data)
            if opposite then
                opposite.paired_to_id = nil
                log_debug("传送门 DEBUG (on_mined): 已通知对侧传送门 (ID: " .. opposite.id .. ") 解除传送配对。")
                for _, p in pairs(game.players) do
                    if p.opened == opposite.entity then GUI.build_or_update(p, opposite.entity) end
                end
            else
                log_debug("传送门 警告 (on_mined): 尝试通知对侧传送门 (ID: " .. my_data.paired_to_id .. ") 解除配对，但找不到有效的对侧结构。")
            end
            my_data.paired_to_id = nil
        end
        if my_data.power_partner_id then
            log_debug("传送门 DEBUG (on_mined): 此门已连接电网, 正在断开连接...")
            local power_partner = State.get_struct_by_id(my_data.power_partner_id)
            if power_partner then
                local primary_struct, secondary_struct = my_data.is_power_primary and { my_data, power_partner } or
                { power_partner, my_data }
                PortalManager.disconnect_wires(primary_struct, secondary_struct)
                power_partner.power_partner_id = nil
                power_partner.is_power_primary = false
                log_debug("传送门 DEBUG (on_mined): 已通知电网伙伴 (ID: " .. power_partner.id .. ") 断开连接。")
                for _, p in pairs(game.players) do
                    if p.opened == power_partner.entity then GUI.build_or_update(p, power_partner.entity) end
                end
            else
                log_debug("传送门 警告 (on_mined): 找不到有效的电网伙伴 (ID: " .. my_data.power_partner_id .. ") 来断开连接。")
            end
            my_data.power_partner_id = nil
            my_data.is_power_primary = false
        end
        log_debug("传送门 DEBUG (on_mined): 正在销毁内部实体...")
        if my_data.station and my_data.station.valid then my_data.station.destroy() end
        if my_data.power_switch and my_data.power_switch.valid then my_data.power_switch.destroy() end
        if my_data.electric_pole and my_data.electric_pole.valid then my_data.electric_pole.destroy() end
        if my_data.energy_interface_actual and my_data.energy_interface_actual.valid then my_data
                .energy_interface_actual.destroy() end
        if my_data.collider and my_data.collider.valid then my_data.collider.destroy() end
        if my_data.sub_entities then
            log_debug("传送门 DEBUG (on_mined): 正在销毁 " .. #my_data.sub_entities .. " 个 sub_entities (轨道, 灯等)...")
            for _, ent in pairs(my_data.sub_entities) do
                if ent and ent.valid then ent.destroy() end
            end
        end
        log_debug("传送门 DEBUG (on_mined): 内部实体销毁完毕。")
        MOD_DATA.portals[entity.unit_number] = nil
        log_debug("传送门 DEBUG (on_mined): 传送门 ID " .. my_data.id .. " 的数据已从全局表移除。清理流程结束。")
    else
        log_debug("传送门 警告 (on_mined): 尝试清理 unit_number 为 " .. entity.unit_number .. " 的传送门，但在全局表中未找到其数据。")
    end
end

-- =================================================================================
-- 配对与连接
-- =================================================================================

--- 连接两个传送门的电线
-- 备注：从 control.lua 的 Chuansongmen.connect_wires 移植。
function PortalManager.connect_wires(primary_struct, secondary_struct)
    log_debug("传送门 DEBUG (connect_wires): 正在连接电线: 主控ID " .. primary_struct.id .. " <-> 次控ID " .. secondary_struct.id)
    if primary_struct.power_switch and primary_struct.electric_pole and secondary_struct.electric_pole and primary_struct.power_switch.valid and primary_struct.electric_pole.valid and secondary_struct.electric_pole.valid then
        log_debug("传送门 DEBUG (connect_wires): 所有电网实体有效, 开始连接...")
        primary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true).connect_to(
        primary_struct.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_left_copper, true), false,
            defines.wire_origin.script)
        log_debug("传送门 DEBUG (connect_wires): 主控电线杆 -> 主控开关 (左侧铜线) 已连接。")
        secondary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true).connect_to(
        primary_struct.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_right_copper, true), false,
            defines.wire_origin.script)
        log_debug("传送门 DEBUG (connect_wires): 次控电线杆 -> 主控开关 (右侧铜线) 已连接。")
        primary_struct.power_switch.power_switch_state = true
        primary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
        secondary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true), false,
            defines.wire_origin.script)
        primary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(
        secondary_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true), false,
            defines.wire_origin.script)
        log_debug("传送门 DEBUG (connect_wires): 红绿电路网络线已连接, 开关已打开。")
    else
        log_debug("传送门 错误 (connect_wires): 连接失败, 缺少必要的电网实体或实体无效。")
        if not primary_struct.power_switch then log_debug("错误详情: 主控 (ID " .. primary_struct.id .. ") 缺少 power_switch") end
        if not primary_struct.electric_pole then log_debug("错误详情: 主控 (ID " .. primary_struct.id .. ") 缺少 electric_pole") end
        if not secondary_struct.electric_pole then log_debug("错误详情: 次控 (ID " ..
            secondary_struct.id .. ") 缺少 electric_pole") end
    end
end

--- 【恢复】断开两个传送门之间的电线连接 (只断开铜线)
-- 备注：此版本只断开电力连接，并保留电路网络信号传输。
function PortalManager.disconnect_wires(primary_struct, secondary_struct)
    log_debug("传送门 DEBUG (disconnect_wires): 正在断开电线: 主控ID " ..
    (primary_struct and primary_struct.id or "nil") .. ", 次控ID " .. (secondary_struct and secondary_struct.id or "nil"))
    if primary_struct and primary_struct.power_switch and primary_struct.power_switch.valid then
        -- 关闭电源开关
        primary_struct.power_switch.power_switch_state = false
        -- 断开开关两侧的铜线连接
        primary_struct.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_left_copper, true)
            .disconnect_all(defines.wire_origin.script)
        primary_struct.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_right_copper, true)
            .disconnect_all(defines.wire_origin.script)
        log_debug("传送门 DEBUG (disconnect_wires): 主控 (ID " .. primary_struct.id .. ") 的电源开关铜线已断开。")
    else
        log_debug("传送门 警告 (disconnect_wires): 尝试断开电线，但找不到有效的主控电源开关。")
    end
end

--- 远程接口 - 配对传送门
-- 备注：这是 remote.interface 中 pair_portals 的核心实现。
function PortalManager.pair_portals(player_index, portal_id, target_id)
    local player = game.get_player(player_index)
    log_debug("传送门 DEBUG (remote): 收到 pair_portals 调用, 玩家: " ..
    (player and player.name or "未知") .. ", portal_id: " .. tostring(portal_id) .. ", target_id: " .. tostring(target_id))
    if not (player and portal_id and target_id) then
        log_debug("传送门 错误 (remote pair_portals): 参数无效。"); return
    end

    local my_data = State.get_struct_by_id(portal_id)
    local target_struct = State.get_struct_by_id(target_id)

    if not (my_data and my_data.entity and my_data.entity.valid) then
        player.print({ "messages.chuansongmen-error-self-invalid" }); return
    end
    if not (target_struct and target_struct.entity and target_struct.entity.valid) then
        player.print({ "messages.chuansongmen-error-target-invalid" }); return
    end

    local is_compatible, reason = Chuansongmen.are_directions_compatible(my_data.entity.direction,
        target_struct.entity.direction)
    if not is_compatible then
        player.print({ "messages.chuansongmen-error-direction-mismatch-rich" })
        log_debug("传送门 警告 (pair_portals): ID " ..
        my_data.id .. " 和 ID " .. target_struct.id .. " 方向不兼容 (" .. reason .. ")，配对被取消。")
        return
    end

    if target_struct.paired_to_id then
        player.print({ "messages.chuansongmen-error-target-already-paired" }); return
    end
    if my_data.paired_to_id then
        player.print({ "messages.chuansongmen-error-self-already-paired" }); return
    end

    my_data.paired_to_id = target_id
    target_struct.paired_to_id = my_data.id
    log_debug("传送门 DEBUG (remote pair_portals): 传送配对成功: " .. portal_id .. " <-> " .. target_id)

    local primary_struct, secondary_struct
    if my_data.id < target_struct.id then
        primary_struct = my_data
        secondary_struct = target_struct
        my_data.is_power_primary = true
        target_struct.is_power_primary = false
    else
        primary_struct = target_struct
        secondary_struct = my_data
        my_data.is_power_primary = false
        target_struct.is_power_primary = true
    end
    my_data.power_partner_id = target_struct.id
    target_struct.power_partner_id = my_data.id

    -- =======================================================
    -- 【核心修改】根据游戏模式决定电网连接行为
    -- =======================================================
    local resource_cost_enabled = settings.startup["chuansongmen-enable-resource-cost"] and
    settings.startup["chuansongmen-enable-resource-cost"].value or false

    if not resource_cost_enabled then
        -- 无消耗模式：自动连接电网
        log_debug("传送门 DEBUG (remote pair_portals): 检测到 [无消耗] 模式，正在自动连接电网...")
        PortalManager.connect_wires(primary_struct, secondary_struct)
        -- 【核心修复】设置正确的状态字段
        my_data.power_connection_status = "connected"
        target_struct.power_connection_status = "connected"
        log_debug("传送门 DEBUG (remote pair_portals): 电网状态已更新 (power_connection_status = 'connected')。主控 ID: " ..
        primary_struct.id)
        player.print({ "messages.chuansongmen-pair-success", my_data.name, target_struct.name })
        player.print({ "messages.chuansongmen-power-auto-connected", primary_struct.name, primary_struct.id })
    else
        -- 有消耗模式：不自动连接，等待玩家手动操作
        log_debug("传送门 DEBUG (remote pair_portals): 检测到 [有消耗] 模式，电网等待手动连接。")
        my_data.power_connected = false
        target_struct.power_connected = false
        log_debug("传送门 DEBUG (remote pair_portals): 电网状态保持不变 (power_connected = false)。")
        player.print({ "messages.chuansongmen-pair-success", my_data.name, target_struct.name })
        player.print({ "messages.chuansongmen-pair-success-manual-power" })
    end
    -- =======================================================

    if player.opened == my_data.entity then GUI.build_or_update(player, my_data.entity) end
    for _, p in pairs(game.players) do
        if p.opened == target_struct.entity then GUI.build_or_update(p, target_struct.entity) end
        if p.opened == my_data.entity and p ~= player then GUI.build_or_update(p, my_data.entity) end
    end
    log_debug("传送门 DEBUG (remote pair_portals): 相关 GUI 已更新。")
end

--- 远程接口 - 解除传送门配对
-- 备注：这是 remote.interface 中 unpair_portals 的核心实现。
function PortalManager.unpair_portals(player_index, portal_id)
    local player = game.get_player(player_index)
    log_debug("传送门 DEBUG (remote): 收到 unpair_portals 调用, 玩家: " ..
    (player and player.name or "未知") .. ", portal_id: " .. tostring(portal_id))
    if not (player and portal_id) then return end

    local my_data = State.get_struct_by_id(portal_id)
    if not my_data then return end

    if my_data.paired_to_id then
        log_debug("传送门 DEBUG (remote unpair_portals): 正在解除传送门 ID " .. my_data.id .. " 的配对...")
        local opposite = State.get_opposite_struct(my_data)
        if opposite then
            opposite.paired_to_id = nil
            log_debug("传送门 DEBUG (remote unpair_portals): 对侧传送门 (ID: " .. opposite.id .. ") 的配对已清除。")
        end
        my_data.paired_to_id = nil
        player.print({ "messages.chuansongmen-unpair-success", my_data.name })

        -- =======================================================
        -- 【核心修改】使用 power_connected 作为判断依据来断开电网
        -- =======================================================
        if my_data.power_connected then
            log_debug("传送门 DEBUG (remote unpair_portals): 检测到电网已连接 (power_connected=true)，正在断开...")
            local power_partner = opposite or State.get_struct_by_id(my_data.power_partner_id)
            if power_partner then
                -- =======================================================
                -- 【关键修复】将修复应用到此函数，解决解除配对时断开无效的问题
                local primary_struct, secondary_struct
                if my_data.is_power_primary then
                    primary_struct = my_data
                    secondary_struct = power_partner
                else
                    primary_struct = power_partner
                    secondary_struct = my_data
                end
                -- =======================================================
                PortalManager.disconnect_wires(primary_struct, secondary_struct)
                power_partner.power_connected = false -- 确保对侧状态也更新
                log_debug("传送门 DEBUG (remote unpair_portals): 对侧电网状态已更新 (power_connected=false)。ID: " .. power_partner
                .id)
            end
            my_data.power_connected = false
            player.print({ "messages.chuansongmen-power-disconnected" })
            log_debug("传送门 DEBUG (remote unpair_portals): 本地电网状态已更新 (power_connected=false)。")
        end
        -- =======================================================

        -- 无论电网是否连接，都需要清理伙伴关系和主控状态
        if my_data.power_partner_id then
            log_debug("传送门 DEBUG (remote unpair_portals): 正在清理电网伙伴关系...")
            local power_partner = opposite or State.get_struct_by_id(my_data.power_partner_id)
            if power_partner then
                power_partner.power_partner_id = nil
                power_partner.is_power_primary = false
            end
            my_data.power_partner_id = nil
            my_data.is_power_primary = false
            log_debug("传送门 DEBUG (remote unpair_portals): 电网伙伴关系清理完毕。")
        end

        if player.opened == my_data.entity then GUI.build_or_update(player, my_data.entity) end
        if opposite then
            for _, p in pairs(game.players) do
                if p.opened == opposite.entity then GUI.build_or_update(p, opposite.entity) end
            end
        end
        log_debug("传送门 DEBUG (remote unpair_portals): 解除配对完成，相关 GUI 已更新。")
    else
        log_debug("传送门 DEBUG (remote unpair_portals): 传送门 ID " .. my_data.id .. " 本身未配对，无需操作。")
        player.print({ "messages.chuansongmen-not-paired" })
    end
end

--- 【重构 v2】远程接口 - 更新传送门的名称和图标
-- 备注：此版本接收一个由 textfield (icon_selector=true) 生成的单一字符串，并从中解析出图标和名称。
-- @param new_name_with_icon string: 一个可能包含富文本的字符串, e.g., "[item=iron-plate] 铁板专线" 或 "普通名称"
function PortalManager.update_portal_details(player_index, portal_id, new_name_with_icon)
    local player = game.get_player(player_index)
    if not (player and portal_id and new_name_with_icon and new_name_with_icon:match("%S")) then
        -- 如果传入的名称为空或只有空格，则不做任何事
        return
    end

    local my_data = State.get_struct_by_id(portal_id)
    if not my_data then return end

    -- 步骤 1: 解析传入的字符串，分离图标和纯文本名称
    local icon_type, icon_name, plain_name = string.match(new_name_with_icon, "%[([%w%-]+)=([%w%-]+)%]%s*(.*)")

    if icon_type and icon_name then
        -- 情况 A: 字符串中包含图标, e.g., "[item=iron-plate] 铁板专线"
        my_data.icon = { type = icon_type, name = icon_name }
        my_data.name = plain_name
        log_debug("传送门 PortalManager: 解析成功。新图标: {type='" ..
        icon_type .. "', name='" .. icon_name .. "'}, 新名称: '" .. plain_name .. "'")
    else
        -- 情况 B: 字符串中不包含图标, e.g., "普通名称"
        -- 在这种情况下，我们只更新名称，保持图标不变。
        my_data.name = new_name_with_icon
        log_debug("传送门 PortalManager: 解析为纯文本。新名称: '" .. my_data.name .. "' (图标保持不变)")
    end

    -- 步骤 2: 更新内部火车站的名称 (backer_name)，实现 SE 风格的命名 (此逻辑保持不变)
    if my_data.station and my_data.station.valid then
        local default_icon_richtext = "[item=chuansongmen]"
        local player_icon_richtext = Util.signal_to_richtext(my_data.icon)

        local final_backer_name
        if player_icon_richtext ~= default_icon_richtext then
            final_backer_name = default_icon_richtext .. " " .. player_icon_richtext .. " " .. my_data.name
        else
            final_backer_name = default_icon_richtext .. " " .. my_data.name
        end

        my_data.station.backer_name = final_backer_name
        log_debug("传送门 PortalManager: 内部车站名称已更新为: " .. final_backer_name)
    end

    -- 步骤 3: 刷新所有可能相关的玩家GUI (此逻辑保持不变)
    if player.opened == my_data.entity then
        GUI.build_or_update(player, my_data.entity)
    end
    for _, p in pairs(game.players) do
        if p ~= player and p.opened == my_data.entity then
            GUI.build_or_update(p, my_data.entity)
        end
        local opposite = State.get_opposite_struct(my_data)
        if opposite and p.opened == opposite.entity then
            GUI.build_or_update(p, opposite.entity)
        end
    end
    log_debug("传送门 PortalManager: 相关玩家的 GUI 已刷新。")
end

-- =================================================================================
-- 新增：手动电网控制
-- =================================================================================

--- 【重写】外部调用：连接两个已配对传送门的电网 (实现双向、同步的预付费逻辑)
-- @param player LuaPlayer: 发起操作的玩家
-- @param portal_id number: 玩家正在操作的传送门的ID
function PortalManager.connect_portal_power(player, portal_id)
    log_debug("传送门 DEBUG (connect_portal_power): 玩家 " .. player.name .. " 请求连接电网，传送门ID: " .. portal_id)
    local my_data = State.get_struct_by_id(portal_id)
    if not my_data then return end

    local opposite = State.get_opposite_struct(my_data)
    if not opposite then
        player.print({ "messages.chuansongmen-error-no-opposite-found" }); return
    end
    if my_data.power_connection_status == "connected" then
        player.print({ "messages.chuansongmen-info-power-already-connected" }); return
    end

    -- =======================================================
    -- 【无消耗模式 - 逻辑修复】
    -- 为无消耗模式提供一个不消耗碎片的“绿色通道”
    -- =======================================================
    local resource_cost_enabled = settings.startup["chuansongmen-enable-resource-cost"] and
    settings.startup["chuansongmen-enable-resource-cost"].value or false
    if not resource_cost_enabled then
        log_debug("传送门 DEBUG (connect_portal_power): [无消耗模式] 玩家手动重连电网。")
        my_data.power_connection_status = "connected"
        opposite.power_connection_status = "connected"

        -- 【最终崩溃修复】应用我们已验证的、绝对安全的if/else结构
        local primary_struct, secondary_struct
        if my_data.is_power_primary then
            primary_struct = my_data
            secondary_struct = opposite
        else
            primary_struct = opposite
            secondary_struct = my_data
        end
        PortalManager.connect_wires(primary_struct, secondary_struct)

        player.print({ "messages.chuansongmen-power-reconnected" }) -- 使用本地化
        -- 刷新GUI并提前退出函数
        for _, p in pairs(game.players) do
            if p.opened and (p.opened == my_data.entity or p.opened == opposite.entity) then
                GUI.build_or_update(p, p.opened)
            end
        end
        return
    end
    -- =======================================================

    -- 【核心修改】双向检查和消耗逻辑
    local inv_A = my_data.entity.get_inventory(defines.inventory.assembling_machine_input)
    local inv_B = opposite.entity.get_inventory(defines.inventory.assembling_machine_input)
    local count_A = inv_A and inv_A.get_item_count("chuansongmen-spacetime-shard") or 0
    local count_B = inv_B and inv_B.get_item_count("chuansongmen-spacetime-shard") or 0

    -- 启动电网需要2个碎片
    if (count_A + count_B) < 2 then
        player.print({ "messages.chuansongmen-error-power-not-enough-shards-start" })
        log_debug("传送门 DEBUG (connect_portal_power): 连接失败，网络中碎片总数 (" .. (count_A + count_B) .. ") 不足2个。")
        return
    end

    -- 智能消耗2个碎片
    if count_A > 0 then inv_A.remove({ name = "chuansongmen-spacetime-shard", count = 1 }) else inv_B.remove({ name =
        "chuansongmen-spacetime-shard", count = 1 }) end
    if count_B > 0 then inv_B.remove({ name = "chuansongmen-spacetime-shard", count = 1 }) else inv_A.remove({ name =
        "chuansongmen-spacetime-shard", count = 1 }) end
    log_debug("传送门 DEBUG (connect_portal_power): 成功消耗2个启动碎片。")

    -- 设置状态为“已连接”
    my_data.power_connection_status = "connected"
    opposite.power_connection_status = "connected"

    -- 从Mod设置中读取持续时间
    local duration_in_minutes = settings.global["chuansongmen-power-grid-duration"].value
    local duration_in_ticks = duration_in_minutes * 60 * 60

    -- 设置统一的到期时间
    local expires_at = game.tick + duration_in_ticks
    my_data.power_grid_expires_at = expires_at
    opposite.power_grid_expires_at = expires_at

    -- 连接电线
    -- =======================================================
    -- 【最终崩溃修复】应用之前已验证的、绝对安全的if/else结构
    -- 彻底根除因疏忽而反复出现的nil值bug
    local primary_struct, secondary_struct
    if my_data.is_power_primary then
        primary_struct = my_data
        secondary_struct = opposite
    else
        primary_struct = opposite
        secondary_struct = my_data
    end
    -- =======================================================
    PortalManager.connect_wires(primary_struct, secondary_struct)

    log_debug("传送门 DEBUG (connect_portal_power): 电网连接成功。ID: " ..
    my_data.id .. " <-> " .. opposite.id .. "。服务到期tick: " .. expires_at)
    player.print({ "messages.chuansongmen-power-connected-simple" })

    -- 刷新所有相关GUI
    for _, p in pairs(game.players) do
        if p.opened and (p.opened == my_data.entity or p.opened == opposite.entity) then
            GUI.build_or_update(p, p.opened)
        end
    end
end

--- 【重写】外部调用：断开两个已配对传送门的电网 (并根据调用者设置不同状态)
-- @param player LuaPlayer: 发起操作的玩家, 可以为nil (当脚本自动断开时)
-- @param portal_id number: 任何一侧传送门的ID
function PortalManager.disconnect_portal_power(player, portal_id)
    local my_data = State.get_struct_by_id(portal_id)
    if not my_data then return end

    -- 检查是否真的需要断开
    if my_data.power_connection_status == "disconnected" then
        if player then player.print({ "messages.chuansongmen-info-power-already-disconnected" }); end
        return
    end

    local opposite = State.get_opposite_struct(my_data)
    if not opposite then return end -- 如果对侧无效，也无法进行操作

    log_debug("传送门 DEBUG (disconnect_portal_power): 正在断开电网，传送门ID: " .. portal_id)

    -- 【核心修改】根据调用者，设置不同的断开状态
    if player then
        -- 玩家手动断开，设置为“完全断开”
        my_data.power_connection_status = "disconnected"
        opposite.power_connection_status = "disconnected"
        log_debug("传送门 DEBUG (disconnect_portal_power): 玩家手动断开，状态设置为 'disconnected'。")
    else
        -- 系统自动断开，设置为“待机/等待自动重连”
        my_data.power_connection_status = "disconnected_by_system"
        opposite.power_connection_status = "disconnected_by_system"
        log_debug("传送门 DEBUG (disconnect_portal_power): 系统自动断开，状态设置为 'disconnected_by_system'。")
    end

    my_data.power_grid_expires_at = 0
    opposite.power_grid_expires_at = 0

    -- 断开电线
    -- =======================================================
    -- 【关键修复】使用我们已验证过的、绝对安全的if/else结构
    -- 来替换有问题的单行赋值语句，以修复参数为nil的bug
    local primary_struct, secondary_struct
    if my_data.is_power_primary then
        primary_struct = my_data
        secondary_struct = opposite
    else
        primary_struct = opposite
        secondary_struct = my_data
    end
    -- =======================================================
    PortalManager.disconnect_wires(primary_struct, secondary_struct)

    log_debug("传送门 DEBUG (disconnect_portal_power): 电网断开成功。ID: " .. my_data.id .. " <-> " .. opposite.id .. "。状态已重置。")
    if player then player.print({ "messages.chuansongmen-power-disconnected" }); end

    -- 刷新所有可能打开了相关GUI的玩家界面
    for _, p in pairs(game.players) do
        if p.opened and (p.opened == my_data.entity or p.opened == opposite.entity) then
            GUI.build_or_update(p, p.opened)
        end
    end
end

-- 导出模块
return PortalManager
