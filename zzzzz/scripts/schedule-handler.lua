-- /scripts/schedule-handler.lua
-- 【传送门 Mod - 时刻表处理模块 v2.0】
-- 功能：专门负责在火车通过传送门后，安全、完整地转移其时刻表和中断机制。
-- 设计原则 (v2.0 更新)：
-- 1. 完整性：同时复制时刻表的站点列表（records）和中断机制（interrupts）。
-- 2. 智能区分：
--- 对于永久站点：不再删除，而是将列车的目标“推进”到时刻表的下一站，以支持循环线路。
--- 对于临时站点：继续执行严格的清理，防止因传送导致的引擎错误和游戏崩溃。
-- 3. 兼容性：借鉴 Space Exploration 的成熟方案，确保对原版和各类 Mod 的高度兼容。
-- 4. 模块化：将复杂的时刻表逻辑与核心传送逻辑解耦，提高代码可读性和可维护性。

local ScheduleHandler = {}

-- 本地调试开关，将由 control.lua 动态控制
local DEBUG_ENABLED = false

-- 本地化的日志记录器
local function log_schedule(message)
    if DEBUG_ENABLED then
        -- 在日志前添加模块标识，方便区分来源
        log("[传送门 ScheduleHandler] " .. message)
    end
end

-- 接收来自 control.lua 的调试开关状态
-- @param is_enabled boolean: 是否开启调试日志
function ScheduleHandler.set_debug_mode(is_enabled)
    DEBUG_ENABLED = is_enabled
    log_schedule("调试模式已 " .. (is_enabled and "开启" or "关闭") .. "。")
end

