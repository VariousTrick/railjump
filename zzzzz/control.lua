-- control.lua (传送门 Mod)
-- 功能：作为 Mod 的主入口和协调器，处理事件分发和模块初始化。
-- 版本：v88.4 (模块化重构 - TeleportHandler 分离，最终格式修正)

log("传送门 DEBUG (control.lua): 开始加载 control.lua ...")

-- 【v94 新增】调试日志开关
local DEBUG_LOGGING_ENABLED = false -- 设置为 true 开启日志，设置为 false 关闭日志

-- 【数据迁移】全局标志位，用于触发延迟迁移
local migration_needed = false

local function log_debug(message)
  if DEBUG_LOGGING_ENABLED then
    log(message)
  end
end



--- 【新功能 新增】辅助函数，用于检查资源消耗模式是否启用
local function is_resource_cost_enabled()
  -- 使用安全的短路求值方式读取设置
  return settings.startup["chuansongmen-enable-resource-cost"] and
      settings.startup["chuansongmen-enable-resource-cost"].value or false
end

-- =================================================================================
-- 模块加载
-- =================================================================================
local Constants = require("scripts.constants")
local State = require("scripts.state")
local Util = require("scripts.util")
local GUI = require("scripts.gui")
local PortalManager = require("scripts.portal_manager")
local TeleportHandler = require("scripts.teleport_handler")

local CybersynCompat = require("scripts.cybersyn-compat")
local ScheduleHandler = require("scripts.schedule-handler")

local CybersynScheduler = require("scripts.cybersyn_scheduler")

local util = require("util")
-- 【SE 兼容】获取 Space Exploration 的列车传送事件ID
local SE_TELEPORT_STARTED_EVENT_ID = nil
local SE_TELEPORT_FINISHED_EVENT_ID = nil

-- =================================================================================
-- 核心逻辑 (剩余部分)
-- =================================================================================

Chuansongmen = {} -- 全局表，用于存放尚未被完全模块化的函数

-- 在 on_load 事件中进行初始化，确保 SE 已经加载完毕
local function initialize_se_events()
  if script.active_mods["space-exploration"] and remote.interfaces["space-exploration"] then
    log_debug("传送门 SE 兼容: 检测到 Space Exploration，正在获取传送事件 ID...")
    local get_started_event = remote.call("space-exploration", "get_on_train_teleport_started_event")
    local get_finished_event = remote.call("space-exploration", "get_on_train_teleport_finished_event")
    if get_started_event and get_finished_event then
      SE_TELEPORT_STARTED_EVENT_ID = get_started_event
      SE_TELEPORT_FINISHED_EVENT_ID = get_finished_event
      log_debug("传送门 SE 兼容: 成功获取事件 ID。")
    else
      log_debug("传送门 SE 兼容: 警告 - 无法从 SE 获取传送事件 ID，状态同步可能失败。")
    end
  end
end

-- 备注：以下几个函数暂时保留在 control.lua，因为它们是全局性的辅助函数。
function Chuansongmen.elevator_east_sign(struct)
  -- 【崩溃修复】正确处理南北/东西方向的映射
  -- 东(East)和南(South)方向使用同一个模型，逻辑上视为+1
  if struct.direction == defines.direction.east or struct.direction == defines.direction.south then
    return 1
  else -- 北(North)和西(West)方向使用另一个模型，逻辑上视为-1
    return -1
  end
end

function Chuansongmen.carriage_east_sign(carriage)
  return carriage.orientation < 0.5 and 1 or -1
end

function Chuansongmen.train_forward_sign(carriage_a)
  local sign = 1
  if #carriage_a.train.carriages == 1 then return sign end
  local carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.front)
  if not carriage_b then
    carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.back)
    sign = -sign
  end
  for _, carriage in pairs(carriage_a.train.carriages) do
    if carriage == carriage_b then return sign end
    if carriage == carriage_a then return -sign end
  end
end

-- =================================================================================================
-- 全局初始化与依赖注入
-- =================================================================================================

