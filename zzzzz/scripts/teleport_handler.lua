-- /scripts/teleport_handler.lua
-- 【传送门 Mod - 传送处理器模块 v1.1】
-- 功能：处理火车传送的完整运行时逻辑，包括检测、内容转移、状态恢复和速度同步。
-- 设计原则：将复杂的、动态的传送过程与静态的对象管理逻辑分离。

local TeleportHandler = {}

-- =================================================================================
-- 模块本地变量 (用于存储依赖)
-- =================================================================================
local Constants = nil
local State = nil
local Util = nil
local ScheduleHandler = nil
local Chuansongmen = nil
local log_debug = function() end
local SE_TELEPORT_STARTED_EVENT_ID = nil
local SE_TELEPORT_FINISHED_EVENT_ID = nil

--- 【新功能 新增】辅助函数，用于检查资源消耗模式是否启用
local function is_resource_cost_enabled()
    -- 使用安全的短路求值方式读取设置
    return settings.startup["chuansongmen-enable-resource-cost"]
        and settings.startup["chuansongmen-enable-resource-cost"].value
        or false
end

--- 依赖注入函数
function TeleportHandler.init(dependencies)
    Constants = dependencies.Constants
    State = dependencies.State
    Util = dependencies.Util
    ScheduleHandler = dependencies.ScheduleHandler
    Chuansongmen = dependencies.Chuansongmen
    log_debug = dependencies.log_debug
    SE_TELEPORT_STARTED_EVENT_ID = dependencies.SE_TELEPORT_STARTED_EVENT_ID
    SE_TELEPORT_FINISHED_EVENT_ID = dependencies.SE_TELEPORT_FINISHED_EVENT_ID
    if log_debug then
        log_debug("传送门 TeleportHandler 模块: 依赖注入成功。")
    end
end

-- =================================================================================
-- Cybersyn 兼容性补丁 (核心新增部分)
-- =================================================================================

-- 【新功能】在无 SE 环境下，手动迁移 Cybersyn 数据并补全时刻表
-- 修改说明：增加了 snapshot 参数，直接使用传送前保存的数据快照
local function handle_cybersyn_migration(old_train_id, new_train, snapshot)
    if script.active_mods["space-exploration"] then
        return
    end

    -- 核心修改：直接检查快照是否存在
    local c_train = snapshot
    if not c_train then
        log_debug(
            "传送门 Cybersyn 兼容: 未提供数据快照 (可能是非 Cybersyn 列车或读取失败)，跳过迁移。"
        )
        return
    end

    log_debug(
        "传送门 Cybersyn 兼容: [无SE模式] 开始为火车 "
        .. new_train.id
        .. " (旧ID: "
        .. old_train_id
        .. ") 注入快照数据..."
    )

    -- 1. 核心迁移：更新实体引用并搬家
    -- 必须更新 entity 引用，否则 Cybersyn 会操作已销毁的实体
    c_train.entity = new_train

    -- 将数据写入新 ID 的位置
    if remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"] then
        remote.call("cybersyn", "write_global", c_train, "trains", new_train.id)

        -- 清除旧 ID 的数据 (虽然 Cybersyn 可能已经删了，但为了保险再写一次 nil)
        remote.call("cybersyn", "write_global", nil, "trains", old_train_id)

        -- >>>>> [新增：强制清除标签并验证] >>>>>
        -- 1. 显式调用接口，定位到具体字段进行删除 (置为 nil)
        remote.call("cybersyn", "write_global", nil, "trains", new_train.id, "se_is_being_teleported")

        -- 2. 立即读取验证，并在游戏内报告结果
        local _, check_val =
            pcall(remote.call, "cybersyn", "read_global", "trains", new_train.id, "se_is_being_teleported")
        if check_val == nil then
            -- game.print(">>> [传送门] ID: " .. new_train.id .. " 标签清除成功 (当前状态: nil)。")
        else
            -- game.print(">>> [传送门] ID: " .. new_train.id .. " 标签清除失败！(当前状态: " .. tostring(check_val) .. ")")
        end
        -- <<<<< [新增结束] <<<<<
    end

    log_debug("传送门 Cybersyn 兼容: 数据注入完成。")

    -- 2. 时刻表补全 (Rail Patch)
    local schedule = new_train.schedule
    if schedule and schedule.records then
        local records = schedule.records
        local current_index = schedule.current
        local current_record = records[current_index]

        if current_record and current_record.station then
            -- 尝试从快照获取目标站点信息
            local target_station_id = nil
            -- 状态修正：1=TO_P, 3=TO_R, 5=TO_D, 6=TO_D_BYPASS (关键修复)
            if c_train.status == 1 then
                target_station_id = c_train.p_station_id
            end
            if c_train.status == 3 then
                target_station_id = c_train.r_station_id
            end
            if c_train.status == 5 or c_train.status == 6 then
                target_station_id = c_train.depot_id
                log_debug(
                    "传送门 Cybersyn 兼容: 检测到回车库状态 ("
                    .. c_train.status
                    .. ")，准备补全 Rail。"
                )
            end

            if target_station_id then
                local st_data = nil
                -- 区分读取：状态 5/6 读 depots 表，其他读 stations 表
                if c_train.status == 5 or c_train.status == 6 then
                    st_data = remote.call("cybersyn", "read_global", "depots", target_station_id)
                else
                    st_data = remote.call("cybersyn", "read_global", "stations", target_station_id)
                end
                if st_data and st_data.entity_stop and st_data.entity_stop.valid then
                    local rail = st_data.entity_stop.connected_rail

                    -- 检查是否在新地表
                    if rail and rail.surface == new_train.front_stock.surface then
                        log_debug("传送门 Cybersyn 兼容: [Rail Patch] 正在插入 Rail 导航记录...")

                        table.insert(records, current_index, {
                            rail = rail,
                            rail_direction = st_data.entity_stop.connected_rail_direction,
                            temporary = true,
                            wait_conditions = { { type = "time", ticks = 1 } },
                        })

                        schedule.records = records
                        new_train.schedule = schedule

                        log_debug("传送门 Cybersyn 兼容: 时刻表补全成功！")
                    else
                        log_debug(
                            "传送门 Cybersyn 兼容: 警告 - 目标铁轨不在当前地表，无法补全。"
                        )
                    end
                end
            end
        end
    end
