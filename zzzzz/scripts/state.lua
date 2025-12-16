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
			-- 【新增】为新游戏直接创建好时间桶
			portal_buckets = {},
		}
		-- 初始化 60 个空桶
		for i = 0, 59 do
			storage.chuansongmen_data.portal_buckets[i] = {}
		end
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug("传送门 State (init): 创建了新的 storage 数据表，包含 portal_buckets。")
		end
	end

	-- 2. 数据迁移/补全：如果 id_map 缺失 (旧存档升级)，补上它
	if not storage.chuansongmen_data.id_map then
		storage.chuansongmen_data.id_map = {}
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug("传送门 State (migration): 检测到旧存档，已补全 id_map。")
		end
	end

	-- 【新增】数据迁移：如果 portal_buckets 缺失 (从旧版本升级)，补上它
	if storage.chuansongmen_data.portals and not storage.chuansongmen_data.portal_buckets then
		if Chuansongmen.DEBUG_MODE_ENABLED then
			log_debug("传送门 State (migration): 检测到旧存档，正在创建 portal_buckets...")
		end
		storage.chuansongmen_data.portal_buckets = {}
		for i = 0, 59 do
			storage.chuansongmen_data.portal_buckets[i] = {}
		end
		-- 具体的填充逻辑将在 control.lua 的 on_configuration_changed 中执行
	end

	-- 确保 MOD_DATA 指向最新的 storage
	MOD_DATA = storage.chuansongmen_data
end

--- 根据 ID 获取传送门结构数据 (修正版：直接访问 storage)
function State.get_struct_by_id(target_id)
	if not target_id then
		return nil
	end

	-- 直接从 storage 读取，避免全局 MOD_DATA 引用问题
	local data = storage.chuansongmen_data
	if not data then
		return nil
	end

	-- 1. 缓存读取
	if data.id_map and data.id_map[target_id] then
		local unit_number = data.id_map[target_id]
		local struct = data.portals and data.portals[unit_number]
		if struct then
			return struct
		else
			-- 清理无效缓存
			data.id_map[target_id] = nil
		end
	end

	-- 2. 兜底查找并建立缓存
	if data.portals then
		for unit_number, struct in pairs(data.portals) do
			if struct.id == target_id then
				if not data.id_map then
					data.id_map = {}
				end
				data.id_map[target_id] = unit_number
				return struct
			end
		end
	end
	return nil
end

--- 根据实体获取数据 (修正版：直接访问 storage)
function State.get_struct(entity)
	if entity and entity.valid and entity.unit_number then
		if storage.chuansongmen_data and storage.chuansongmen_data.portals then
			return storage.chuansongmen_data.portals[entity.unit_number]
		end
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
