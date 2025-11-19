-- /scripts/cybersyn-compat.lua
-- 【最终修正版 v4 - 完美伪装策略】
-- 修复了伪造对象缺少 .valid 属性导致被 Cybersyn 删除的问题。

local CybersynCompat = {}
local State = nil -- <--- 添加这一行

local log_debug = function() end

CybersynCompat.is_present = false
CybersynCompat.BUTTON_NAME = "chuansongmen_cybersyn_connect_switch"

function CybersynCompat.set_logger(logger_func)
  if logger_func then
    log_debug = logger_func
    log_debug("传送门 Cybersyn 兼容: 成功接收到来自 control.lua 的 debug logger。")
  end
end

function CybersynCompat.init(dependencies)
  State = dependencies.State -- <--- 添加这一行来保存 State 模块
  if remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"] then
    CybersynCompat.is_present = true
    log_debug("传送门 Cybersyn 兼容: Cybersyn 已加载。将使用'完美伪装'策略进行原生集成。")
  else
    CybersynCompat.is_present = false
  end
end

local function sorted_pair_key(a, b)
  if a < b then return a .. "|" .. b else return b .. "|" .. a end
end

function CybersynCompat.update_connection(portal_struct, opposite_struct, connect, player)
  if not CybersynCompat.is_present then
    if player then player.print({ "messages.chuansongmen-error-cybersyn-not-found" }) end
    return
  end

  local station1 = portal_struct.station
  local station2 = opposite_struct.station

  if not (station1 and station1.valid and station2 and station2.valid) then
    if player then player.print({ "messages.chuansongmen-error-cybersyn-no-station" }) end
    return
  end

  local surface_pair_key = sorted_pair_key(station1.surface.index, station2.surface.index)
  local entity_pair_key = sorted_pair_key(station1.unit_number, station2.unit_number)

  local success = false
  pcall(function()
    if connect then
      -- 【完美伪装】构建一个包含必要属性的假对象，特别是 valid = true
      local fake_station1 = {
        valid = true,                          -- 关键！骗过 Cybersyn 的垃圾清理检查
        name = "se-space-elevator-train-stop", -- 关键！骗过 SE 兼容脚本的类型检查
        unit_number = station1.unit_number,
        surface = { index = station1.surface.index, name = station1.surface.name, valid = true },
        position = station1.position,
        operable = true
      }
      -- 注意：我们只需要伪装其中一个站点，Cybersyn 就会认为这是一条电梯连接

      -- 构造 SE 数据库所需的完整记录
      local ground_portal, orbit_portal
      if portal_struct.surface.index < opposite_struct.surface.index then
        ground_portal = portal_struct
        orbit_portal = opposite_struct
      else
        ground_portal = opposite_struct
        orbit_portal = portal_struct
      end

      -- 我们必须传递真实的实体给 se_elevators，因为 SE 可能会用它们来检查位置
      local ground_end_data = {
        elevator = ground_portal.entity,
        stop = ground_portal.station,
        surface_id = ground_portal
            .surface.index,
        stop_id = ground_portal.station.unit_number,
        elevator_id = ground_portal.entity.unit_number
      }
      local orbit_end_data = {
        elevator = orbit_portal.entity,
        stop = orbit_portal.station,
        surface_id = orbit_portal
            .surface.index,
        stop_id = orbit_portal.station.unit_number,
        elevator_id = orbit_portal.entity.unit_number
      }

      local fake_elevator_data = {
        ground = ground_end_data,
        orbit = orbit_end_data,
        cs_enabled = true,
        network_masks = nil,
        [ground_portal.surface.index] = ground_end_data,
        [orbit_portal.surface.index] = orbit_end_data
      }

      -- 1. 写入 SE 电梯数据库 (使用真实实体，通过深度验证)
      remote.call("cybersyn", "write_global", fake_elevator_data, "se_elevators", ground_portal.station.unit_number)
      remote.call("cybersyn", "write_global", fake_elevator_data, "se_elevators", orbit_portal.station.unit_number)

      -- 2. 写入地表连接数据库 (使用伪装实体，通过名字检查)
      local connection_data = {
        entity1 = (station1.unit_number < station2.unit_number) and fake_station1 or station2,
        entity2 = (station1.unit_number < station2.unit_number) and station2 or fake_station1,
      }
      local entity_pair_table = { [entity_pair_key] = connection_data }
      remote.call("cybersyn", "write_global", entity_pair_table, "connected_surfaces", surface_pair_key)

      log_debug("传送门 Cybersyn 兼容: [完美伪装] 连接已建立。")
      success = true
    else
      remote.call("cybersyn", "write_global", nil, "se_elevators", station1.unit_number)
      remote.call("cybersyn", "write_global", nil, "se_elevators", station2.unit_number)
      remote.call("cybersyn", "write_global", nil, "connected_surfaces", surface_pair_key)
      log_debug("传送门 Cybersyn 兼容: 连接已断开并清理。")
      success = true
    end
  end)

  if success then
    portal_struct.cybersyn_connected = connect
    opposite_struct.cybersyn_connected = connect
    if player then
      if connect then
        player.print({ "messages.chuansongmen-info-cybersyn-connected", portal_struct.name })
      else
        player.print({ "messages.chuansongmen-info-cybersyn-disconnected", portal_struct.name })
      end
    end
  end
end

function CybersynCompat.on_portal_destroyed(portal_struct)
  if not CybersynCompat.is_present then return end
  if portal_struct and portal_struct.cybersyn_connected then
    local opposite_struct = State.get_opposite_struct(portal_struct)
    if opposite_struct and portal_struct.station.valid and opposite_struct.station.valid then
      CybersynCompat.update_connection(portal_struct, opposite_struct, false, nil)
    end
  end
end

return CybersynCompat
