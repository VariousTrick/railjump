-- scripts/cybersyn_scheduler.lua
-- 版本：v8 (核心修复 - 禁止提前修改列车状态，解决不取货问题)

local CybersynScheduler = {}

-- 调试开关
local DEBUG_MODE = false
local function log_debug(msg)
    if DEBUG_MODE then
        game.print("[传送门调度] " .. msg)
        log("[传送门调度] " .. msg)
    end
end

-- 如果启用了 SE，本模块失效
if script.active_mods["space-exploration"] then return CybersynScheduler end

-- 延迟队列
local pending_trains = {}

-- 辅助函数
local function get_portal_data()
    return storage.chuansongmen_data and storage.chuansongmen_data.portals
end

local function get_distance(pos1, pos2)
    local dx = pos1.x - pos2.x; local dy = pos1.y - pos2.y
    return dx * dx + dy * dy
end

-- 寻路算法
local function find_portal_station(source_surface_index, target_surface_index, origin_position)
    local portals = get_portal_data()
    if not portals then return nil end
    local best_portal = nil; local min_dist = math.huge

    for _, portal in pairs(portals) do
        -- [修复] 增加 and portal.cybersyn_connected 判断
        if portal.surface.index == source_surface_index and
            portal.station and
            portal.station.valid and
            portal.paired_to_id and
            portal.cybersyn_connected then -- <=== 加上这一行
            local partner = nil
            for _, p in pairs(portals) do
                if p.id == portal.paired_to_id then
                    partner = p; break
                end
            end
            if partner and partner.surface.index == target_surface_index then
                local dist = get_distance(portal.position, origin_position)
                if dist < min_dist then
                    min_dist = dist; best_portal = portal
                end
            end
        end
    end
    if best_portal then return best_portal.station.backer_name end
    return nil
end

-- 安全的插入函数 (1:1 复刻 Cybersyn 逻辑)
local function insert_cybersyn_stop_sequence(new_records, original_records, target_station_data, station_type_name,
                                             train_surface_index)
    if not (target_station_data and target_station_data.entity_stop and target_station_data.entity_stop.valid) then
        log_debug("❌ 错误: 无法获取 " .. station_type_name .. " 的实体数据。")
        return
    end

    local stop_entity = target_station_data.entity_stop
    local rail = stop_entity.connected_rail
    local backer_name = stop_entity.backer_name
    local target_surface_index = stop_entity.surface.index

    -- 步骤 1: 尝试插入 Rail 导航记录 (仅同地表)
    if rail and target_surface_index == train_surface_index then
        log_debug("✅ [同地表] 为 " .. station_type_name .. " (" .. backer_name .. ") 插入 Rail 导航记录。")
        table.insert(new_records, {
            rail = rail,
            rail_direction = stop_entity.connected_rail_direction,
            temporary = true,
            wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
        })
    elseif rail then
        log_debug("🛡️ [异地表保护] 跳过 " .. station_type_name .. " 的 Rail 插入。")
    end

    -- 步骤 2: 插入 Station 操作记录
    local found = false
    for _, rec in pairs(original_records) do
        if rec.station == backer_name then
            log_debug("✅ [原有逻辑] 复制 " .. station_type_name .. " (" .. backer_name .. ") 的业务记录。")
            table.insert(new_records, rec)
            found = true
            break
        end
    end

    if not found then
        log_debug("❌ 错误: 未找到名为 " .. backer_name .. " 的原始记录。")
    end
end