local function initialize_all_modules()
  State.initialize_globals()
  if State.set_logger then State.set_logger(log_debug) end
  if Util.set_debug_mode then Util.set_debug_mode(DEBUG_LOGGING_ENABLED) end
  if ScheduleHandler.set_debug_mode then ScheduleHandler.set_debug_mode(DEBUG_LOGGING_ENABLED) end
  if CybersynCompat.set_logger then CybersynCompat.set_logger(log_debug) end

  local gui_deps = { State = State, Chuansongmen = Chuansongmen, CybersynCompat = CybersynCompat, log_debug = log_debug }
  if GUI.init then GUI.init(gui_deps) end

  local pm_deps = {
    State = State,
    GUI = GUI,
    Constants = Constants,
    Util = Util,
    Chuansongmen = Chuansongmen,
    log_debug =
        log_debug
  }
  if PortalManager.init then PortalManager.init(pm_deps) end

  if PortalManager.init then PortalManager.init(pm_deps) end

  -- 【关键】为 TeleportHandler 模块注入所有它需要的依赖
  local th_deps = {
    Constants = Constants, -- 【v88.6 修复】添加缺失的 Constants 依赖
    State = State,
    Util = Util,
    ScheduleHandler = ScheduleHandler,
    Chuansongmen = Chuansongmen,
    log_debug = log_debug,
    SE_TELEPORT_STARTED_EVENT_ID = SE_TELEPORT_STARTED_EVENT_ID,
    SE_TELEPORT_FINISHED_EVENT_ID = SE_TELEPORT_FINISHED_EVENT_ID
  }
  if TeleportHandler.init then TeleportHandler.init(th_deps) end

  -- 【修复】将 State 模块注入到 CybersynCompat 中
  local cybersyn_deps = { State = State }
  CybersynCompat.init(cybersyn_deps)

  if CybersynCompat.is_present and CybersynCompat.set_portal_accessor then
    CybersynCompat.set_portal_accessor(Chuansongmen.find_portal_path_for_cybersyn)
  end
end


-- =================================================================================================
-- 事件处理钩子
-- =================================================================================================

script.on_init(function()
  initialize_all_modules()
  log_debug("传送门 DEBUG (event): on_init 触发。")
end
)

script.on_load(function()
  -- 【v88.5 修复】先获取 SE 事件 ID
  initialize_se_events()
  -- 然后再调用一次完整的模块初始化，这样可以确保所有依赖（包括刚获取的 SE ID）都被正确注入
  initialize_all_modules()

  -- =======================================================
  -- 【数据迁移 - 步骤1: 预检查】
  -- 在 on_load 中只读检查，不修改 storage，以确定是否需要迁移
  -- =======================================================
  log_debug("传送门 DEBUG (on_load): [预检查] 正在检查是否存在旧版本数据...")
  for _, portal_struct in pairs(MOD_DATA.portals) do
    if portal_struct.power_connection_status == nil or portal_struct.power_grid_expires_at == nil then
      migration_needed = true
      log_debug("传送门 DEBUG (on_load): [预检查] 发现旧数据，已标记需要迁移。")
      break -- 只要发现一个，就可以停止检查了
    end
  end
  -- =======================================================

  log_debug("传送门 DEBUG (event): on_load 触发。")
end)

script.on_configuration_changed(function(event)
  initialize_all_modules()

  -- =======================================================
  -- 【数据迁移】处理Mod版本更新或旧存档兼容性问题
  -- 这是Factorio API规定进行此类修改的唯一正确位置
  -- =======================================================
  -- 通过检查 event.mod_changes，确保迁移只在Mod更新后第一次加载时运行
  local old_version = event.mod_changes and event.mod_changes["zzzzz"] and event.mod_changes["zzzzz"].old_version
  if old_version then
    log_debug("传送门 DEBUG (on_config_changed): 检测到Mod更新，从版本 " .. old_version .. " 开始迁移数据...")

    -- (这里是我们从 on_load 剪切过来的脚本)
    for _, portal_struct in pairs(MOD_DATA.portals) do
      -- 迁移 power_connection_status 状态
      if portal_struct.power_connection_status == nil then
        log_debug("传送门 DEBUG (on_config_changed): 正在为传送门 " .. portal_struct.id .. " 迁移电网状态...")
        if portal_struct.power_connected == true then
          portal_struct.power_connection_status = "connected"
        else
          portal_struct.power_connection_status = "disconnected"
        end
        portal_struct.power_connected = nil
      end

      -- 迁移 power_grid_expires_at 计时器
      if portal_struct.power_grid_expires_at == nil then
        log_debug("传送门 DEBUG (on_config_changed): 正在为传送门 " .. portal_struct.id .. " 初始化电网计时器...")
        portal_struct.power_grid_expires_at = 0
      end
    end
    log_debug("传送门 DEBUG (on_config_changed): 数据迁移完成。")
  end
  -- =======================================================

  log_debug("传送门 DEBUG (event): on_configuration_changed 触发。")
end)