end

-- =================================================================================
-- 火车传送核心逻辑
-- =================================================================================

--- 内容转移
function TeleportHandler.carriage_transfer_contents(carriage, new_carriage)
    log_debug(
        "传送门 DEBUG (carriage_transfer_contents): 正在从 "
        .. carriage.name
        .. " (旧 unit_number: "
        .. carriage.unit_number
        .. ") 复制内容到 "
        .. new_carriage.name
        .. " (新 unit_number: "
        .. new_carriage.unit_number
        .. ")"
    )
    Util.transfer_equipment_grid(carriage, new_carriage)
    log_debug("传送门 DEBUG (carriage_transfer_contents): 装备网格已转移。")
    Util.transfer_all_inventories(carriage, new_carriage, false)
    log_debug("传送门 DEBUG (carriage_transfer_contents): 所有物品栏已转移。")
    if carriage.type == "fluid-wagon" then
        Util.transfer_fluids(carriage, new_carriage)
        log_debug("传送门 DEBUG (carriage_transfer_contents): 流体内容已转移。")
    end
    if carriage.type == "cargo-wagon" then
        Util.transfer_inventory_filters(carriage, new_carriage, defines.inventory.cargo_wagon)
        log_debug("传送门 DEBUG (carriage_transfer_contents): 货运车厢过滤器已转移。")
    elseif carriage.type == "artillery-wagon" then
        Util.transfer_inventory_filters(carriage, new_carriage, defines.inventory.artillery_wagon_ammo)
        log_debug("传送门 DEBUG (carriage_transfer_contents): 火炮车厢过滤器已转移。")
    end
    new_carriage.backer_name = carriage.backer_name or ""
    new_carriage.health = carriage.health
    if carriage.color and new_carriage.color then
        new_carriage.color = carriage.color
    end
    local driver = carriage.get_driver()
    if driver then
        log_debug("传送门 DEBUG (carriage_transfer_contents): 检测到司机/乘客, 正在尝试传送...")
        carriage.set_driver(nil)
        if driver.object_name == "LuaPlayer" then
            new_carriage.set_driver(driver)
            log_debug("传送门 DEBUG (carriage_transfer_contents): 玩家司机已转移。")
        else
            if driver.teleport then
                driver.teleport(new_carriage.position, new_carriage.surface)
                new_carriage.set_driver(driver)
                log_debug("传送门 DEBUG (carriage_transfer_contents): 非玩家司机已传送并转移。")
            else
                log_debug(
                    "传送门 警告 (carriage_transfer_contents): 无法传送非玩家司机 (类型: "
                    .. driver.type
                    .. ")，司机将留在原地。"
                )
            end
        end
    end
    log_debug("传送门 DEBUG (carriage_transfer_contents): 内容复制完成。")