-- 处理函数
local function process_train(train)
    if not (train and train.valid and train.schedule and train.schedule.records) then return end

    for _, record in pairs(train.schedule.records) do
        if record.station and string.find(record.station, "chuansongmen") then return end
    end

    local status, c_train = pcall(remote.call, "cybersyn", "read_global", "trains", train.id)
    if not (status and c_train and c_train.manifest) then return end

    local p_st = remote.call("cybersyn", "read_global", "stations", c_train.p_station_id)
    local r_st = remote.call("cybersyn", "read_global", "stations", c_train.r_station_id)
    local dep = remote.call("cybersyn", "read_global", "depots", c_train.depot_id)

    if not (p_st and r_st and dep) then return end

    local s_D = dep.entity_stop.surface.index
    local s_P = p_st.entity_stop.surface.index
    local s_R = r_st.entity_stop.surface.index

    if s_D == s_P and s_P == s_R then return end

    local current_train_surface = train.front_stock.surface.index

    log_debug(">>> ⚡ 开始拦截并重写时刻表 (v8 核心修复版) ⚡ <<<")

    local new_records = {}
    local original_records = train.schedule.records
    local current_pos = train.front_stock.position
    local path_found = false

    -- 1. D -> P
    if s_D ~= s_P then
        local portal = find_portal_station(s_D, s_P, current_pos)
        if portal then
            table.insert(new_records,
                { station = portal, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
            path_found = true
        end
    end

    -- 2. 插入 P (供应站)
    insert_cybersyn_stop_sequence(new_records, original_records, p_st, "供应站(P)", current_train_surface)

    -- 3. P -> R
    if s_P ~= s_R then
        local portal = find_portal_station(s_P, s_R, p_st.entity_stop.position)
        if portal then
            table.insert(new_records,
                { station = portal, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
            path_found = true
        end
    end

    -- 4. 插入 R (收货站)
    insert_cybersyn_stop_sequence(new_records, original_records, r_st, "收货站(R)", current_train_surface)

    -- 5. R -> D
    if s_R ~= s_D then
        local portal = find_portal_station(s_R, s_D, r_st.entity_stop.position)
        if portal then
            table.insert(new_records,
                { station = portal, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
            path_found = true
        end
    end

    -- 6. D (车库)
    if original_records[#original_records] then
        table.insert(new_records, original_records[#original_records])
    end

    if #new_records > 0 then
        local s_manifest = c_train.manifest
        -- 【关键修复】绝对不要在这里手动修改 status！
        -- 让 Cybersyn 自己在列车到站时从 1 (TO_P) 改为 2 (P)
        -- local s_status = c_train.status  <-- 删除了这个变量的修改逻辑

        local schedule = train.schedule
        schedule.records = new_records
        schedule.current = 1
        train.schedule = schedule
        train.manual_mode = false

        -- 只写回 manifest 和 ID 引用，绝对不要写回 status
        remote.call("cybersyn", "write_global", s_manifest, "trains", train.id, "manifest")
        -- remote.call("cybersyn", "write_global", s_status, "trains", train.id, "status") <-- 这一行被删除了，禁止覆盖状态！

        if c_train.p_station_id then
            remote.call("cybersyn", "write_global", c_train.p_station_id, "trains", train.id,
                "p_station_id")
        end
        if c_train.r_station_id then
            remote.call("cybersyn", "write_global", c_train.r_station_id, "trains", train.id,
                "r_station_id")
        end
        if c_train.depot_id then remote.call("cybersyn", "write_global", c_train.depot_id, "trains", train.id, "depot_id") end

        log_debug("成功! 时刻表已修正，列车状态保持原始值，等待出发。")

        -- [新增] 消除视觉警报和内部记录
        if remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"] then
            -- 清除 Cybersyn 内部的警报记录
            remote.call("cybersyn", "write_global", nil, "active_alerts", train.id)
        end

        -- 清除玩家屏幕上的红色报警图标
        local entity_to_clear = train.front_stock or train.back_stock
        if entity_to_clear and entity_to_clear.valid then
            for _, player in pairs(game.connected_players) do
                player.remove_alert({ entity = entity_to_clear })
            end
        end
    end
end

function CybersynScheduler.on_tick()
    if not next(pending_trains) then return end
    for id, train in pairs(pending_trains) do
        if train and train.valid then process_train(train) end
        pending_trains[id] = nil
    end
end

script.on_event(defines.events.on_train_schedule_changed, function(event)
    if event.train and event.train.valid and not event.player_index then
        if event.train.schedule and #event.train.schedule.records >= 2 then
            pending_trains[event.train.id] = event.train
        end
    end
end)

return CybersynScheduler