function Chuansongmen.find_portal_path_for_cybersyn(source_surface_index, destination_surface_index)
  log_debug("传送门 DEBUG (find_portal_path_for_cybersyn): 正在查找从地表 " ..
    source_surface_index .. " 到 " .. destination_surface_index .. " 的传送门路径...")
  for _, portal_A in pairs(MOD_DATA.portals) do
    if portal_A.surface.index == source_surface_index and portal_A.paired_to_id and portal_A.cybersyn_connected then
      local portal_B = State.get_opposite_struct(portal_A)
      if portal_B and portal_B.surface.index == destination_surface_index then
        log_debug("传送门 DEBUG (find_portal_path_for_cybersyn): 找到路径！入口 ID: " .. portal_A.id .. ", 出口 ID: " .. portal_B.id)
        return portal_A, portal_B
      end
    end
  end
  log_debug("传送门 DEBUG (find_portal_path_for_cybersyn): 未找到可用的传送门路径。")
  return nil, nil
end

function Chuansongmen.are_directions_compatible(direction1, direction2)
  if direction1 == direction2 then return true, "SAME" end
  return false, "MISMATCH"
end

function Chuansongmen.force_clear_trains_in_area(struct)
  if not (struct and struct.entity and struct.entity.valid) then return end
  log_debug("传送门 DEBUG (force_clear_trains_in_area): 开始为传送门 ID " .. struct.id .. " 强制清理区域内的火车...")
  local area = {
    { struct.position.x - Constants.deconstruction_check_radius, struct.position.y - Constants.deconstruction_check_radius },
    { struct.position.x + Constants.deconstruction_check_radius, struct.position.y + Constants.deconstruction_check_radius }
  }
  local train_parts = struct.surface.find_entities_filtered { area = area, type = Constants.stock_types }
  if #train_parts > 0 then
    log_debug("传送门 DEBUG (force_clear_trains_in_area): 找到 " .. #train_parts .. " 节火车部件，正在强制销毁...")
    for _, part in pairs(train_parts) do
      if part and part.valid then
        part.destroy()
      end
    end
    log_debug("传送门 DEBUG (force_clear_trains_in_area): 火车部件销毁完毕。")
  else
    log_debug("传送门 DEBUG (force_clear_trains_in_area): 区域内无火车，无需清理。")
  end
end

--- 【重写】处理玩家传送请求 (移除了goto以修复作用域bug)
local function process_player_teleport_requests()
  if not (MOD_DATA.players_to_teleport and next(MOD_DATA.players_to_teleport)) then
    return -- 如果没有请求，则直接退出
  end

  log_debug("传送门 DEBUG (on_tick): [玩家传送] 检测到待处理的传送请求...")

  for player_index, request in pairs(MOD_DATA.players_to_teleport) do
    local player = game.get_player(player_index)
    local my_data = State.get_struct_by_id(request.portal_id)
    local can_teleport = true -- 设置一个标志位，用于追踪所有检查是否通过

    -- 检查1：玩家和传送门是否有效
    if not (player and player.valid and my_data and my_data.entity and my_data.entity.valid) then
      can_teleport = false
    end

    -- 检查2：对侧传送门是否有效
    local opposite = nil
    if can_teleport then
      opposite = State.get_opposite_struct(my_data)
      if not (opposite and opposite.entity and opposite.entity.valid) then
        player.print({ "messages.chuansongmen-error-invalid-target-teleport" })
        can_teleport = false
      end
    end

    -- 检查3：距离是否过远 (仅在有消耗模式)
    if can_teleport and is_resource_cost_enabled() then
      local function calculate_distance(pos1, pos2)
        local dx = pos1.x - pos2.x
        local dy = pos1.y - pos2.y
        return math.sqrt(dx * dx + dy * dy)
      end
      local distance = calculate_distance(player.position, my_data.entity.position)
      local max_distance = 25
      if distance > max_distance then
        log_debug("传送门 DEBUG (on_tick): [玩家传送] 玩家 " .. player.name .. " 因距离过远 (" .. distance .. ") 而传送失败。")
        player.print({ "messages.chuansongmen-error-player-too-far" })
        can_teleport = false
      end
    end

    -- 检查4：资源是否充足 (仅在有消耗模式)
    if can_teleport and is_resource_cost_enabled() then
      log_debug("传送门 DEBUG (on_tick): [玩家传送] 正在为玩家 " .. player.name .. " 处理有消耗传送...")
      local items_to_consume = {
        { name = "chuansongmen-exotic-matter",       count = 1 },
        { name = "chuansongmen-personal-stabilizer", count = 1 }
      }
      local result = Util.consume_shared_resources(player, my_data, opposite, items_to_consume)

      if result.success then
        local producer_portal = result.consumed_at
        local output_inventory = producer_portal.entity.get_inventory(defines.inventory.assembling_machine_output)
        if output_inventory then
          output_inventory.insert({ name = "chuansongmen-spacetime-shard", count = 3 })
        end

        local final_inv = producer_portal.entity.get_inventory(defines.inventory.assembling_machine_input)
        if final_inv and final_inv.get_item_count("chuansongmen-exotic-matter") == 0 then
          player.print({ "messages.chuansongmen-warning-exotic-matter-depleted", producer_portal.name })
        end
      else
        -- 资源不足，传送失败
        can_teleport = false
      end
    end

    -- 【最终执行】如果所有检查都通过了，才执行传送
    if can_teleport then
      local landing_pos = { x = opposite.entity.position.x, y = opposite.entity.position.y + 16 }
      player.teleport(landing_pos, opposite.entity.surface)
      if player.opened then player.opened = nil end
      log_debug("传送门 DEBUG (on_tick): [玩家传送] 玩家 " .. player.name .. " 传送成功。")
    end
  end

  -- 清空所有已处理的请求
  MOD_DATA.players_to_teleport = {}
end

local function on_tick(event)
  -- =======================================================
  -- 【数据迁移 - 步骤2: 延迟执行】
  -- 在第一个 on_tick 中执行实际的迁移操作，这里允许修改 storage
  -- =======================================================
  if migration_needed then
    log_debug("传送门 DEBUG (on_tick): [延迟迁移] 开始执行数据迁移...")
    for _, portal_struct in pairs(MOD_DATA.portals) do
      -- 迁移 power_connection_status 状态
      if portal_struct.power_connection_status == nil then
        if portal_struct.power_connected == true then
          portal_struct.power_connection_status = "connected"
        else
          portal_struct.power_connection_status = "disconnected"
        end
        portal_struct.power_connected = nil
      end

      -- 迁移 power_grid_expires_at 计时器
      if portal_struct.power_grid_expires_at == nil then
        portal_struct.power_grid_expires_at = 0
      end
    end
    migration_needed = false -- 关闭标志位，确保迁移只执行一次
    log_debug("传送门 DEBUG (on_tick): [延迟迁移] 数据迁移完成。")
  end
  -- =======================================================

  -- ======================================================================
  -- 【新增逻辑】持续速度管理 (每 1 tick 执行)
  -- 这是一个独立的循环，专门用于给正在传送的火车提供持续动力
  -- ======================================================================
  for _, struct in pairs(MOD_DATA.portals) do
    if struct and struct.entity and struct.entity.valid then
      -- 如果传送门正在进行传送（即入口和出口都有火车/车厢存在）
      if struct.carriage_behind and struct.carriage_behind.valid and struct.carriage_ahead and struct.carriage_ahead.valid then
        -- 调用速度管理器，强制维持火车动力
        TeleportHandler.hypertrain_manage_speed(struct)
      end
    end
  end

  -- ======================================================================
  -- 【原有逻辑】处理碰撞器重建和车厢传送 (保持原有的分散 Tick 执行)
  -- ======================================================================
  for _, struct in pairs(MOD_DATA.portals) do
    if struct.entity and struct.entity.valid then
      -- 1. 检查并重建碰撞器
      if event.tick % 60 == struct.id % 60 then
        if not (struct.collider and struct.collider.valid) then
          local se_direction = (struct.direction == defines.direction.east or struct.direction == defines.direction.south) and
              defines.direction.east or defines.direction.west
          local collider_pos_offset = Constants.space_elevator_collider_position[se_direction]
          if collider_pos_offset then
            log_debug("传送门 DEBUG (on_tick): 传送门 " .. struct.id .. " 的碰撞器无效，正在重建...")
            struct.collider = struct.surface.create_entity { name = "chuansongmen-collider", position = Util.vectors_add(struct.position, collider_pos_offset), force = "neutral" }
          end
        end
      end

      -- 2. 触发下一节车厢的传送
      if event.tick % Constants.teleport_next_tick_frequency == struct.unit_number % Constants.teleport_next_tick_frequency then
        local opposite = State.get_opposite_struct(struct)
        if opposite and opposite.surface then
          if struct.carriage_behind and struct.carriage_behind.valid then
            TeleportHandler.teleport_next(struct)
          end
        else
          if struct.carriage_behind or struct.carriage_ahead then
            struct.carriage_behind, struct.carriage_ahead = nil, nil
          end
        end
      end

      -- 【注意】原有的 TeleportHandler.hypertrain_manage_speed(struct) 已从此循环移除
      -- 因为它已经移动到了上方的新增循环中执行
    end
  end

  -- 【“唤醒”逻辑升级版 v2.0】
  if is_resource_cost_enabled() and (event.tick % 60 == 0) then -- 每秒检查一次以保证性能
    for _, struct in pairs(MOD_DATA.portals) do
      -- 首先检查，当前传送门附近是否有正在等待的火车
      if struct.entity and struct.entity.valid and struct.watch_area then
        local carriages = struct.surface.find_entities_filtered { area = struct.watch_area, type = Constants.stock_types, limit = 1 }
        if carriages and #carriages > 0 then
          local train = carriages[1].train
          local schedule = train and train.get_schedule()
          if schedule then
            local record = schedule.get_record({ schedule_index = schedule.current })
            -- 确认这辆火车确实是因为燃料问题而停下的
            if record and record.temporary and record.station == struct.station.backer_name and record.wait_conditions and #record.wait_conditions == 1 and record.wait_conditions[1].type == "time" and record.wait_conditions[1].ticks > 999999 then
              -- 【核心改动】现在我们来检查整个网络的燃料
              local has_fuel = false

              -- 1. 检查本地燃料
              local local_inv = struct.entity.get_inventory(defines.inventory.assembling_machine_input)
              if local_inv and local_inv.get_item_count("chuansongmen-exotic-matter") > 0 then
                has_fuel = true
              end

              -- 2. 如果本地没有，再检查对侧燃料
              if not has_fuel then
                local opposite = State.get_opposite_struct(struct)
                if opposite then
                  local opposite_inv = opposite.entity.get_inventory(defines.inventory.assembling_machine_input)
                  if opposite_inv and opposite_inv.get_item_count("chuansongmen-exotic-matter") > 0 then
                    has_fuel = true
                  end
                end
              end

              -- 3. 如果整个网络中任何一处有燃料，就唤醒火车
              if has_fuel then
                log_debug("传送门 DEBUG (on_tick): [唤醒逻辑] 发现传送网络已补充燃料，且有火车正在等待。")
                log_debug("传送门 DEBUG (on_tick): [唤醒逻辑] 火车ID: " .. train.id .. ", 正在移除其临时路障站点...")

                schedule.remove_record({ schedule_index = schedule.current })

                log_debug("传送门 DEBUG (on_tick): [唤醒逻辑] 手动触发传送检测...")
                TeleportHandler.check_carriage_at_location(struct.surface, carriages[1].position)
              end
            end
          end
        end
      end
    end
  end


  -- 【最终修复 - 重构】处理所有玩家传送请求

  -- =======================================================
  -- 【电网维持 - 核心逻辑 v3.0 - 续期/到期 与 自动唤醒】
  -- =======================================================
  -- 每秒检查一次，以分散计算负载
  if event.tick % 60 == 0 then
    if is_resource_cost_enabled() then
      for _, struct_A in pairs(MOD_DATA.portals) do
        -- 我们只对主控传送门进行检查，避免对同一个网络重复操作
        if struct_A.is_power_primary then
          local struct_B = State.get_opposite_struct(struct_A)
          if not struct_B then goto continue end -- 如果对侧无效，则跳过

          -- 逻辑分支一：处理已连接的电网 (续期或到期)
          if struct_A.power_connection_status == "connected" and game.tick > struct_A.power_grid_expires_at then
            log_debug("传送门 DEBUG (on_tick): [电网维持] 网络 " .. struct_A.id .. "<->" .. struct_B.id .. " 服务已到期，处理续期...")

            local inv_A = struct_A.entity.get_inventory(defines.inventory.assembling_machine_input)
            local inv_B = struct_B.entity.get_inventory(defines.inventory.assembling_machine_input)
            local count_A = inv_A and inv_A.get_item_count("chuansongmen-spacetime-shard") or 0
            local count_B = inv_B and inv_B.get_item_count("chuansongmen-spacetime-shard") or 0

            if (count_A + count_B) < 2 then
              -- 【续期失败】-> 状态变为“系统断开”
              log_debug("传送门 DEBUG (on_tick): [电网维持] 续期失败，网络碎片总数 (" .. (count_A + count_B) .. ") 不足2个。断开电网...")
              PortalManager.disconnect_portal_power(nil, struct_A.id) -- player为nil，状态会变为 "disconnected_by_system"

              local gps_tag_A = "[gps=" ..
                  struct_A.position.x .. "," .. struct_A.position.y .. "," .. struct_A.surface.name .. "]"
              for _, player in pairs(game.players) do
                if settings.get_player_settings(player)["chuansongmen-show-power-warnings"].value == true then
                  player.print({ "messages.chuansongmen-warning-power-disconnected-shards", gps_tag_A, struct_A.name,
                    struct_B.name })
                end
              end
            else
              -- 【续期成功】
              if count_A > 0 then
                inv_A.remove({ name = "chuansongmen-spacetime-shard", count = 1 })
              else
                inv_B.remove({
                  name =
                  "chuansongmen-spacetime-shard",
                  count = 1
                })
              end
              if count_B > 0 then
                inv_B.remove({ name = "chuansongmen-spacetime-shard", count = 1 })
              else
                inv_A.remove({
                  name =
                  "chuansongmen-spacetime-shard",
                  count = 1
                })
              end

              local duration_in_minutes = settings.global["chuansongmen-power-grid-duration"].value
              local duration_in_ticks = duration_in_minutes * 60 * 60

              local new_expires_at = struct_A.power_grid_expires_at + duration_in_ticks
              struct_A.power_grid_expires_at = new_expires_at
              struct_B.power_grid_expires_at = new_expires_at
              log_debug("传送门 DEBUG (on_tick): [电网维持] 续期成功，消耗2个碎片。新的到期tick: " .. new_expires_at)
            end

            -- 逻辑分支二：处理等待唤醒的电网 (自动重连)
          elseif struct_A.power_connection_status == "disconnected_by_system" then
            log_debug("传送门 DEBUG (on_tick): [电网唤醒] 正在检查网络 " .. struct_A.id .. "<->" .. struct_B.id .. " 是否可以自动重连...")

            local inv_A = struct_A.entity.get_inventory(defines.inventory.assembling_machine_input)
            local inv_B = struct_B.entity.get_inventory(defines.inventory.assembling_machine_input)
            local count_A = inv_A and inv_A.get_item_count("chuansongmen-spacetime-shard") or 0
            local count_B = inv_B and inv_B.get_item_count("chuansongmen-spacetime-shard") or 0

            if (count_A + count_B) >= 2 then
              -- 【唤醒成功】
              log_debug("传送门 DEBUG (on_tick): [电网唤醒] 碎片已补充，正在自动恢复电网连接...")

              -- 复用 connect_portal_power 的逻辑 (手动调用)
              if count_A > 0 then
                inv_A.remove({ name = "chuansongmen-spacetime-shard", count = 1 })
              else
                inv_B.remove({
                  name =
                  "chuansongmen-spacetime-shard",
                  count = 1
                })
              end
              if count_B > 0 then
                inv_B.remove({ name = "chuansongmen-spacetime-shard", count = 1 })
              else
                inv_A.remove({
                  name =
                  "chuansongmen-spacetime-shard",
                  count = 1
                })
              end

              struct_A.power_connection_status = "connected"
              struct_B.power_connection_status = "connected"

              local duration_in_minutes = settings.global["chuansongmen-power-grid-duration"].value
              local duration_in_ticks = duration_in_minutes * 60 * 60
              local expires_at = game.tick + duration_in_ticks
              struct_A.power_grid_expires_at = expires_at
              struct_B.power_grid_expires_at = expires_at

              PortalManager.connect_wires(struct_A, struct_B) -- 直接调用内部函数连接电线

              local gps_tag_A = "[gps=" ..
                  struct_A.position.x .. "," .. struct_A.position.y .. "," .. struct_A.surface.name .. "]"
              for _, player in pairs(game.players) do
                if settings.get_player_settings(player)["chuansongmen-show-power-warnings"].value == true then
                  player.print({ "messages.chuansongmen-info-power-reconnected-auto", gps_tag_A, struct_A.name, struct_B
                      .name })
                end
              end
            end
          end
        end
        ::continue::
      end
    end
  end
  -- =======================================================


  -- 调用 Cybersyn 兼容调度器的每帧逻辑
  if CybersynScheduler.on_tick then
    CybersynScheduler.on_tick()
  end

  process_player_teleport_requests()
end

-- =================================================================================
-- 事件监听器注册
-- =================================================================================
log_debug("传送门 DEBUG (control.lua): 注册事件监听器...")
script.on_event(defines.events.on_gui_click, GUI.handle_click)
script.on_event(defines.events.on_gui_checked_state_changed, GUI.handle_checked_state_changed)
script.on_event(defines.events.on_gui_selection_state_changed, GUI.handle_signal_selection) -- 【新增】监听玩家从信号选择界面选择图标的事件

script.on_event(defines.events.on_tick, on_tick)


-- 定义一个辅助函数判断是否为飞船地表
local function is_spaceship_surface(surface)
  return string.find(surface.name, "spaceship") ~= nil
end

script.on_event(defines.events.on_entity_cloned, function(event)
  local new_entity = event.destination
  local old_entity = event.source

  if not (new_entity and new_entity.valid) then return end

  -- =======================================================
  -- 分支 A: 唤醒 Cybersyn 控制器 (Combinator)
  -- =======================================================
  if new_entity.name == "cybersyn-combinator" then
    -- 逻辑：只有当新地表是飞船时，才唤醒控制器
    if is_spaceship_surface(new_entity.surface) then
      -- 唤醒！
      script.raise_event(defines.events.script_raised_built, { entity = new_entity })
      -- 这里不需要 log，避免大量刷屏
    end
    return     -- 控制器处理完毕，退出
  end

  -- =======================================================
  -- 分支 B: 传送门主体克隆
  -- =======================================================
  if new_entity.name == Constants.name_entity then
    local old_id = old_entity.unit_number
    local old_data = MOD_DATA.portals[old_id]

    if not old_data then return end

    log_debug("传送门 DEBUG (cloned): 传送门克隆 " .. old_id .. " -> " .. new_entity.unit_number)

    -- 1. 深度拷贝数据
    local new_data = util.table.deepcopy(old_data)

    -- 2. 更新基础信息
    new_data.unit_number = new_entity.unit_number
    new_data.entity = new_entity
    new_data.surface = new_entity.surface
    new_data.position = new_entity.position

    -- 3. 组件重连
    PortalManager.reconnect_internal_entities(new_data)

    -- 4. 保存新数据
    MOD_DATA.portals[new_entity.unit_number] = new_data

    -- 5. 物理线路重连 (对抗 SE 切线)
    if new_data.paired_to_id and new_data.power_connection_status == "connected" then
      local partner = State.get_struct_by_id(new_data.paired_to_id)
      if partner then
        local primary = new_data.is_power_primary and new_data or partner
        local secondary = new_data.is_power_primary and partner or new_data
        PortalManager.connect_wires(primary, secondary)
      end
    end

    -- >>>>> [关键逻辑] Cybersyn 智能迁移 >>>>>
    if new_data.cybersyn_connected then
      local old_is_space = is_spaceship_surface(old_entity.surface)
      local new_is_space = is_spaceship_surface(new_entity.surface)

      -- 定义降落：旧的是飞船，新的不是
      local is_landing = old_is_space and (not new_is_space)

      -- 调用兼容模块处理
      CybersynCompat.on_portal_cloned(old_data, new_data, is_landing)
    end
    -- <<<<< [逻辑结束] <<<<<

    -- 6. 删除旧数据
    MOD_DATA.portals[old_id] = nil
  end
end)


local function handle_built_entity(event)
  -- 增加对放置器名称的判断
  if event.entity and (event.entity.name == Constants.name_entity or event.entity.name == "chuansongmen-placer-entity") then
    PortalManager.on_built(event.entity)
  end
end

-- 修正后的注册方式：只需要传入事件ID和处理函数
script.on_event(defines.events.on_built_entity, handle_built_entity)

script.on_event(defines.events.on_robot_built_entity, handle_built_entity)

local function on_portal_removed(entity)
  if not (entity and entity.valid) then return end
  local struct = State.get_struct(entity)
  if not struct then
    log_debug("传送门 警告 (on_portal_removed): 找不到传送门实体的数据。")
    PortalManager.on_mined(entity)
    return
  end
  Chuansongmen.force_clear_trains_in_area(struct)
  CybersynCompat.on_portal_destroyed(struct)
  PortalManager.on_mined(entity)
end

script.on_event({ defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity }, function(event)
  if event and event.entity and event.entity.name == Constants.name_entity then
    log_debug("传送门 DEBUG (event): on_mined_entity 捕捉到传送门拆除。")
    on_portal_removed(event.entity)
  end
end
)

script.on_event(defines.events.on_entity_died, function(event)
  if event and event.entity and event.entity.name == Constants.name_entity then
    log_debug("传送门 DEBUG (event): on_entity_died 捕捉到传送门摧毁。")
    on_portal_removed(event.entity)
  end
end
)

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type == defines.gui_type.entity and event.entity and event.entity.name == Constants.name_entity then
    local player = game.get_player(event.player_index)
    if player and not player.vehicle then
      log_debug("传送门 DEBUG (event): on_gui_opened 捕捉到玩家打开传送门 GUI。")
      GUI.create_cybersyn_anchor_gui(player, event.entity)
      GUI.build_or_update(player, event.entity)
    end
  end
end
)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player or event.gui_type ~= defines.gui_type.entity then return end
  local relative_gui = player.gui.relative
  if relative_gui.chuansongmen_main_frame and relative_gui.chuansongmen_main_frame.valid then
    log_debug("传送门 DEBUG (event): on_gui_closed 捕捉到实体 GUI 关闭，销毁传送门 GUI...")
    relative_gui.chuansongmen_main_frame.destroy()
  end
  local anchor_frame = relative_gui.left and relative_gui.left["chuansongmen_anchor_frame"]
  if anchor_frame and anchor_frame.valid then
    anchor_frame.destroy()
  end
