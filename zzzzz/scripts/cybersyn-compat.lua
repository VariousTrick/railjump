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
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug(
				"传送门 Cybersyn 兼容: Cybersyn 已加载。将使用'完美伪装'策略进行原生集成。"
			)
		end
	else
		CybersynCompat.is_present = false
	end
end

local function sorted_pair_key(a, b)
	if a < b then
		return a .. "|" .. b
	else
		return b .. "|" .. a
	end
end

function CybersynCompat.update_connection(portal_struct, opposite_struct, connect, player)
	if not CybersynCompat.is_present then
		if player then
			player.print({ "messages.chuansongmen-error-cybersyn-not-found" })
		end
		return
	end

	local station1 = portal_struct.station
	local station2 = opposite_struct.station

	if not (station1 and station1.valid and station2 and station2.valid) then
		if player then
			player.print({ "messages.chuansongmen-error-cybersyn-no-station" })
		end
		return
	end

	local surface_pair_key = sorted_pair_key(station1.surface.index, station2.surface.index)
	local entity_pair_key = sorted_pair_key(station1.unit_number, station2.unit_number)

	local success = false
	pcall(function()
		if connect then
			-- 【关键逻辑修改】
			-- Cybersyn 内部会强制按 unit_number 排序，ID 小的永远是 entity1。
			-- 且 Cybersyn 的时刻表生成器只检查 entity1 的名字。
			-- 所以，我们必须找出 ID 较小的那个车站，并对其进行伪装。
			local min_station, max_station
			if station1.unit_number < station2.unit_number then
				min_station = station1
				max_station = station2
			else
				min_station = station2
				max_station = station1
			end

			-- 基于 ID 较小的车站构建完美伪装对象
			local fake_station_for_check = {
				valid = true,
				name = "se-space-elevator-train-stop", -- 核心：骗过名字检查
				unit_number = min_station.unit_number, -- 核心：ID 必须对应
				surface = { index = min_station.surface.index, name = min_station.surface.name, valid = true },
				position = min_station.position,
				operable = true,
				backer_name = min_station.backer_name, -- 建议带上，虽然主要检查的是 name
			}

			-- 构造 SE 数据库所需的完整记录 (这部分逻辑保持不变，依赖 Surface Index)
			local ground_portal, orbit_portal
			if portal_struct.surface.index < opposite_struct.surface.index then
				ground_portal = portal_struct
				orbit_portal = opposite_struct
			else
				ground_portal = opposite_struct
				orbit_portal = portal_struct
			end

			-- 写入 se_elevators (这部分保持不变，使用真实实体)
			local ground_end_data = {
				elevator = ground_portal.entity, -- 注意：如果还遇到清理问题，这里可改为 ground_portal.station
				stop = ground_portal.station,
				surface_id = ground_portal.surface.index,
				stop_id = ground_portal.station.unit_number,
				elevator_id = ground_portal.entity.unit_number,
			}
			local orbit_end_data = {
				elevator = orbit_portal.entity, -- 同上
				stop = orbit_portal.station,
				surface_id = orbit_portal.surface.index,
				stop_id = orbit_portal.station.unit_number,
				elevator_id = orbit_portal.entity.unit_number,
			}

			local fake_elevator_data = {
				ground = ground_end_data,
				orbit = orbit_end_data,
				cs_enabled = true,
				network_masks = nil,
				[ground_portal.surface.index] = ground_end_data,
				[orbit_portal.surface.index] = orbit_end_data,
			}

			-- 1. 写入 SE 电梯数据库
			remote.call(
				"cybersyn",
				"write_global",
				fake_elevator_data,
				"se_elevators",
				ground_portal.station.unit_number
			)
			remote.call(
				"cybersyn",
				"write_global",
				fake_elevator_data,
				"se_elevators",
				orbit_portal.station.unit_number
			)

			-- 2. 写入地表连接数据库
			-- 【关键修改】entity1 必须是我们伪造的那个 (因为它 ID 小)，entity2 放真实的另一个
			local connection_data = {
				entity1 = fake_station_for_check,
				entity2 = max_station,
			}
			-- [修改] 尝试使用 4 个参数进行定点插入
			local result = remote.call(
				"cybersyn",
				"write_global",
				connection_data,
				"connected_surfaces",
				surface_pair_key,
				entity_pair_key
			)

			-- [修改] 如果表不存在，退回初始化写法
			if not result then
				remote.call(
					"cybersyn",
					"write_global",
					{ [entity_pair_key] = connection_data },
					"connected_surfaces",
					surface_pair_key
				)
			end
			if Chuansongmen.DEBUG_MODE_ENABLED then
				log_debug("传送门 Cybersyn 兼容: [智能排序伪装] 连接已建立。")
			end
			success = true
		else
			-- [修改] 使用 4 个参数进行定点删除
			remote.call("cybersyn", "write_global", nil, "connected_surfaces", surface_pair_key, entity_pair_key)
			remote.call("cybersyn", "write_global", nil, "se_elevators", station1.unit_number)
			remote.call("cybersyn", "write_global", nil, "se_elevators", station2.unit_number)
			if Chuansongmen.DEBUG_MODE_ENABLED then
				log_debug("传送门 Cybersyn 兼容: 连接已断开并清理 (定点)。")
			end
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
	if not CybersynCompat.is_present then
		return
	end
	if portal_struct and portal_struct.cybersyn_connected then
		local opposite_struct = State.get_opposite_struct(portal_struct)
		if opposite_struct and portal_struct.station.valid and opposite_struct.station.valid then
			CybersynCompat.update_connection(portal_struct, opposite_struct, false, nil)
		end
	end
end

--- 【新增】处理传送门克隆/移动时的 Cybersyn 注册迁移
-- @param old_struct table: 旧数据
-- @param new_struct table: 新数据
-- @param is_landing boolean: 是否正在降落 (从太空变回地面)
function CybersynCompat.on_portal_cloned(old_struct, new_struct, is_landing)
	if not CybersynCompat.is_present then
		return
	end

	-- 只处理原本就已经连接了 Cybersyn 的传送门
	if not (old_struct and new_struct and old_struct.cybersyn_connected) then
		return
	end

	-- 获取配对目标
	local partner = State.get_struct_by_id(new_struct.paired_to_id)
	if not partner then
		return
	end

	-- 1. 无条件注销旧连接
	CybersynCompat.update_connection(old_struct, partner, false, nil)

	-- 2. 根据状态决定操作和通知
	local is_takeoff = false -- 标记是否是起飞

	if is_landing then
		-- 场景：降落。隐身模式。
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug("传送门 Cybersyn 兼容: 飞船降落，物流接口进入隐身模式。")
		end
		new_struct.cybersyn_connected = true -- 保持按钮开启状态
	else
		-- 场景：起飞 或 地面搬家。注册新 ID。
		CybersynCompat.update_connection(new_struct, partner, true, nil)
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug("传送门 Cybersyn 兼容: 接口已迁移到新实体。")
		end

		-- 判断是否是起飞 (新地表是飞船)
		if string.find(new_struct.surface.name, "spaceship") then
			is_takeoff = true
		end
	end

	-- 3. 发送玩家通知 (根据设置)
	-- 只有在 "起飞" 或 "降落" 时才通知，普通搬家不打扰
	if is_landing or is_takeoff then
		for _, player in pairs(game.players) do
			-- 检查玩家是否开启了通知设置
			if settings.get_player_settings(player)["chuansongmen-show-cybersyn-notifications"].value then
				if is_landing then
					player.print({ "messages.chuansongmen-cybersyn-landing", new_struct.name })
				elseif is_takeoff then
					player.print({ "messages.chuansongmen-cybersyn-takeoff", new_struct.name })
				end
			end
		end
	end
end

return CybersynCompat