end

--- 传送结束 (修复版：发送方持有状态)
function TeleportHandler.finish_teleport(struct)
    --  FOR ID: " .. tostring(struct and struct.id))
    -- [关键修复] 在函数内部重新、可靠地获取对侧实体 (仅用于获取位置或触发事件)
    local opposite_struct = State.get_opposite_struct(struct)

    -- 日志修正
    if opposite_struct then
        log_debug(
            "传送门 DEBUG (finish_teleport): 火车传送完毕, 开始清理状态。源ID: "
            .. struct.id
            .. ", 目标ID: "
            .. opposite_struct.id
        )
    else
        log_debug(
            "传送门 DEBUG (finish_teleport): 火车传送完毕, 开始清理状态。源ID: "
            .. struct.id
            .. " (对侧无效)"
        )
    end

    -- 1. 销毁最后的拖船
    -- [修改] 拖船现在记录在发送方 struct.tug 上
    if struct.tug and struct.tug.valid then
        struct.tug.destroy()
        struct.tug = nil
        log_debug("传送门 DEBUG (finish_teleport): [Tug] 最后的拖船已销毁。")
    end

    -- 2. 恢复火车状态
    -- [修改] 远端车头现在记录在发送方 struct.carriage_ahead 上
    local final_train = struct.carriage_ahead and struct.carriage_ahead.valid and struct.carriage_ahead.train

    if final_train and final_train.valid then
        log_debug(
            "传送门 DEBUG (finish_teleport): 找到最终火车 (ID: "
            .. final_train.id
            .. "), 开始恢复状态。"
        )

        -- [修改] 从 struct 读取保存的索引
        if struct.saved_schedule_index then
            final_train.go_to_station(struct.saved_schedule_index)
            log_debug(
                "传送门 DEBUG (finish_teleport): [时刻表修复] 已将时刻表指针拨动到已保存的索引: "
                .. struct.saved_schedule_index
            )
        end

        -- 3. 恢复模式和速度
        -- [修改] 从 struct 读取保存的模式和速度
        final_train.manual_mode = struct.saved_manual_mode or false

        -- SE 风格速度恢复：切回自动后立即应用速度
        if struct.old_train_speed and opposite_struct then
            local speed_direction = Chuansongmen.elevator_east_sign(opposite_struct)
                * Chuansongmen.carriage_east_sign(struct.carriage_ahead)
                * Chuansongmen.train_forward_sign(struct.carriage_ahead)
            final_train.speed = speed_direction * math.abs(struct.old_train_speed)
        end

        -- 4. Cybersyn 迁移
        -- [修改] 从 struct 读取快照
        if struct.old_train_id then
            handle_cybersyn_migration(struct.old_train_id, final_train, struct.cybersyn_snapshot)
            struct.cybersyn_snapshot = nil
        end

        log_debug(
            "传送门 DEBUG (finish_teleport): 状态恢复完毕。模式: "
            .. (final_train.manual_mode and "手动" or "自动")
            .. ", 速度: "
            .. final_train.speed
        )

        -- [新增] SE 完成事件触发
        if struct.old_train_id and SE_TELEPORT_FINISHED_EVENT_ID and opposite_struct then
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id_1 = struct.old_train_id,
                old_surface_index = struct.surface.index,
                teleporter = opposite_struct.entity, -- 注意：触发点是出口实体
            })
        end
    else
        log_debug("传送门 警告 (finish_teleport): 找不到有效的最终火车进行状态恢复。")
    end

    -- 5. 清理所有状态变量
    -- [关键修改] 只清理 struct 自身的状态，绝对不碰 opposite_struct
    -- 这样避免了误删正在反向传送的任务状态
    struct.carriage_behind = nil
    struct.carriage_ahead = nil
    struct.tug = nil
    struct.is_teleporting = false

    struct.saved_schedule_index = nil
    struct.saved_manual_mode = nil
    struct.old_train_speed = nil
    struct.old_train_id = nil

    -- [优化] 将自己移出活跃列表
    if storage.active_teleporters then
        storage.active_teleporters[struct.unit_number] = nil
    end

    log_debug("传送门 DEBUG (finish_teleport): ID " .. struct.id .. " 传送结束，进入休眠。")
