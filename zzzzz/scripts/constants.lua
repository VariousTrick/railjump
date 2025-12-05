-- /scripts/constants.lua
-- 【传送门 Mod - 常量模块 v1.0】
-- 功能：集中管理 Mod 所需的所有静态数据、名称和配置值。
-- 设计原则：将配置与逻辑分离，便于后期调整和维护。

-- log("传送门 DEBUG (constants.lua): 开始加载 constants.lua ...") -- DEBUG: 确认文件被加载

local Constants = {}

---------------------------------------------------------------------------
-- 核心实体与物品名称
---------------------------------------------------------------------------
-- 备注：这些是从 control.lua 的 "核心常量定义" 部分移动过来的。
Constants.name_entity = "chuansongmen-entity" -- 主实体名称
Constants.name_tug = "chuansongmen-tug"       -- 拖车实体名称

-- 【!! 火车检测关键修复 !!】修正脚本监听的爆炸物名称
Constants.name_train_collision_detector = "chuansongmen-train-collision-detector-explosion"

---------------------------------------------------------------------------
-- 行为参数
---------------------------------------------------------------------------
-- 备注：这些是从 control.lua 的 "核心常量定义" 部分移动过来的。
Constants.teleport_next_tick_frequency = 4                                                -- 火车传送检查的频率 (tick)
Constants.player_teleport_distance = 15                                                   -- 玩家传送的距离 (已废弃，现使用精确坐标)
Constants.stock_types = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } -- 脚本识别的火车车辆类型
Constants.deconstruction_check_radius = 12                                                -- 检查传送门附近是否有火车的半径

---------------------------------------------------------------------------
-- 几何与位置定义
---------------------------------------------------------------------------
-- 备注：这些是从 control.lua 的 "核心常量定义" 部分移动过来的。

-- 内部碰撞器的相对位置 (根据朝向)
Constants.space_elevator_collider_position = {
    [defines.direction.east] = { x = -3, y = -3.5 },
    [defines.direction.west] = { x = 3, y = -3.5 },
}

-- 火车检测区域 (相对传送门中心)
Constants.watch_rect_by_dir = {
    [defines.direction.east] = { left_top = { x = -11, y = -11 }, right_bottom = { x = 0, y = 0 } },
    [defines.direction.west] = { left_top = { x = 0, y = -11 }, right_bottom = { x = 11, y = 0 } },
}

-- 火车传送出口位置 (相对传送门中心)
Constants.output_pos = {
    [defines.direction.east] = { x = 5, y = -2 },
    [defines.direction.west] = { x = -5, y = -2 },
}

-- 拖车生成位置 (相对传送门中心, 已废弃)
Constants.output_tug_pos = {
    [defines.direction.east] = { x = 1, y = -6 },
    [defines.direction.west] = { x = -1, y = -6 },
}

-- 火车传送出口清理区域 (相对传送门中心)
Constants.output_area = {
    [defines.direction.east] = { left_top = { x = 0, y = -12 }, right_bottom = { x = 12, y = 12 } },
    [defines.direction.west] = { left_top = { x = -12, y = -12 }, right_bottom = { x = 0, y = 12 } },
}

---------------------------------------------------------------------------
-- 内部实体布局
---------------------------------------------------------------------------
-- 备注：这是从 control.lua 中 `Chuansongmen.internals` 的完整定义移动过来的。
-- 【v63 修正】传送门内部实体的相对位置和方向定义 (恢复内部轨道)
Constants.internals = {
    shared = {
        ["chuansongmen-blocker-vertical"] = {
            { position = { x = -10.85, y = -4.85 }, direction = defines.direction.north },
            { position = { x = -10.85, y = 7.85 },  direction = defines.direction.north },
            { position = { x = -10.85, y = -2 },    direction = defines.direction.north },
            { position = { x = 10.85, y = 7.85 },   direction = defines.direction.north },
            { position = { x = 10.85, y = -4.85 },  direction = defines.direction.north },
            { position = { x = 10.85, y = -2 },     direction = defines.direction.north },
        },
        ["chuansongmen-blocker-horizontal"] = {
            { position = { x = 0, y = 10.85 },     direction = defines.direction.east },
            { position = { x = -7.85, y = 10.85 }, direction = defines.direction.east },
            { position = { x = 7.85, y = 10.85 },  direction = defines.direction.east },
            { position = { x = 0, y = -7.85 },     direction = defines.direction.east },
            { position = { x = -7.85, y = -7.85 }, direction = defines.direction.east },
            { position = { x = 7.85, y = -7.85 },  direction = defines.direction.east },
        },
        -- 【v63 修正】恢复内部连接轨道
        ["chuansongmen-legacy-straight-rail"] = {
            { position = { x = -5.5, y = -1.5 }, direction = defines.direction.southeast },
            { position = { x = 4.5, y = -1.5 },  direction = defines.direction.southwest },
        },
        ["chuansongmen-legacy-curved-rail"] = {
            { position = { x = 2, y = -4 },  direction = defines.direction.south },
            { position = { x = -2, y = -4 }, direction = defines.direction.southwest },
            { position = { x = 8, y = 2 },   direction = defines.direction.northwest },
            { position = { x = -8, y = 2 },  direction = defines.direction.east },
        },
        ["chuansongmen-lamp"] = {
            { position = { x = 0, y = 0 }, direction = defines.direction.north },
        },
        ["chuansongmen-energy-interface"] = {
            { position = { x = 0, y = 0 }, direction = defines.direction.north },
        },
        ["chuansongmen-energy-pole"] = {
            { position = { x = 0, y = 0 }, direction = defines.direction.north },
        },
        ["chuansongmen-power-switch"] = {
            { position = { x = 0, y = 0 }, direction = defines.direction.north, primary_only = true },
        },
    },
    [defines.direction.east] = {
        ["chuansongmen-legacy-straight-rail"] = {
            { position = { x = -1, y = -9 }, direction = defines.direction.north },
        },
        ["chuansongmen-train-stop"] = {
            { position = { x = 1, y = -9 }, direction = defines.direction.north },
        },
        -- 【v63 修正】添加 east 方向信号灯
        ["chuansongmen-rail-signal"] = {
            { position = { x = -11.5, y = 4.5 }, direction = defines.direction.west },
            { position = { x = 11.5, y = 4.5 },  direction = defines.direction.west },
        },
    },
    [defines.direction.west] = {
        ["chuansongmen-legacy-straight-rail"] = {
            { position = { x = 1, y = -9 }, direction = defines.direction.north },
        },
        ["chuansongmen-train-stop"] = {
            { position = { x = 3, y = -9 }, direction = defines.direction.north },
        },
        ["chuansongmen-rail-signal"] = {
            { position = { x = -11.5, y = 1.5 }, direction = defines.direction.east },
            { position = { x = 11.5, y = 1.5 },  direction = defines.direction.east },
        },
    },
}

-- 在文件末尾，将包含所有常量的大表导出，以便其他文件可以引用
return Constants
