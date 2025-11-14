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
  return settings.startup["chuansongmen-enable-resource-cost"] and
      settings.startup["chuansongmen-enable-resource-cost"].value or false
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
-- 火车传送核心逻辑
-- =================================================================================

--- 内容转移
function TeleportHandler.carriage_transfer_contents(carriage, new_carriage)
  log_debug("传送门 DEBUG (carriage_transfer_contents): 正在从 " ..
    carriage.name ..
    " (旧 unit_number: " ..
    carriage.unit_number .. ") 复制内容到 " .. new_carriage.name .. " (新 unit_number: " .. new_carriage.unit_number .. ")")
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
  if carriage.color and new_carriage.color then new_carriage.color = carriage.color end
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
        log_debug("传送门 警告 (carriage_transfer_contents): 无法传送非玩家司机 (类型: " .. driver.type .. ")，司机将留在原地。")
      end
    end
  end
  log_debug("传送门 DEBUG (carriage_transfer_contents): 内容复制完成。")
end

--- 传送结束
function TeleportHandler.finish_teleport(struct, opposite_struct)
  log_debug("传送门 DEBUG (finish_teleport): 火车传送完毕, 开始清理状态。源ID: " .. struct.id .. ", 目标ID: " .. opposite_struct.id)

  -- =======================================================
  -- 【Tug机制】销毁最后一个拖船
  -- =======================================================
  if opposite_struct.tug and opposite_struct.tug.valid then
    opposite_struct.tug.destroy()
    opposite_struct.tug = nil
    log_debug("传送门 DEBUG (finish_teleport): [Tug] 最后的拖船已销毁。")
  end
  -- =======================================================

  local final_train = opposite_struct.carriage_ahead and opposite_struct.carriage_ahead.train
  if final_train and final_train.valid then
    log_debug("传送门 DEBUG (finish_teleport): 找到最终火车 (ID: " .. final_train.id .. "), 开始恢复状态。")
    final_train.manual_mode = opposite_struct.carriage_ahead_manual_mode
    local speed_direction = Chuansongmen.elevator_east_sign(opposite_struct) *
        Chuansongmen.carriage_east_sign(opposite_struct.carriage_ahead) *
        Chuansongmen.train_forward_sign(opposite_struct.carriage_ahead)
    final_train.speed = speed_direction * math.abs(opposite_struct.old_train_speed)
    log_debug("传送门 DEBUG (finish_teleport): [最小干预策略] 不再调用go_to_station。")
    log_debug("传送门 DEBUG (finish_teleport): 状态恢复完毕。模式: " ..
      (final_train.manual_mode and "手动" or "自动") .. ", 速度: " .. final_train.speed)
  else
    log_debug("传送门 警告 (finish_teleport): 找不到有效的最终火车进行状态恢复。")
  end
  struct.carriage_behind, struct.carriage_ahead, opposite_struct.carriage_behind, opposite_struct.carriage_ahead = nil,
      nil, nil, nil
  log_debug("传送门 DEBUG (finish_teleport): 两侧传送门状态变量已重置。清理完毕。")
  if SE_TELEPORT_FINISHED_EVENT_ID and final_train and final_train.valid and opposite_struct.old_train_id then
    log_debug("传送门 SE 兼容: 正在为新火车 ID " ..
      final_train.id .. " (旧火车ID: " .. opposite_struct.old_train_id .. ") 触发 on_train_teleport_finished 事件。")
    script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
      train = final_train,
      old_train_id_1 = opposite_struct.old_train_id,
      old_surface_index = struct.surface.index,
      teleporter = opposite_struct.entity
    })
    opposite_struct.old_train_id = nil
    if opposite_struct.saved_schedule_index then
      log_debug("传送门 DEBUG (finish_teleport): [时刻表] 清理出口传送门 (ID: " .. opposite_struct.id .. ") 的时刻表记忆。")
      opposite_struct.saved_schedule_index = nil
    end
    if struct.saved_schedule_index then
      struct.saved_schedule_index = nil
    end
  else
    log_debug("传送门 SE 兼容: 警告 - 未能满足所有条件，on_train_teleport_finished 事件被跳过！")
  end
end

