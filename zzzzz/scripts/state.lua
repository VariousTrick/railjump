-- /scripts/state.lua
-- 【传送门 Mod - 状态管理模块 v1.2 Fix】
-- 功能：集中管理 Mod 的全局数据，修复 on_load 修改 storage 的错误。

local State = {}

-- 这个模块将直接管理 MOD_DATA
MOD_DATA = {}

-- 本地化的日志记录器
local log_debug = function() end

function State.set_logger(logger_func)
    if logger_func then
        log_debug = logger_func
    end
end

--- [只读] 初始化或加载全局数据引用
-- 这个函数可以在 on_load 中安全调用，因为它只读取，不写入。
function State.initialize_globals()
    -- 仅仅是将 MOD_DATA 指向 storage，不做任何创建或修改
    if storage.chuansongmen_data then
        MOD_DATA = storage.chuansongmen_data
        -- log_debug("传送门 State (on_load): MOD_DATA 已链接。")
    else
        -- 如果 storage 里没数据，这里什么都不做，留给 ensure_storage 处理
    end
end

--- [写入] 确保数据结构存在
-- 这个函数只能在 on_init 或 on_configuration_changed 中调用
function State.ensure_storage()
    -- 1. 如果完全没有数据 (新游戏)，创建它
    if not storage.chuansongmen_data then
        storage.chuansongmen_data = {
            portals = {},
            id_map = {},
            next_id = 1,
        }
        log_debug("传送门 State (init): 创建了新的 storage 数据表。")
    end

    -- 2. 数据迁移/补全：如果 id_map 缺失 (旧存档升级)，补上它
    if not storage.chuansongmen_data.id_map then
        storage.chuansongmen_data.id_map = {}
        log_debug("传送门 State (migration): 检测到旧存档，已补全 id_map。")
    end

    -- 确保 MOD_DATA 指向最新的 storage
    MOD_DATA = storage.chuansongmen_data
end

--- 根据 ID 获取传送门结构数据 (带缓存)
function State.get_struct_by_id(target_id)
    if not target_id then
        return nil
    end

    -- 1. 缓存读取
    if MOD_DATA.id_map and MOD_DATA.id_map[target_id] then
        local unit_number = MOD_DATA.id_map[target_id]
        local struct = MOD_DATA.portals[unit_number]
        if struct then
            return struct
        else
            MOD_DATA.id_map[target_id] = nil
        end
    end

    -- 2. 兜底查找并建立缓存
    if MOD_DATA.portals then
        for unit_number, struct in pairs(MOD_DATA.portals) do
            if struct.id == target_id then
                if not MOD_DATA.id_map then
                    MOD_DATA.id_map = {}
                end
                MOD_DATA.id_map[target_id] = unit_number
                return struct
            end
        end
    end
    return nil
end

--- 根据实体获取数据
function State.get_struct(entity)
    if entity and entity.valid and entity.unit_number and MOD_DATA.portals then
        return MOD_DATA.portals[entity.unit_number]
    end
    return nil
end

--- 获取对侧数据
function State.get_opposite_struct(struct)
    if not (struct and struct.paired_to_id) then
        return nil
    end
    local opposite_struct = State.get_struct_by_id(struct.paired_to_id)
    if opposite_struct and opposite_struct.entity and opposite_struct.entity.valid then
        return opposite_struct
    end
    return nil
end

return State