--- 核心函数：转移时刻表和中断机制 (v2.0 重构版)
-- @param old_train LuaTrain: 即将被销毁的、进入传送门的旧火车实体
-- @param new_train LuaTrain: 在出口处新创建的火车实体
-- @param entry_portal_station_name string: 入口传送门内部火车站的完整名称
function ScheduleHandler.transfer_schedule(old_train, new_train, entry_portal_station_name)
    log_schedule(
        "DEBUG (transfer_schedule v2.0): 开始为新火车 (ID: "
        .. new_train.id
        .. ") 转移时刻表，来源旧火车 (ID: "
        .. old_train.id
        .. ")。"
    )

    -- 1. 安全地获取旧火车的时刻表对象
    if not (old_train and old_train.valid and new_train and new_train.valid) then
        log_schedule("错误 (transfer_schedule): 输入的旧火车或新火车实体无效，操作中止。")
        return
    end

    local schedule_old = old_train.get_schedule()
    if not schedule_old then
        log_schedule("DEBUG (transfer_schedule): 旧火车没有时刻表，无需转移。")
        return
    end

    -- 2. 【关键】获取旧时刻表的完整快照
    log_schedule(
        "DEBUG (transfer_schedule): 正在从旧时刻表获取站点列表 (records)、中断机制 (interrupts) 和当前状态..."
    )
    local records_old = schedule_old.get_records()
    local interrupts = schedule_old.get_interrupts()
    local current_stop_index = schedule_old.current
    log_schedule(
        "DEBUG (transfer_schedule): 获取完毕。站点数: "
        .. #records_old
        .. ", 中断数: "
        .. #interrupts
        .. ", 当前目标索引: "
        .. current_stop_index
    )

    if #records_old == 0 then
        log_schedule("DEBUG (transfer_schedule): 旧时刻表为空，无需进一步处理。")
        return
    end

    -- 3. 【v2.0 核心改动】智能计算“逻辑上的下一站”索引
    -- 这一步在任何清理操作之前进行，以确保我们知道火车原本应该去哪里。
    local logical_next_stop_index = current_stop_index
    local current_record = records_old[current_stop_index]

    if current_record and current_record.station == entry_portal_station_name then
        log_schedule(
            "DEBUG (transfer_schedule): 检测到当前站点是刚通过的传送门。正在计算逻辑下一站..."
        )
        -- 使用取模运算(%)优雅地处理循环时刻表，计算出下一个站点的索引
        logical_next_stop_index = (current_stop_index % #records_old) + 1
        log_schedule(
            "DEBUG (transfer_schedule): 基于原始时刻表，逻辑下一站的索引为: "
            .. logical_next_stop_index
        )
    else
        log_schedule(
            "DEBUG (transfer_schedule): 当前站点不是传送门，或已无站点，将保持当前目标。"
        )
    end

    -- 4. 【v2.0 核心改动】构建新的时刻表记录，并按需清理
    -- 我们不再直接修改旧记录，而是创建一个全新的、干净的记录列表。
    log_schedule("DEBUG (transfer_schedule): 开始构建新时刻表，并按需清理临时/轨道站点...")
    local final_records = {}
    local index_correction_offset = 0 -- 用于记录因删除站点而产生的索引偏移

    for i, record in ipairs(records_old) do
        local should_be_removed = false

        -- 清理条件 1: 任何指向轨道的临时站点（防止跨地表崩溃的关键措施）
        if record.rail and record.temporary then
            log_schedule(
                "!! 关键清理 (transfer_schedule): 发现并准备移除一个临时的轨道站点，索引: " .. i
            )
            should_be_removed = true
        end

        -- 清理条件 2: 刚刚通过的、且是临时的传送门站点
        if not should_be_removed and record.station == entry_portal_station_name and record.temporary then
            log_schedule(
                "DEBUG (transfer_schedule): 发现并准备移除刚通过的临时传送门站点，索引: " .. i
            )
            should_be_removed = true
        end

        if should_be_removed then
            -- 如果被移除的站点在我们的“逻辑下一站”之前，那么“逻辑下一站”的最终索引就需要减一
            if i < logical_next_stop_index then
                index_correction_offset = index_correction_offset + 1
                log_schedule(
                    "DEBUG (transfer_schedule): 因移除了目标前的站点，索引修正偏移量增加为: "
                    .. index_correction_offset
                )
            end
        else
            -- 如果站点不需要被移除 (包括永久的传送门站)，则将其加入到最终的列表中
            table.insert(final_records, record)
        end
    end

    log_schedule("DEBUG (transfer_schedule): 新时刻表构建完毕。最终站点数: " .. #final_records)

    -- 5. 【v2.0 核心改动】修正最终的目标索引
    local final_target_index = logical_next_stop_index - index_correction_offset
    log_schedule(
        "DEBUG (transfer_schedule): 原始目标索引 "
        .. logical_next_stop_index
        .. " - 偏移量 "
        .. index_correction_offset
        .. " = 最终目标索引 "
        .. final_target_index
    )

    -- 确保修正后的索引不会越界
    if #final_records > 0 then
        if final_target_index < 1 then
            final_target_index = 1
        elseif final_target_index > #final_records then
            final_target_index = #final_records
        end
        log_schedule("DEBUG (transfer_schedule): 最终目标索引校对完成: " .. final_target_index)
    else
        log_schedule("DEBUG (transfer_schedule): 清理后已无站点记录，无需设置下一站。")
    end

    -- 6. 将清理和修正后的数据应用到新火车
    local schedule_new = new_train.get_schedule()
    if not schedule_new then
        log_schedule("错误 (transfer_schedule): 无法为新火车获取有效的时刻表对象！")
        return
    end

    -- 6.1. 复制站点列表
    schedule_new.set_records(final_records)
    log_schedule(
        "DEBUG (transfer_schedule): 已将 " .. #final_records .. " 个最终站点记录设置到新时刻表。"
    )

    -- 6.2. 复制中断机制
    schedule_new.set_interrupts(interrupts)
    log_schedule("DEBUG (transfer_schedule): 已将 " .. #interrupts .. " 个中断机制设置到新时刻表。")

    -- 6.3. 复制列车组信息
    if schedule_old.group then
        schedule_new.group = schedule_old.group
        log_schedule("DEBUG (transfer_schedule): 已成功复制列车组信息。")
    end

    -- 7. 【关键】命令新火车继续它的旅程
    if #final_records > 0 then
        schedule_new.go_to_station(final_target_index)
        log_schedule(
            "!! 核心操作 (transfer_schedule): 已命令新火车前往最终目标站点索引 "
            .. final_target_index
            .. " ('"
            .. (final_records[final_target_index].station or "轨道站")
            .. "')。时刻表转移完成！"
        )
    end

    -- 8. 【重要】清空旧火车的时刻表，防止在销毁前产生意外行为
    old_train.schedule = nil
    log_schedule("DEBUG (transfer_schedule): 已清空旧火车的时刻表，准备安全销毁。")
end

return ScheduleHandler
