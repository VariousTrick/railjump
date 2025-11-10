-- =================================================================================================
-- 传送门 Mod - data.lua - v91.0 (功能合并版)
-- 描述: 将 v90.x 的模块化功能 (模式切换、新物品) 重新整合回 v37 的单文件稳定结构中。
-- =================================================================================================

local function create_centered_box(width, height)
local half_width = width / 2
local half_height = height / 2
return {{-half_width, -half_height}, {half_width, half_height}}
end

local blank_sprite = {
    filename = "__zzzzz__/graphics/blank.png",
    priority = "high",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1,
}

-- =================================================================================================
-- 1. 原型定义 (data:extend)
--    整合了旧版的基础原型和新版的资源消耗原型。
-- =================================================================================================
data:extend({

    -- 【请在这里加入这一段】
    {
        type = "recipe-category",
        name = "chuansongmen-internal" -- 类别名称可以自定义
    },

    -- ==================================
    -- 核心传送门物品与实体
    -- ==================================
    {
        type = "item",
        name = "chuansongmen",
        icon = "__zzzzz__/graphics/icons/portal.png",
        icon_size = 64,
        subgroup = "logistic-network",
        order = "z[portal]",
        place_result = "chuansongmen-entity",
        stack_size = 1,
    },
    {
        type = "recipe",
        name = "chuansongmen",
        enabled = true, -- 直接可用
        energy_required = 60, -- 设定一个较长的制作时间，符合其工程量
        ingredients = {
            {type = "item", name = "processing-unit", amount = 200},
            {type = "item", name = "radar", amount = 5},
            {type = "item", name = "accumulator", amount = 10},
            {type = "item", name = "concrete", amount = 500},
            {type = "item", name = "chuansongmen-personal-stabilizer", amount = 2},
            {type = "item", name = "chuansongmen-exotic-matter", amount = 5}
        },
        results = {
            {type = "item", name = "chuansongmen", amount = 1}
        },
    },
    {
        type = "assembling-machine",
        name = "chuansongmen-entity",
        icon = "__zzzzz__/graphics/icons/portal.png",
        icon_size = 64,

        localised_description = {"entity-description.chuansongmen-entity-restriction"},
        flags = {"placeable-neutral", "placeable-player", "player-creation", "hide-alt-info"},
        show_activity = false, -- 【请在这里加入这一行】
        show_recipe_icon = false, -- 【!! 在这里添加这一行 !!】
        minable = {mining_time = 1, result = "chuansongmen"},
        max_health = 10000,
        corpse = "big-remnants",
        dying_explosion = "medium-explosion",
        collision_box = create_centered_box(23.9, 24),
            selection_box = create_centered_box(24, 24),
            build_grid_size = 2,
            resistances = {{type = "fire", percent = 100}, {type = "impact", percent = 100}},
            crafting_categories = {"chuansongmen-internal"},
            -- 【请进行这两处修改】
            fixed_recipe = "chuansongmen-dummy-maintenance",
            crafting_speed = 0.01, -- 初始值，后续会根据模式调整
            energy_source = {type = "electric", usage_priority = "secondary-input", drain = "10kW"},
            energy_usage = "10kW",
            collision_mask = {
                layers = {
                    ["water_tile"] = true,
                    ["item"] = true,
                    ["floor"] = true,
                    ["object"] = true,
                    ["player"] = true,
                },
            },
            graphics_set = {
                animation = {
                    north = {layers = {{filename = "__zzzzz__/graphics/entity/portal/portal-left.png", priority = "high", width = 832, height = 832, scale = 1, shift = {0, 0}}, {filename = "__zzzzz__/graphics/entity/portal/portal-shadow.png", priority = "high", width = 2304, height = 1344, scale = 0.5, shift = {6, 2.5}, draw_as_shadow = true}}},
                    east = {layers = {{filename = "__zzzzz__/graphics/entity/portal/portal-right.png", priority = "high", width = 832, height = 832, scale = 1, shift = {0, 0}}, {filename = "__zzzzz__/graphics/entity/portal/portal-shadow.png", priority = "high", width = 2304, height = 1344, scale = 0.5, shift = {6, 2.5}, draw_as_shadow = true}}},
                    south = {layers = {{filename = "__zzzzz__/graphics/entity/portal/portal-right.png", priority = "high", width = 832, height = 832, scale = 1, shift = {0, 0}}, {filename = "__zzzzz__/graphics/entity/portal/portal-shadow.png", priority = "high", width = 2304, height = 1344, scale = 0.5, shift = {6, 2.5}, draw_as_shadow = true}}},
                    west = {layers = {{filename = "__zzzzz__/graphics/entity/portal/portal-left.png", priority = "high", width = 832, height = 832, scale = 1, shift = {0, 0}}, {filename = "__zzzzz__/graphics/entity/portal/portal-shadow.png", priority = "high", width = 2304, height = 1344, scale = 0.5, shift = {6, 2.5}, draw_as_shadow = true}}},
                },
                    working_visualisations = {} -- 【请在这里加入这一行】
            },
    },

    -- ==================================
    -- 【新内容】模式 1: 有消耗模式的物品与配方
    -- ==================================
    {
        type = "item",
        name = "chuansongmen-exotic-matter",
        icon = "__zzzzz__/graphics/icons/exotic-matter.png",
        icon_size = 64,
        subgroup = "intermediate-product",
        order = "z-a",
        stack_size = 10,
    },
    {
        type = "item",
        name = "chuansongmen-spacetime-shard",
        icon = "__zzzzz__/graphics/icons/spacetime-shard.png",
        icon_size = 64,
        subgroup = "intermediate-product",
        order = "z-b",
        stack_size = 30,
    },
    {
        type = "item",
        name = "chuansongmen-personal-stabilizer",
        icon = "__zzzzz__/graphics/icons/personal-stabilizer.png",
        icon_size = 64,
        subgroup = "intermediate-product",
        order = "z-c",
        stack_size = 5,
    },
    -- ==================================
    -- 【最终版】生产与消耗配方
    -- ==================================

    -- 1. 奇异物质 (终局量产配方)
{
    type = "recipe",
    name = "chuansongmen-exotic-matter-production",
    category = "centrifuging", -- 只能在离心机中制作
    enabled = true, -- 直接可用
    energy_required = 60,
    ingredients = {
        {type="item", name="speed-module", amount=1},
        {type="item", name="efficiency-module", amount=1},
        {type="item", name="productivity-module", amount=1},
        {type="item", name="uranium-235", amount=1}
        -- 【修改】移除了重油
    },
    results = {
        {type="item", name="chuansongmen-exotic-matter", amount=1}
    },
},

-- 2. 奇异物质 (回收配方)
{
    type = "recipe",
    name = "chuansongmen-shard-recycling",
    category = "crafting", -- 【修改】可以在组装机或玩家手中制作
    enabled = true, -- 直接可用
    energy_required = 30,
    ingredients = {
        {type = "item", name = "chuansongmen-spacetime-shard", amount = 10}
        -- 【修改】移除了重油
    },
    results = {
        {type = "item", name = "chuansongmen-exotic-matter", amount = 1}
    },
},

-- 3. 不稳定的时空碎片 (低效启动器配方)
{
    type = "recipe",
    name = "chuansongmen-shard-emergency-production",
    category = "centrifuging", -- 只能在离心机中制作
    enabled = true, -- 直接可用
    energy_required = 10,
    ingredients = {
        {type = "item", name = "speed-module", amount = 1},
        {type = "item", name = "iron-plate", amount = 20}
    },
    results = {
        {type = "item", name = "chuansongmen-spacetime-shard", amount = 5}
    },
},

-- 4. 个人时空稳定器 (精密电子产品配方)
{
    type = "recipe",
    name = "chuansongmen-personal-stabilizer-production",
    category = "crafting", -- 可以在组装机或玩家手中制作
    enabled = true, -- 直接可用
    energy_required = 15,
    ingredients = {
        {type = "item", name = "processing-unit", amount = 10},
        {type = "item", name = "battery", amount = 20},
        {type = "item", name = "steel-plate", amount = 10},
        -- 【修改】增加了碎片作为原料
        {type = "item", name = "chuansongmen-spacetime-shard", amount = 5}
    },
    results = {
        {type = "item", name = "chuansongmen-personal-stabilizer", amount = 1}
    },
},

-- 5. 内部配方 (用于传送门实体，保持不变)
{
    type = "recipe",
    name = "chuansongmen-matter-consumption",
    icon = "__zzzzz__/graphics/icons/portal.png",
    icon_size = 64,
    category = "chuansongmen-internal",
    enabled = true,
    localised_description = {"recipe-description.chuansongmen-matter-consumption"},
    hidden = true, -- 这个配方在任何制作菜单中都不可见
    energy_required = 3600,
    ingredients = {
        {type = "item", name = "chuansongmen-exotic-matter", amount = 1},
        {type = "item", name = "chuansongmen-personal-stabilizer", amount = 1},
        {type = "item", name = "chuansongmen-spacetime-shard", amount = 1}
    },
    results = {
        {type = "item", name = "chuansongmen-spacetime-shard", amount = 3}
    },
},

    -- ==================================
    -- 【新/旧内容】模式 2: 无消耗模式的虚拟配方
    -- ==================================
    {
        type = "recipe",
        name = "chuansongmen-dummy-maintenance",
        -- 【请在这里加入下面这两行】
        icon = "__zzzzz__/graphics/icons/portal.png",
        icon_size = 64,
        category = "chuansongmen-internal", -- 【请添加这一行】
        ---------------------------------
        hidden = true,
        enabled = false,
        ingredients = {},
        results = {},
    },

    -- ==================================
    -- 内部实体原型 (来自旧版 v37 & 新版 v90.9)
-- ==================================
{
    type = "electric-pole",
    name = "chuansongmen-energy-pole",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    flags = {"not-deconstructable", "not-blueprintable"},
    hidden = true,
    selectable_in_game = true,
    collision_mask = {layers = {}},
    collision_box = create_centered_box(0.1, 0.1),
            selection_box = create_centered_box(6, 6),
            supply_area_distance = 12,
            maximum_wire_distance = 32,
            pictures = blank_sprite,
            connection_points = {{
                shadow = {copper = {1, 0.1}, green = {1.2, -0.3}, red = {0.95, -0.2}},
            wire = {copper = {0.1, -2.5}, green = {0.2, -2.8}, red = {-0.25, -2.7}}
            }},
},
{
    type = "electric-energy-interface",
    name = "chuansongmen-energy-interface",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    flags = {"not-deconstructable", "not-blueprintable"},
    hidden = true,
    selectable_in_game = false,
    collision_mask = {layers = {}},
    energy_source = {
        buffer_capacity = "10kW",
        input_flow_limit = "600MW",
        output_flow_limit = "0GW",
        type = "electric",
        usage_priority = "secondary-input"
    },
},
{
    type = "explosion",
    name = "chuansongmen-train-collision-detector-explosion",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    hidden = true,
    flags = {"not-on-map", "placeable-off-grid"},
    animations = blank_sprite,
},
{
    type = "simple-entity",
    name = "chuansongmen-collider",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"},
    hidden = true,
    collision_box = create_centered_box(4, 6),
            selection_box = create_centered_box(4, 6),
            collision_mask = {layers = {["train"] = true}},
            picture = blank_sprite,
            dying_trigger_effect = {type = "create-entity", entity_name = "chuansongmen-train-collision-detector-explosion", trigger_created_entity = true},
            max_health = 1,
            selectable_in_game = false,
},
{
    type = "lamp",
    name = "chuansongmen-lamp",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    hidden = true,
    selectable_in_game = false,
    collision_mask = {layers = {}},
    energy_source = {type = "void"},
    energy_usage_per_tick = "1W",
    picture_off = blank_sprite,
    picture_on = blank_sprite,
    light = {intensity = 1, size = 48, color = {r = 1, g = 0.95, b = 0.9}}
},
{
    type = "simple-entity",
    name = "chuansongmen-blocker-vertical",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    hidden = true,
    selectable_in_game = false,
    flags = {"placeable-neutral", "not-repairable"},
    picture = blank_sprite,
    collision_mask = {layers = {["player"] = true}},
    collision_box = create_centered_box(2, 8),
},
{
    type = "simple-entity",
    name = "chuansongmen-blocker-horizontal",
    icon = "__zzzzz__/graphics/icons/portal.png", icon_size = 64,
    hidden = true,
    selectable_in_game = false,
    flags = {"placeable-neutral", "not-repairable"},
    picture = blank_sprite,
    collision_mask = {layers = {["player"] = true}},
    collision_box = create_centered_box(8, 2),
},

-- 占位符原型
{type = "power-switch", name = "chuansongmen-power-switch"},
{type = "train-stop", name = "chuansongmen-train-stop"},
{type = "rail-signal", name = "chuansongmen-rail-signal"},
{type = "legacy-straight-rail", name = "chuansongmen-legacy-straight-rail"},
{type = "legacy-curved-rail", name = "chuansongmen-legacy-curved-rail"},
})