end

--- 传送下一节车厢 (修复版：红绿灯逻辑支持)
function TeleportHandler.teleport_next(struct)
    -- [修正] 自己获取对侧实体，不再依赖外部传入
    local opposite = State.get_opposite_struct(struct)
    if not opposite then
        log_debug("传送门 DEBUG (teleport_next): 传送门 " .. struct.id .. " 未找到配对，中断传送。")
        TeleportHandler.finish_teleport(struct)
        return
    end

    -- 检查入口车厢是否依然有效
    if
        not (
            struct.carriage_behind
            and struct.carriage_behind.valid
            and struct.carriage_behind.surface == struct.surface
        )
    then
        log_debug("传送门 DEBUG (teleport_next): 入口待传送车厢已失效，传送序列终止。")
        TeleportHandler.finish_teleport(struct)
        return
    end

    local carriage = struct.carriage_behind
    if not (carriage.train and carriage.train.valid) then
        log_debug("传送门 警告 (teleport_next): 待传送车厢或其火车无效，中断传送。")
        TeleportHandler.finish_teleport(struct)
        return
    end

    -- 读取 struct.carriage_ahead (远端已传过去的车)
    local carriage_ahead = struct.carriage_ahead

    local se_direction = (opposite.direction == defines.direction.east or opposite.direction == defines.direction.south)
        and defines.direction.east
        or defines.direction.west
    local spawn_pos = Util.vectors_add(opposite.position, Constants.output_pos[se_direction])

    local can_place = opposite.surface.can_place_entity({
        name = carriage.name,
        position = spawn_pos,
        direction = defines.direction.south,
        force = carriage.force,
    })

    -- 堵塞检查：如果是第一节车 (carriage_ahead 为空)，检查出口区域
    local is_clear = not carriage_ahead
        and opposite.surface.count_entities_filtered({
            type = Constants.stock_types,
            area = opposite.output_area,
            limit = 1,
        })
        == 0

    if can_place and (carriage_ahead or is_clear) then
        log_debug(
            "传送门 DEBUG (teleport_next): 传送门 " .. struct.id .. " 正在传送车厢: " .. carriage.name
        )

        local next_carriage = carriage.get_connected_rolling_stock(defines.rail_direction.front)
            or carriage.get_connected_rolling_stock(defines.rail_direction.back)

        -- 如果是第一节车，保存状态到 struct
        if not carriage_ahead then
            struct.saved_manual_mode = carriage.train.manual_mode
            struct.old_train_speed = carriage.train.speed
            struct.old_train_id = carriage.train.id

            if remote.interfaces["cybersyn"] then
                remote.call("cybersyn", "write_global", true, "trains", carriage.train.id, "se_is_being_teleported")
                local status, c_data = pcall(remote.call, "cybersyn", "read_global", "trains", carriage.train.id)
                if status and c_data then
                    log_debug(
                        "传送门 Cybersyn 兼容: 已捕获旧火车 (ID: "
                        .. carriage.train.id
                        .. ") 的数据快照。"
                    )
                    struct.cybersyn_snapshot = c_data
                end
            end
            log_debug(
                "传送门 DEBUG (teleport_next): [状态保存] 已保存火车状态。速度: "
                .. struct.old_train_speed
            )
        end

        -- 销毁旧拖船 (从 struct 获取)
        if struct.tug and struct.tug.valid then
            struct.tug.destroy()
            struct.tug = nil
            log_debug("传送门 DEBUG (teleport_next): [Tug] 旧拖船已销毁。")
        end

        local spawn_dir = carriage.orientation > 0.5 and defines.direction.south or defines.direction.north
        local new_carriage = opposite.surface.create_entity({
            name = carriage.name,
            position = spawn_pos,
            direction = spawn_dir,
            force = carriage.force,
        })

        if not new_carriage then
            log_debug("传送门 致命错误 (teleport_next): 无法在出口创建新车厢！")
            TeleportHandler.finish_teleport(struct)
            return
        end

        log_debug("传送门 DEBUG (teleport_next): 新车厢 " .. new_carriage.name .. " 创建成功。")
        TeleportHandler.carriage_transfer_contents(carriage, new_carriage)

        -- 如果是第一节车，转移时刻表并保存索引到 struct
        if not carriage_ahead then
            log_debug("传送门 DEBUG (teleport_next): [时刻表] 调用 ScheduleHandler 进行智能设定...")
            ScheduleHandler.transfer_schedule(carriage.train, new_carriage.train, struct.station.backer_name)

            -- [新增关键逻辑] 抵消 go_to_station 的副作用
            -- transfer_schedule 内部可能隐式开启了自动模式，我们需要立刻按回手动，等待连接完成
            new_carriage.train.manual_mode = true
            log_debug("传送门 DEBUG (teleport_next): [状态保护] 已强制第一节新车保持手动模式，防止早产。")

            if new_carriage.train and new_carriage.train.schedule then
                struct.saved_schedule_index = new_carriage.train.schedule.current
                log_debug(
                    "传送门 DEBUG (teleport_next): [时刻表] 已将正确的下一站索引 ["
                    .. struct.saved_schedule_index
                    .. "] 记忆到 struct。"
                )
            end
        end

        if SE_TELEPORT_STARTED_EVENT_ID and not carriage_ahead then
            log_debug(
                "传送门 SE 兼容: 正在为旧火车 ID "
                .. tostring(carriage.train.id)
                .. " 触发 on_train_teleport_started。"
            )
            script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
                train = carriage.train,
                old_train_id_1 = carriage.train.id,
                old_surface_index = struct.surface.index,
                teleporter = struct.entity,
            })
        end

        if carriage.valid then
            carriage.destroy()
        end

        -- 更新指针: struct.carriage_ahead 指向远端新车
        struct.carriage_ahead = new_carriage

        if next_carriage and next_carriage.valid then
            log_debug("传送门 DEBUG (teleport_next): 设置下一节待传送车厢: " .. next_carriage.name)
            struct.carriage_behind = next_carriage

            -- 创建新拖船并赋给 struct.tug
            local tug = opposite.surface.create_entity({
                name = Constants.name_tug,
                position = Util.vectors_add(opposite.position, Constants.output_tug_pos[se_direction]),
                direction = se_direction,
                force = new_carriage.force,
            })
            if tug then
                tug.destructible = false
                struct.tug = tug
                log_debug(
                    "传送门 DEBUG (teleport_next): [Tug] 新拖船已创建并连接到车厢 "
                    .. new_carriage.unit_number
                )
            end

            -- >>>>> [新增关键逻辑] 立即恢复出口火车状态 (太空电梯风格) >>>>>
            -- 目的：让火车在两节车厢传送的间隙，也能响应红绿灯
            if new_carriage.train and new_carriage.train.valid then
                -- 1. 恢复时刻表
                if struct.saved_schedule_index then
                    new_carriage.train.go_to_station(struct.saved_schedule_index)
                end

                -- 2. 恢复自动模式 (如果原车是自动)
                new_carriage.train.manual_mode = struct.saved_manual_mode or false

                -- 3. 恢复速度 (对抗切自动导致的刹车)
                if not new_carriage.train.manual_mode and struct.old_train_speed then
                    local speed_direction = Chuansongmen.elevator_east_sign(opposite)
                        * Chuansongmen.carriage_east_sign(new_carriage)
                        * Chuansongmen.train_forward_sign(new_carriage)

                    -- 只有当速度归零时才强制恢复，避免打断正常的减速
                    if new_carriage.train.speed == 0 then
                        new_carriage.train.speed = speed_direction * math.abs(struct.old_train_speed)
                    end
                end
            end
            -- <<<<< [新增结束] <<<<<
        else
            log_debug("传送门 DEBUG (teleport_next): 这是最后一节车厢，传送完成。")
            TeleportHandler.finish_teleport(struct)
        end
    else
        -- [跑路检查]
        if game.tick % (Constants.teleport_next_tick_frequency * 15) == 0 then
            local carriage_bounding_box = Util.rotate_box(carriage.bounding_box, carriage.position)
            local carriage_side = (struct.direction == defines.direction.east) and carriage_bounding_box.right_bottom
                or carriage_bounding_box.left_top
            if not Util.position_in_rect(struct.entity.bounding_box, carriage_side) then
                TeleportHandler.finish_teleport(struct)
                return
            end
        end

        -- [出口堵塞]
        log_debug(
            "传送门 警告 (teleport_next): 传送目标点被阻挡。等待 on_tick 速度管理器疏通..."
        )
        if not carriage_ahead and not carriage.train.manual_mode then
            local schedule = carriage.train.get_schedule()
            if schedule then
                local records = schedule.get_records()
                local current_index = schedule.current
                if records and records[current_index] then
                    records[current_index].wait_conditions = { { type = "time", ticks = 9999999 * 60 } }
                    records[current_index].temporary = true
                    schedule.set_records(records)
                    log_debug(
                        "传送门 DEBUG (teleport_next): [兼容性模式] 出口堵塞，已修改当前站点的等待条件使火车暂停。"
                    )
                end
            end
        end
    end