end
)

script.on_event(defines.events.on_trigger_created_entity, function(event)
  if event.entity and event.entity.name == Constants.name_train_collision_detector then
    log_debug("传送门 DEBUG (event): on_trigger_created_entity 捕捉到碰撞检测实体 '" ..
      Constants.name_train_collision_detector .. "' 创建！")
    TeleportHandler.check_carriage_at_location(event.entity.surface, event.entity.position)
  end
end
)

log_debug("传送门 DEBUG (control.lua): 事件监听器注册完毕。")




-- =================================================================================
-- 远程接口
-- =================================================================================
remote.add_interface("zchuansongmen", {
  pair_portals = function(...)
    PortalManager.pair_portals(...)
  end,
  unpair_portals = function(...)
    PortalManager.unpair_portals(...)
  end,
  update_portal_details = function(...) -- 【重构】替换为新的详情更新接口
    PortalManager.update_portal_details(...)
  end,
  -- =======================================================
  -- 【新增接口】暴露手动的电网控制函数
  -- =======================================================
  connect_portal_power = function(player_index, portal_id)
    local player = game.get_player(player_index)
    if player and portal_id then
      log_debug("传送门 DEBUG (remote): 接收到 connect_portal_power 远程调用, 正在转发给 PortalManager...")
      PortalManager.connect_portal_power(player, portal_id)
    end
  end,
  disconnect_portal_power = function(player_index, portal_id)
    local player = game.get_player(player_index)
    if player and portal_id then
      log_debug("传送门 DEBUG (remote): 接收到 disconnect_portal_power 远程调用, 正在转发给 PortalManager...")
      PortalManager.disconnect_portal_power(player, portal_id)
    end
  end
}
)



