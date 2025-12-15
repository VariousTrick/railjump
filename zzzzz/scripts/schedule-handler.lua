-- /scripts/schedule-handler.lua
-- 【传送门 Mod - 时刻表处理模块 v3.0 (SE 逻辑重构版)】
-- 功能：专门负责在火车通过传送门后，安全、完整地转移其时刻表。
-- 修复内容：
-- 1. 采用 Space Exploration 的"先清理后计算"流程，彻底解决循环线路末尾死循环问题。
-- 2. 只处理当前经过的临时传送门站点，不再误删时刻表中其他同名的临时站点。

local ScheduleHandler = {}

-- 本地调试开关
local DEBUG_ENABLED = false

local function log_schedule(message)
	if DEBUG_ENABLED then
		log("[传送门 ScheduleHandler] " .. message)
	end
end

function ScheduleHandler.set_debug_mode(is_enabled)
	DEBUG_ENABLED = is_enabled
	log_schedule("调试模式已 " .. (is_enabled and "开启" or "关闭") .. "。")
end

--- 核心函数：转移时刻表
-- @param old_train LuaTrain: 即将被销毁的旧火车
-- @param new_train LuaTrain: 新创建的火车
-- @param entry_portal_station_name string: 刚刚经过的传送门车站名称
function ScheduleHandler.transfer_schedule(old_train, new_train, entry_portal_station_name)
	if not (old_train and old_train.valid and new_train and new_train.valid) then
		return
	end

	log_schedule("DEBUG (transfer_schedule v3.0): 开始转移时刻表 (SE 逻辑流程)...")

	-- 1. 获取旧时刻表数据的副本
	local schedule = old_train.get_schedule()
	if not schedule then
		return
	end

	-- get_records 返回的是一个新表，我们可以随意修改它而不影响旧火车
	local records = schedule.get_records()
	if not records then
		return
	end

	local current_index = schedule.current
	log_schedule("DEBUG: 初始状态 - 站点数: " .. #records .. ", 当前索引: " .. current_index)

	-- ========================================================================
	-- 步骤 1: 清理防堵塞路障 (Rail Stops)
	-- SE 逻辑：倒序遍历，移除所有基于铁轨的站点。
	-- 关键在于正确调整 current_index，使其回退到“逻辑上的上一站”。
	-- ========================================================================

	for i = #records, 1, -1 do
		local record = records[i]
		if record.rail then
			-- 如果当前火车正停在这个路障上 (堵塞情况)
			if i == current_index then
				log_schedule("DEBUG: 发现当前停靠在 Rail 路障 (Index " .. i .. ")，索引回退。")
				current_index = current_index - 1

			-- 如果这个路障在当前索引之前 (虽然少见，但也处理)
			elseif i < current_index then
				current_index = current_index - 1

				-- 如果路障在当前索引之后，移除它不影响当前索引，直接忽略
			end

			-- 从列表中物理移除该记录
			table.remove(records, i)
		end
	end

	-- 安全钳制：防止索引回退到 0
	if current_index < 1 then
		current_index = 1
	end

	-- 如果列表被删空了 (极罕见)
	if #records == 0 then
		log_schedule("DEBUG: 警告 - 时刻表被清空。")
		return
	end

	log_schedule("DEBUG: 路障清理完毕 - 剩余站点数: " .. #records .. ", 修正后索引: " .. current_index)

	-- ========================================================================
	-- 步骤 2: 处理当前传送门站点
	-- 此时 current_index 应该指向传送门本身 (如果刚才是在路障上，现在已经退回来了)
	-- ========================================================================

	local current_record = records[current_index]

	-- 只有当火车处于自动模式，且当前指向的确实是传送门时，才介入处理
	if not old_train.manual_mode and current_record and current_record.station == entry_portal_station_name then
		if current_record.temporary then
			-- [情况 A] 临时的传送门站
			-- 逻辑：任务已完成，删除它。
			log_schedule("DEBUG: 当前是临时传送门站 (Index " .. current_index .. ")，执行删除。")
			table.remove(records, current_index)

			-- 删除当前站后，索引自动指向下一条记录 (即原本的下一站)。
			-- 唯一需要处理的是越界情况 (删的是最后一站 -> 回到第一站)
			if current_index > #records then
				current_index = 1
			end
			log_schedule("DEBUG: 删除后索引指向: " .. current_index)
		else
			-- [情况 B] 永久的传送门站
			-- 逻辑：保留它，将目标推进到下一站。
			-- 公式：(当前索引 % 总数) + 1。
			-- 举例：总数2，当前2。 (2 % 2) + 1 = 1。去第一站。完美解决死循环。
			current_index = (current_index % #records) + 1
			log_schedule("DEBUG: 当前是永久传送门站，推进到下一站索引: " .. current_index)
		end
	else
		log_schedule("DEBUG: 当前不是传送门站 (或手动模式)，保持目标不变。")
	end

	-- ========================================================================
	-- 步骤 3: 应用到新火车
	-- ========================================================================

	local new_schedule = new_train.get_schedule()
	if not new_schedule then
		return
	end

	-- 设置清理后的记录列表
	new_schedule.set_records(records)

	-- 复制中断设置
	new_schedule.set_interrupts(schedule.get_interrupts())

	-- 复制组信息
	if schedule.group then
		new_schedule.group = schedule.group
	end

	-- 命令新火车前往计算出的目标索引
	if #records > 0 then
		new_schedule.go_to_station(current_index)
		log_schedule("DEBUG: 时刻表转移完成，最终目标 Index: " .. current_index)
	end

	-- 清空旧火车时刻表，防止销毁时的副作用
	old_train.schedule = nil
end

return ScheduleHandler