end

--- 检查火车进入
function TeleportHandler.check_carriage_at_location(surface, position)
    log_debug(
        "传送门 DEBUG (check_carriage): 碰撞器触发！位置: "
        .. serpent.line(position)
        .. ", 地表: "
        .. surface.name
    )
    for _, struct in pairs(MOD_DATA.portals) do
        if
            struct.entity
            and struct.entity.valid
            and struct.watch_area
            and (not struct.carriage_behind or not struct.carriage_behind.valid)
            and struct.surface == surface
            and Util.position_in_rect(struct.entity.bounding_box, position)
        then
            local carriages = surface.find_entities_filtered({ type = Constants.stock_types, area = struct.watch_area })
            if not (carriages and #carriages > 0 and carriages[1].train and carriages[1].train.valid) then
                -- 如果找不到有效的火车，则跳过此传送门
                goto continue
            end
            local train = carriages[1].train

            -- 【新功能 新增】火车传送消耗逻辑
            if is_resource_cost_enabled() then
                log_debug(
                    "传送门 DEBUG (check_carriage): [资源消耗] 模式已启用，开始检查火车传送消耗..."
                )
                local opposite = State.get_opposite_struct(struct)
                if not opposite then
                    log_debug(
                        "传送门 DEBUG (check_carriage): [资源消耗] 传送门未配对，跳过消耗检查。"
                    )
                else
                    local portal_inventory = struct.entity.get_inventory(defines.inventory.assembling_machine_input)
                    if not portal_inventory then
                        log_debug(
                            "传送门 错误 (check_carriage): [资源消耗] 无法获取传送门输入物品栏！"
                        )
                        return -- 严重错误，中断
                    end

                    -- 1. 定义火车传送需要消耗的物品
                    local items_to_consume = { { name = "chuansongmen-exotic-matter", count = 1 } }

                    -- 2. 调用新的共享资源消耗函数
                    local result = Util.consume_shared_resources(nil, struct, opposite, items_to_consume) -- player为nil，将向所有人广播

                    -- 3. 根据结果进行处理
                    if result.success then
                        -- 在成功消耗了资源的那个传送门产出碎片
                        local producer_portal = result.consumed_at
                        local output_inventory =
                            producer_portal.entity.get_inventory(defines.inventory.assembling_machine_output)
                        if output_inventory then
                            output_inventory.insert({ name = "chuansongmen-spacetime-shard", count = 3 })
                        end

                        -- 检查是否在本次消耗后耗尽，并发出提示
                        local final_inv =
                            producer_portal.entity.get_inventory(defines.inventory.assembling_machine_input)
                        if final_inv and final_inv.get_item_count("chuansongmen-exotic-matter") == 0 then
                            log_debug(
                                "传送门 警告 (check_carriage): [资源消耗] 奇异物质已在本次传送中耗尽。"
                            )
                            game.print({
                                "messages.chuansongmen-warning-exotic-matter-depleted-train",
                                producer_portal.name,
                                producer_portal.id,
                            })
                        end
                        log_debug("传送门 DEBUG (check_carriage): [资源消耗] 消耗完毕。")

                        -- [新增] [优化] 清除缺油标记 (如果之前有)
                        struct.waiting_for_fuel = nil
                        struct.blocked_train = nil
                    else
                        -- 如果消耗失败，则执行停止火车的逻辑并中断传送
                        if not train.manual_mode then
                            local schedule = train.get_schedule()
                            if schedule then
                                local current_index = schedule.current
                                log_debug(
                                    "传送门 DEBUG (check_carriage): [时刻表修复] 火车时刻表将被修正。当前目标索引: "
                                    .. current_index
                                )
                                local new_record_index = current_index + 1
                                schedule.add_record({
                                    station = struct.station.backer_name,
                                    wait_conditions = { { type = "time", ticks = 9999999 * 60 } },
                                    temporary = true,
                                    index = { schedule_index = new_record_index },
                                })
                                schedule.go_to_station(new_record_index)

                                -- [新增] [优化] 标记为等待燃料，不再需要每秒扫描
                                struct.waiting_for_fuel = true
                                struct.blocked_train = train
                                log_debug(
                                    "传送门 DEBUG (check_carriage): [优化] 标记为等待燃料 (waiting_for_fuel=true)"
                                )

                                log_debug(
                                    "传送门 DEBUG (check_carriage): [时刻表修复] 已在下一站插入临时路障站点，并重定向火车目标。"
                                )
                            end
                        else
                            log_debug(
                                "传送门 DEBUG (check_carriage): [时刻表修复] 火车处于手动模式，跳过时刻表修改。"
                            )
                        end
                        return -- 关键：中断函数，传送序列不会开始
                    end
                end
            end
            -- 【新功能 结束】

            log_debug(
                "传送门 DEBUG (check_carriage): 碰撞发生在 ID: "
                .. struct.id
                .. " 附近, 找到 "
                .. #carriages
                .. " 节车厢。"
            )
            log_debug("传送门 DEBUG (check_carriage): 成功捕获到火车: " .. carriages[1].name)
            struct.carriage_behind = carriages[1]
            struct.carriage_ahead = nil
            -- [新增] [优化] 开启传送状态标记，激活 on_tick
            struct.is_teleporting = true

            -- [优化] 将该传送门的 ID 加入活跃列表
            if not storage.active_teleporters then
                storage.active_teleporters = {}
            end
            -- [修改] 不再存整个 struct，只存 unit_number 作为 key，值为 true
            storage.active_teleporters[struct.unit_number] = true
            log_debug("传送门 DEBUG (check_carriage): 设置待传送车厢为: " .. struct.carriage_behind.name)
            return
        end
        ::continue::
    end
end

-- =================================================================================
-- SE 兼容性：速度同步 (现在由 on_tick 循环持续调用)
-- =================================================================================

--- 【重构】速度同步逻辑 (此函数基本不变，但调用时机变了)
function TeleportHandler.hypertrain_sync_speed(carriage_a, carriage_a_direction, carriage_b, carriage_b_direction)
    local train_a = carriage_a.train
    local train_b = carriage_b.train
    if not (train_a and train_a.valid and train_b and train_b.valid) then
        return
    end

    local total_weight = train_a.weight + train_b.weight
    local average_speed = ((train_a.weight * math.abs(train_a.speed)) + (train_b.weight * math.abs(train_b.speed)))
        / total_weight

    -- 限制最高速度
    local max_train_speed = 0.5
    average_speed = math.min(average_speed, max_train_speed)

    train_a.speed = average_speed * carriage_a_direction * Chuansongmen.train_forward_sign(carriage_a)
    train_b.speed = average_speed * carriage_b_direction * Chuansongmen.train_forward_sign(carriage_b)
end

--- 持续速度管理器 (修复版：绅士推车，红灯停)
function TeleportHandler.hypertrain_manage_speed(struct)
    -- 必须同时存在入口车厢和出口车厢
    if
        struct.carriage_behind
        and struct.carriage_behind.valid
        and struct.carriage_ahead
        and struct.carriage_ahead.valid
    then
        local train_behind = struct.carriage_behind.train
        local train_ahead = struct.carriage_ahead.train
        local opposite_struct = State.get_opposite_struct(struct)

        if not (train_behind and train_behind.valid and train_ahead and train_ahead.valid and opposite_struct) then
            return
        end

        -- 1. 维持出口动力 (带红绿灯检测)
        -- 逻辑：只有当火车处于手动模式，或者自动模式下“正在行驶/无路径”时，才施加推力。
        -- 如果是 wait_signal (红灯) 或 destination_full，则尊重引擎决定，不推。
        local should_push = train_ahead.manual_mode or
            train_ahead.state == defines.train_state.on_the_path or
            train_ahead.state == defines.train_state.no_path

        local passive_train_speed = 0.5

        if should_push and math.abs(train_ahead.speed) < passive_train_speed then
            local speed_direction = Chuansongmen.elevator_east_sign(opposite_struct)
                * Chuansongmen.carriage_east_sign(struct.carriage_ahead)
                * Chuansongmen.train_forward_sign(struct.carriage_ahead)

            train_ahead.speed = passive_train_speed * speed_direction
        end

        -- 2. 强制入口手动模式 (保持不变，入口必须完全接管)
        if not train_behind.manual_mode then
            train_behind.manual_mode = true
        end

        -- 3. 同步速度
        TeleportHandler.hypertrain_sync_speed(
            struct.carriage_behind,
            Chuansongmen.elevator_east_sign(struct) * Chuansongmen.carriage_east_sign(struct.carriage_behind),
            struct.carriage_ahead,
            Chuansongmen.elevator_east_sign(opposite_struct) * Chuansongmen.carriage_east_sign(struct.carriage_ahead)
        )
    elseif struct.tug and struct.tug.valid then
        -- 如果只有拖船没有车了(异常情况)，清理
        struct.tug.destroy()
        struct.tug = nil
    end
end

-- [优化] 专门处理等待燃料的唤醒逻辑 (替代 control.lua 中的全图扫描)
function TeleportHandler.handle_fuel_wakeup(struct)
    if not (struct.waiting_for_fuel and struct.blocked_train and struct.blocked_train.valid) then
        struct.waiting_for_fuel = nil -- 数据无效，清理标记
        struct.blocked_train = nil
        return
    end

    -- [修改] 检查整个网络的燃料，而不仅仅是本地
    local network_has_fuel = false

    -- 1. 检查本地燃料
    local local_inv = struct.entity.get_inventory(defines.inventory.assembling_machine_input)
    if local_inv and local_inv.get_item_count("chuansongmen-exotic-matter") > 0 then
        network_has_fuel = true
        log_debug("传送门 DEBUG: [唤醒] 在本地传送门 ID " .. struct.id .. " 发现燃料。")
    end

    -- 2. 如果本地没有，再检查对侧燃料
    if not network_has_fuel then
        local opposite = State.get_opposite_struct(struct) -- O(1) 操作，性能安全
        if opposite then
            local opposite_inv = opposite.entity.get_inventory(defines.inventory.assembling_machine_input)
            if opposite_inv and opposite_inv.get_item_count("chuansongmen-exotic-matter") > 0 then
                network_has_fuel = true
                log_debug("传送门 DEBUG: [唤醒] 在对侧传送门 ID " .. opposite.id .. " 发现燃料。")
            end
        end
    end

    -- 3. 如果网络中有燃料，则唤醒火车
    if network_has_fuel then
        log_debug("传送门 DEBUG: [唤醒] 燃料已补充，正在唤醒火车...")

        local train = struct.blocked_train
        local schedule = train.schedule

        -- 移除之前插入的临时等待站 (解除封印)
        if schedule and schedule.records and schedule.current <= #schedule.records then
            -- [安全修复] 检查当前记录是否是那个临时站，避免误删
            local current_record = schedule.records[schedule.current]
            if current_record and current_record.temporary and current_record.station == struct.station.backer_name then
                table.remove(schedule.records, schedule.current)
                -- 修正索引
                if schedule.current > #schedule.records and #schedule.records > 0 then
                    schedule.current = #schedule.records
                end
                train.schedule = schedule
            end
        end

        -- 清理标记
        struct.waiting_for_fuel = nil
        struct.blocked_train = nil

        -- 手动触发一次检测，立即开始传送
        -- 注意：这里可能会消耗对侧的燃料，但这是符合预期的
        TeleportHandler.check_carriage_at_location(struct.surface, train.front_stock.position)
    end
end

return TeleportHandler