--- 传送下一节车厢
function TeleportHandler.teleport_next(struct)
  local opposite = State.get_opposite_struct(struct)
  if not opposite then
    log_debug("传送门 DEBUG (teleport_next): 传送门 " .. struct.id .. " 未找到配对，中断传送。")
    TeleportHandler.finish_teleport(struct, struct)
    return
  end
  if not (struct.carriage_behind and struct.carriage_behind.valid and struct.carriage_behind.surface == struct.surface) then
    struct.carriage_behind, struct.carriage_ahead = nil, nil
    return
  end
  local carriage = struct.carriage_behind
  if not (carriage.train and carriage.train.valid) then
    log_debug("传送门 警告 (teleport_next): 待传送车厢或其火车无效，中断传送。")
    TeleportHandler.finish_teleport(struct, opposite)
    return
  end
  local carriage_ahead = opposite.carriage_ahead
  local se_direction = (opposite.direction == defines.direction.east or opposite.direction == defines.direction.south) and
      defines.direction.east or defines.direction.west
  local spawn_pos = Util.vectors_add(opposite.position, Constants.output_pos[se_direction])
  local can_place = opposite.surface.can_place_entity { name = carriage.name, position = spawn_pos, direction = defines.direction.south, force = carriage.force }
  local is_clear = opposite.surface.count_entities_filtered { type = Constants.stock_types, area = opposite.output_area, limit = 1 } ==
      0
  if can_place and (carriage_ahead or is_clear) then
    log_debug("传送门 DEBUG (teleport_next): 传送门 " .. struct.id .. " 正在传送车厢: " .. carriage.name)
    local next_carriage = carriage.get_connected_rolling_stock(defines.rail_direction.front) or
        carriage.get_connected_rolling_stock(defines.rail_direction.back)
    if not carriage_ahead then
      opposite.carriage_ahead_manual_mode, opposite.old_train_speed, opposite.old_train_id = carriage.train.manual_mode,
          carriage.train.speed, carriage.train.id
      log_debug("传送门 DEBUG (teleport_next): [状态保存] 已保存火车状态。")
    end

    -- =======================================================
    -- 【Tug机制】在创建新车厢之前，先销毁上一轮的Tug
    -- =======================================================
    if opposite.tug and opposite.tug.valid then
      opposite.tug.destroy()
      opposite.tug = nil
      log_debug("传送门 DEBUG (teleport_next): [Tug] 旧拖船已销毁。")
    end
    -- =======================================================

    local spawn_dir = carriage.orientation > 0.5 and defines.direction.south or defines.direction.north
    local new_carriage = opposite.surface.create_entity({
      name = carriage.name,
      position = spawn_pos,
      direction = spawn_dir,
      force = carriage.force
    })
    if not new_carriage then
      log_debug("传送门 致命错误 (teleport_next): 无法在出口创建新车厢！")
      TeleportHandler.finish_teleport(struct, opposite)
      return
    end
    log_debug("传送门 DEBUG (teleport_next): 新车厢 " .. new_carriage.name .. " 创建成功。")
    TeleportHandler.carriage_transfer_contents(carriage, new_carriage)
    if not carriage_ahead then
      log_debug("传送门 DEBUG (teleport_next): [时刻表] 调用 ScheduleHandler 进行智能设定...")
      ScheduleHandler.transfer_schedule(carriage.train, new_carriage.train, struct.station.backer_name)
      if new_carriage.train and new_carriage.train.schedule then
        opposite.saved_schedule_index = new_carriage.train.schedule.current
        log_debug("传送门 DEBUG (teleport_next): [时刻表] 已将正确的下一站索引 [" .. opposite.saved_schedule_index .. "] 记忆到出口。")
      end
    end
    if SE_TELEPORT_STARTED_EVENT_ID then
      log_debug("传送门 SE 兼容: 正在为旧火车 ID " .. tostring(opposite.old_train_id) .. " 触发 on_train_teleport_started。")
      script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
        train = carriage.train,
        old_train_id_1 = opposite.old_train_id or 0,
        old_surface_index = struct.surface.index,
        teleporter = struct.entity
      })
    end
    if new_carriage.train and new_carriage.train.valid then
      local speed_dir = Chuansongmen.elevator_east_sign(opposite) * Chuansongmen.carriage_east_sign(new_carriage) *
          Chuansongmen.train_forward_sign(new_carriage)
      new_carriage.train.speed = speed_dir * math.abs(opposite.old_train_speed)
      if opposite.saved_schedule_index then
        new_carriage.train.get_schedule().go_to_station(opposite.saved_schedule_index)
        log_debug("传送门 DEBUG (teleport_next): [时刻表] 强制将火车目标指回正确的站点索引。")
      end
    end
    if carriage.valid then
      log_debug("传送门 DEBUG (teleport_next): 销毁旧车厢。")
      carriage.destroy()
    end
    struct.carriage_ahead, opposite.carriage_ahead = new_carriage, new_carriage
    if next_carriage and next_carriage.valid then
      log_debug("传送门 DEBUG (teleport_next): 设置下一节待传送车厢: " .. next_carriage.name)
      struct.carriage_behind = next_carriage

      -- =======================================================
      -- 【Tug机制】在拼接完新车厢之后，在车队尾部创建新的Tug
      -- =======================================================
      local tug = opposite.surface.create_entity { name = Constants.name_tug, position = Util.vectors_add(opposite.position, Constants.output_tug_pos[se_direction]), direction = se_direction, force = new_carriage.force }
      if tug then
        tug.destructible = false
        opposite.tug = tug
        log_debug("传送门 DEBUG (teleport_next): [Tug] 新拖船已创建并连接到车厢 " .. new_carriage.unit_number)
      end
      -- =======================================================
    else
      log_debug("传送门 DEBUG (teleport_next): 这是最后一节车厢，传送完成。")
      TeleportHandler.finish_teleport(struct, opposite)
    end
  else
    log_debug("传送门 警告 (teleport_next): 传送目标点被阻挡。")
    -- 【最终兼容性修复】
    if not carriage_ahead and not carriage.train.manual_mode then
      local schedule = carriage.train.get_schedule()

      if schedule then
        -- 1. 获取整个时刻表的记录列表
        local records = schedule.get_records()
        local current_index = schedule.current

        -- 2. 确保当前索引有效，并且对应的记录存在
        if records and records[current_index] then
          -- 3. 只修改当前记录的等待条件，这是最无侵入性的做法
          records[current_index].wait_conditions = { { type = "time", ticks = 9999999 * 60 } }

          -- (可选，但推荐) 标记为临时，这样schedule-handler在传送后可以清理它
          records[current_index].temporary = true

          -- 4. 将修改后的完整记录列表写回火车
          schedule.set_records(records)

          log_debug("传送门 DEBUG (teleport_next): [兼容性模式] 出口堵塞，已修改当前站点的等待条件使火车暂停。")
        end
      end
    end
  end