-- =================================================================================================
-- 2. 读取模组设置 (从 data-final-fixes 移植)
--    在 data 阶段，settings.startup 是只读的，这样读取是安全的。
-- =================================================================================================
local resource_cost_enabled = settings.startup["chuansongmen-enable-resource-cost"] and settings.startup["chuansongmen-enable-resource-cost"].value or true

-- =================================================================================================
-- 3. 根据模式修改原型 (从 data-final-fixes 移植)
--    这部分逻辑现在直接跟随在 data:extend 之后，确保能访问到刚定义的原型。
-- =================================================================================================

local portal_entity = data.raw["assembling-machine"]["chuansongmen-entity"]

if resource_cost_enabled then
    -- ==================================
    -- 有消耗模式 (启用)
    -- ==================================
    log("传送门 Mod: 正在启用 [资源消耗] 模式。")

    portal_entity.fixed_recipe = "chuansongmen-matter-consumption"
    -- 【核心修改】将原料栏从2增加到3，以容纳新的维护材料（碎片）
    portal_entity.ingredient_inventory_size = 3
    portal_entity.result_inventory_size = 1
    portal_entity.crafting_speed = 0.5
    portal_entity.module_specification = {module_slots = 0}

    -- 从旗帜中移除 hide-alt-info，以便玩家能看到燃料和产出
    local flags = {}
    for _, flag in pairs(portal_entity.flags) do
        if flag ~= "hide-alt-info" then
            table.insert(flags, flag)
            end
            end
            portal_entity.flags = flags

            data.raw.recipe["chuansongmen-dummy-maintenance"] = nil
            else
                -- ==================================
                -- 无消耗模式 (禁用)
                -- ==================================
                log("传送门 Mod: 正在启用 [无消耗] 模式。")

                portal_entity.fixed_recipe = "chuansongmen-dummy-maintenance"
                data.raw.recipe["chuansongmen-dummy-maintenance"].enabled = true -- 确保虚拟配方可用
                portal_entity.crafting_speed = 0.01 -- 保持旧版无消耗模式的极低速度

                -- 确保其他消耗模式的属性不存在
                portal_entity.ingredient_inventory_size = nil
                portal_entity.result_inventory_size = nil

                -- 删除所有与资源消耗相关的物品和配方
                data.raw.item["chuansongmen-exotic-matter"] = nil
                data.raw.item["chuansongmen-spacetime-shard"] = nil
                data.raw.item["chuansongmen-personal-stabilizer"] = nil

                data.raw.recipe["chuansongmen-exotic-matter-production"] = nil
                data.raw.recipe["chuansongmen-shard-recycling"] = nil
                data.raw.recipe["chuansongmen-personal-stabilizer-production"] = nil
                data.raw.recipe["chuansongmen-matter-consumption"] = nil
                end

                -- =================================================================================================
                -- 4. 共享的后期处理 (来自旧版 v37，包含完整的图形清理)
                --    这部分代码确保了内部实体的正确配置和隐形。
                -- =================================================================================================

                local function table_merge(destination, source)
                for k, v in pairs(source) do
                    destination[k] = v
                    end
                    return destination
                    end

                    -- 配置电源开关
                    local internal_power_switch = data.raw["power-switch"]["chuansongmen-power-switch"]
                    table_merge(internal_power_switch, table.deepcopy(data.raw["power-switch"]["power-switch"]))
                    internal_power_switch.name = "chuansongmen-power-switch"
                    internal_power_switch.icon = "__zzzzz__/graphics/icons/portal.png"
                    internal_power_switch.icon_size = 64
                    internal_power_switch.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"}
                    internal_power_switch.collision_mask = {layers = {}}
                    internal_power_switch.selectable_in_game = false
                    internal_power_switch.hidden = true
                    internal_power_switch.power_on_animation = blank_sprite
                    internal_power_switch.overlay_start = blank_sprite
                    internal_power_switch.overlay_loop = blank_sprite
                    internal_power_switch.led_on = blank_sprite
                    internal_power_switch.led_off = blank_sprite

                    -- 配置火车站
                    local internal_train_stop = data.raw["train-stop"]["chuansongmen-train-stop"]
                    table_merge(internal_train_stop, table.deepcopy(data.raw["train-stop"]["train-stop"]))
                    -- 在 table_merge(...) 之后添加/修改：
                    internal_train_stop.minable = nil -- 不可挖掘
                    internal_train_stop.placeable_by = nil -- 不可放置 (虽然 hidden=true 通常足够)
                    internal_train_stop.next_upgrade = nil -- 移除升级信息
                    internal_train_stop.fast_replaceable_group = nil -- 移除快速替换组
                    -- 确保 flags 包含 SE 使用的所有标志 (合并，不要覆盖)
                    -- 您当前的 flags 已经很好了: {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"}
                    -- SE 还加了 "not-in-kill-statistics"，可以考虑加入
                    internal_train_stop.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map", "not-in-kill-statistics"}
                    internal_train_stop.name = "chuansongmen-train-stop"
                    internal_train_stop.icon = "__zzzzz__/graphics/icons/portal.png"
                    internal_train_stop.icon_size = 64
                    internal_train_stop.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"}
                    internal_train_stop.hidden = true
                    internal_train_stop.selectable_in_game = false
                    internal_train_stop.animations = nil
                    internal_train_stop.light1 = nil
                    internal_train_stop.light2 = nil
                    internal_train_stop.top_animations = nil
                    internal_train_stop.rail_overlay_animations = nil

                    -- 配置铁路信号
                    local internal_rail_signal = data.raw["rail-signal"]["chuansongmen-rail-signal"]
                    table_merge(internal_rail_signal, table.deepcopy(data.raw["rail-signal"]["rail-signal"]))
                    internal_rail_signal.minable = nil
                    internal_rail_signal.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map", "not-in-kill-statistics"}
                    internal_rail_signal.name = "chuansongmen-rail-signal"
                    internal_rail_signal.icon = "__zzzzz__/graphics/icons/portal.png"
                    internal_rail_signal.icon_size = 64
                    internal_rail_signal.hidden = true
                    internal_rail_signal.selectable_in_game = false
                    internal_rail_signal.animation = nil
                    internal_rail_signal.red_light = nil
                    internal_rail_signal.green_light = nil
                    internal_rail_signal.orange_light = nil
                    internal_rail_signal.rail_piece = nil
                    internal_rail_signal.ground_patch = nil
                    internal_rail_signal.ground_piece = nil
                    internal_rail_signal.ground_light = nil
                    if internal_rail_signal.ground_picture_set then
                        internal_rail_signal.ground_picture_set.north = blank_sprite
                        internal_rail_signal.ground_picture_set.east = blank_sprite
                        internal_rail_signal.ground_picture_set.south = blank_sprite
                        internal_rail_signal.ground_picture_set.west = blank_sprite
                        end

                        -- 为清空轨道图形准备正确的空白结构 (原版)
                        local blank_rail_layers = {metals = blank_sprite, backplates = blank_sprite, ties = blank_sprite, stone_path = blank_sprite}

                        local internal_straight_rail = data.raw["legacy-straight-rail"]["chuansongmen-legacy-straight-rail"]
                        table_merge(internal_straight_rail, table.deepcopy(data.raw["legacy-straight-rail"]["legacy-straight-rail"]))
                        -- 在 table_merge(...) 之后添加/修改：
                        internal_straight_rail.minable = nil
                        internal_straight_rail.placeable_by = nil
                        internal_straight_rail.next_upgrade = nil
                        internal_straight_rail.fast_replaceable_group = nil
                        -- 确保 flags 包含 SE 使用的所有标志
                        internal_straight_rail.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map", "not-in-kill-statistics"}
                        internal_straight_rail.name = "chuansongmen-legacy-straight-rail"
                        internal_straight_rail.icon = "__zzzzz__/graphics/icons/portal.png"
                        internal_straight_rail.icon_size = 64
                        internal_straight_rail.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"}
                        internal_straight_rail.hidden = true
                        internal_straight_rail.selectable_in_game = false

                        -- 清理主要的轨道图形
                        for _, key in pairs({"straight_rail_horizontal", "straight_rail_vertical", "straight_rail_diagonal_left_top", "straight_rail_diagonal_right_top", "straight_rail_diagonal_right_bottom", "straight_rail_diagonal_left_bottom"}) do
                            if internal_straight_rail.pictures[key] then -- 检查以防万一
                                internal_straight_rail.pictures[key] = blank_rail_layers
                                end
                                end


                                -- 2. 修正“弯曲轨道”
                                -- ==================
                                local internal_curved_rail = data.raw["legacy-curved-rail"]["chuansongmen-legacy-curved-rail"]
                                table_merge(internal_curved_rail, table.deepcopy(data.raw["legacy-curved-rail"]["legacy-curved-rail"]))
                                -- 在 table_merge(...) 之后添加/修改：
                                internal_curved_rail.minable = nil
                                internal_curved_rail.placeable_by = nil
                                internal_curved_rail.next_upgrade = nil
                                internal_curved_rail.fast_replaceable_group = nil
                                -- 确保 flags 包含 SE 使用的所有标志
                                internal_curved_rail.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map", "not-in-kill-statistics"}
                                internal_curved_rail.name = "chuansongmen-legacy-curved-rail"
                                internal_curved_rail.icon = "__zzzzz__/graphics/icons/portal.png"
                                internal_curved_rail.icon_size = 64
                                internal_curved_rail.flags = {"hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map"}
                                internal_curved_rail.hidden = true
                                internal_curved_rail.selectable_in_game = false

                                -- 清理主要的轨道图形
                                for _, key in pairs({"curved_rail_vertical_left_top", "curved_rail_vertical_right_top", "curved_rail_vertical_right_bottom", "curved_rail_vertical_left_bottom", "curved_rail_horizontal_left_top", "curoved_rail_horizontal_right_top", "curved_rail_horizontal_right_bottom", "curved_rail_horizontal_left_bottom"}) do
                                    if internal_curved_rail.pictures[key] then -- 检查以防万一
                                        internal_curved_rail.pictures[key] = blank_rail_layers
                                        end
                                        end

                                        -- !! 【重要修复】为弯曲轨道重复防御性逻辑 !!
                                        -- 【v63 修正】模仿 SE internalise 函数清空 rail_endings 的方式
                                        -- (注意：我们复用了上面为直轨创建的 blank_rail_endings_simple，SE 也是这样做的)
                                        internal_curved_rail.pictures.rail_endings = blank_rail_endings_simple

                                        -- ==================================================================
                                        -- !! 修复结束 !!
                                        -- ==================================================================