-- =================================================================================
-- 调试工具
-- =================================================================================
local serpent = {}
function serpent.dump(val, options)
  options = options or {}
  local lookup, totallookup = {}, 0
  local out = {}
  local O, T = " ", options.indent or ""
  local function D(v, t)
    if type(v) == "string" then
      local esc_str = string.gsub(v, "\\", "\\\\")
      esc_str = string.gsub(esc_str, "\n", "\\n")
      esc_str = string.gsub(esc_str, "\"", "\\\"")
      esc_str = string.gsub(esc_str, "\r", "\\r")
      return '"' .. esc_str .. '"'
    elseif type(v) == "number" then
      return tostring(v)
    elseif type(v) == "boolean" then
      return v and "true" or "false"
    elseif type(v) == "table" then
      if lookup[v] then return lookup[v] end
      totallookup = totallookup + 1
      lookup[v] = "table" .. totallookup
      out[totallookup] = "{"
      local o = {}
      for i, k in ipairs(v) do
        table.insert(o, T .. O .. "[" .. i .. "] = " .. D(k, T .. O))
      end
      for k, v_ in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > #v or k ~= math.floor(k) then
          table.insert(o, T .. O .. "[" .. D(k, T .. O) .. "] = " .. D(v_, T .. O))
        end
      end
      table.sort(o)
      out[totallookup] = out[totallookup] .. "\n" .. table.concat(o, ",\n") .. "\n" .. T .. "}"
      return lookup[v]
    else
      return tostring(v)
    end
  end
  local res = D(val, T)
  local outres = {}
  for i = 1, totallookup do
    table.insert(outres, "local table" .. i .. " = " .. out[i])
  end
  outres = table.concat(outres, "\n")
  res = (outres ~= "" and outres .. "\n" or "") .. "return " .. res
  return res
end

function serpent.line(val)
  local options = { indent = "", sortkeys = true, comment = false }
  local res = serpent.dump(val, options)
  res = string.gsub(res, "\n", " ")
  res = string.gsub(res, "local table%d+ = ", "")
  res = string.gsub(res, "return table%d+", "")
  res = string.gsub(res, "return ", "")
  res = string.gsub(res, "%s+", " ")
  res = string.gsub(res, "{%s*{", "{{")
  res = string.gsub(res, "}%s*}", "}}")
  return res
end

log_debug("传送门 DEBUG (control.lua): Serpent 库已嵌入。")

log_debug("传送门 DEBUG (control.lua): control.lua 加载完毕。")