end

--- 检查火车进入
function TeleportHandler.check_carriage_at_location(surface, position)
  log_debug("传送门 DEBUG (check_carriage): 碰撞器触发！位置: " .. serpent.line(position) .. ", 地表: " .. surface.name)
  for _, struct in pairs(MOD_DATA.portals) do
    if struct.entity and struct.entity.valid and struct.watch_area and (not struct.carriage_behind or not struct.carriage_behind.valid) and struct.surface == surface and Util.position_in_rect(struct.entity.bounding_box, position) then
      local carriages = surface.find_entities_filtered { type = Constants.stock_types, area = struct.watch_area }
      if not (carriages and #carriages > 0 and carriages[1].train and carriages[1].train.valid) then
        -- 如果找不到有效的火车，则跳过此传送门
        goto continue
      end
      local train = carriages[1].train

      -- 【新功能 新增】火车传送消耗逻辑
      if is_resource_cost_enabled() then
        log_debug("传送门 DEBUG (check_carriage): [资源消耗] 模式已启用，开始检查火车传送消耗...")
        local opposite = State.get_opposite_struct(struct)
        if not opposite then
          log_debug("传送门 DEBUG (check_carriage): [资源消耗] 传送门未配对，跳过消耗检查。")
        else
          local portal_inventory = struct.entity.get_inventory(defines.inventory.assembling_machine_input)
          if not portal_inventory then
            log_debug("传送门 错误 (check_carriage): [资源消耗] 无法获取传送门输入物品栏！")
            return                             -- 严重错误，中断
          end

          -- 1. 定义火车传送需要消耗的物品
          local items_to_consume = { { name = "chuansongmen-exotic-matter", count = 1 } }

          -- 2. 调用新的共享资源消耗函数
          local result = Util.consume_shared_resources(nil, struct, opposite, items_to_consume)                               -- player为nil，将向所有人广播

          -- 3. 根据结果进行处理
          if result.success then
            -- 在成功消耗了资源的那个传送门产出碎片
            local producer_portal = result.consumed_at
            local output_inventory = producer_portal.entity.get_inventory(defines.inventory.assembling_machine_output)
            if output_inventory then
              output_inventory.insert({ name = "chuansongmen-spacetime-shard", count = 3 })
            end

            -- 检查是否在本次消耗后耗尽，并发出提示
            local final_inv = producer_portal.entity.get_inventory(defines.inventory.assembling_machine_input)
            if final_inv and final_inv.get_item_count("chuansongmen-exotic-matter") == 0 then
              log_debug("传送门 警告 (check_carriage): [资源消耗] 奇异物质已在本次传送中耗尽。")
              game.print({ "messages.chuansongmen-warning-exotic-matter-depleted-train", producer_portal.name,
                producer_portal.id })
            end
            log_debug("传送门 DEBUG (check_carriage): [资源消耗] 消耗完毕。")
          else
            -- 如果消耗失败，则执行停止火车的逻辑并中断传送
            if not train.manual_mode then
              local schedule = train.get_schedule()
              if schedule then
                local current_index = schedule.current
                log_debug("传送门 DEBUG (check_carriage): [时刻表修复] 火车时刻表将被修正。当前目标索引: " .. current_index)
                local new_record_index = current_index + 1
                schedule.add_record({
                  station = struct.station.backer_name,
                  wait_conditions = { { type = "time", ticks = 9999999 * 60 } },
                  temporary = true,
                  index = { schedule_index = new_record_index }
                })
                schedule.go_to_station(new_record_index)
                log_debug("传送门 DEBUG (check_carriage): [时刻表修复] 已在下一站插入临时路障站点，并重定向火车目标。")
              end
            else
              log_debug("传送门 DEBUG (check_carriage): [时刻表修复] 火车处于手动模式，跳过时刻表修改。")
            end
            return                                           -- 关键：中断函数，传送序列不会开始
          end
        end
      end
      -- 【新功能 结束】

      log_debug("传送门 DEBUG (check_carriage): 碰撞发生在 ID: " .. struct.id .. " 附近, 找到 " .. #carriages .. " 节车厢。")
      log_debug("传送门 DEBUG (check_carriage): 成功捕获到火车: " .. carriages[1].name)
      struct.carriage_behind = carriages[1]
      struct.carriage_ahead = nil
      log_debug("传送门 DEBUG (check_carriage): 设置待传送车厢为: " .. struct.carriage_behind.name)
      return
    end
    ::continue::
  end
end

-- =================================================================================
-- SE 兼容性：速度同步
-- =================================================================================

function TeleportHandler.hypertrain_sync_speed(carriage_a, carriage_a_direction, carriage_b, carriage_b_direction)
  local train_a = carriage_a.train
  local train_b = carriage_b.train
  local total_weight = train_a.weight + train_b.weight
  local average_speed = ((train_a.weight * math.abs(train_a.speed)) + (train_b.weight * math.abs(train_b.speed))) /
      total_weight
  local max_train_speed = 0.5
  average_speed = math.min(average_speed, max_train_speed)
  train_a.speed = average_speed * carriage_a_direction * Chuansongmen.train_forward_sign(carriage_a)
  train_b.speed = average_speed * carriage_b_direction * Chuansongmen.train_forward_sign(carriage_b)
end

function TeleportHandler.hypertrain_manage_speed(struct)
  if struct.carriage_behind and struct.carriage_behind.valid and struct.carriage_ahead and struct.carriage_ahead.valid then
    if not struct.carriage_behind.train.manual_mode then
      struct.carriage_behind.train.manual_mode = true
    end
    local passive_train_speed = 0.5
    local train_behind = struct.carriage_behind.train
    local train_ahead = struct.carriage_ahead.train
    if math.abs(train_behind.speed) < passive_train_speed then
      local speed_direction = Chuansongmen.elevator_east_sign(struct) *
          Chuansongmen.carriage_east_sign(struct.carriage_behind) *
          Chuansongmen.train_forward_sign(struct.carriage_behind)
      train_behind.speed = passive_train_speed * speed_direction
    end
    if math.abs(train_ahead.speed) < passive_train_speed then
      local speed_direction = Chuansongmen.elevator_east_sign(struct) *
          Chuansongmen.carriage_east_sign(struct.carriage_ahead) * Chuansongmen.train_forward_sign(struct.carriage_ahead)
      train_ahead.speed = passive_train_speed * speed_direction
    end
    TeleportHandler.hypertrain_sync_speed(
      struct.carriage_behind,
      Chuansongmen.elevator_east_sign(struct) * Chuansongmen.carriage_east_sign(struct.carriage_behind),
      struct.carriage_ahead,
      Chuansongmen.elevator_east_sign(struct) * Chuansongmen.carriage_east_sign(struct.carriage_ahead)
    )
  end
end

return TeleportHandler
