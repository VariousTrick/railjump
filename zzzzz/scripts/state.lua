-- /scripts/state.lua
-- 【传送门 Mod - 状态管理模块 v1.0】
-- 功能：集中管理 Mod 的全局数据，包括初始化、加载、以及提供对传送门数据的访问接口。
-- 设计原则：将数据层与逻辑层分离，为其他模块提供一个统一、稳定的数据来源。

-- log("传送门 DEBUG (state.lua): 开始加载 state.lua ...") -- DEBUG: 确认文件被加载

local State = {}

-- 这个模块将直接管理 MOD_DATA，所以我们在此定义它
MOD_DATA = {}

-- 本地化的日志记录器，将由 control.lua 注入
local log_debug = function() end

--- 接收来自 control.lua 的调试日志函数
-- @param logger_func function: 从 control.lua 传入的 log_debug 函数
function State.set_logger(logger_func)
    if logger_func then
        log_debug = logger_func
        log_debug("传送门 State 模块: 成功接收到 debug logger。")
    end
end

--- 初始化或加载全局数据表
-- 备注：这是从 control.lua 的 initialize_globals 函数中移动过来的核心部分。
function State.initialize_globals()
    -- 【v42/v46 修复】使用 'storage' 进行持久化存储
    if not storage.chuansongmen_data then
        storage.chuansongmen_data = {
            portals = {}, -- 存储所有传送门数据的表
            next_id = 1   -- 用于分配唯一 ID
        }
        log_debug("传送门 State (initialize_globals): 未找到现有数据，已创建新的 storage.chuansongmen_data。")
    end

    -- 创建一个全局快捷方式，方便在整个脚本中访问我们的数据
    MOD_DATA = storage.chuansongmen_data
    log_debug("传送门 State (initialize_globals): 全局数据 (MOD_DATA) 已初始化并链接到 storage。")
end

--- 根据 ID 获取传送门结构数据
-- 备注：这是从 control.lua 的 Chuansongmen.get_struct_by_id 函数移动过来的。
-- @param target_id number: 要查找的传送门的唯一 ID
-- @return table|nil: 传送门的 struct 数据，如果找不到则返回 nil
function State.get_struct_by_id(target_id)
    if not target_id then return nil end
    -- 直接从 MOD_DATA 中查找
    for _, struct in pairs(MOD_DATA.portals) do
        if struct.id == target_id then
            return struct
        end
    end
    log_debug("传送门 State 警告 (get_struct_by_id): 未找到 ID 为 " .. tostring(target_id) .. " 的传送门结构。")
    return nil
end

--- 根据游戏实体对象获取其对应的传送门结构数据
-- 备注：这是从 control.lua 的 Chuansongmen.get_struct 函数移动过来的。
-- @param entity LuaEntity: 游戏中的传送门实体
-- @return table|nil: 传送门的 struct 数据，如果找不到则返回 nil
function State.get_struct(entity)
    if entity and entity.valid and entity.unit_number then
        -- MOD_DATA.portals 的键就是实体的 unit_number
        return MOD_DATA.portals[entity.unit_number]
    end
    return nil
end

--- 获取一个传送门配对的另一半的结构数据
-- 备注：这是从 control.lua 的 Chuansongmen.get_opposite_struct 函数移动过来的。
-- @param struct table: 当前传送门的 struct 数据
-- @return table|nil: 对侧传送门的 struct 数据，如果无效或未配对则返回 nil
function State.get_opposite_struct(struct)
    if not (struct and struct.paired_to_id) then return nil end

    -- 复用 get_struct_by_id 来查找对侧
    local opposite_struct = State.get_struct_by_id(struct.paired_to_id)

    -- 确保找到的对侧传送门是有效的
    if opposite_struct and opposite_struct.entity and opposite_struct.entity.valid then
        return opposite_struct
    end

    return nil
end

-- 导出模块
return State
