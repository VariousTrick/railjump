-- scripts/util.lua (传送门 Mod 工具库 - goto 修复版)
-- 功能：提供一系列健robust、兼容性强的工具函数，用于安全地处理实体、物品栏和流体。

local Util = {}

local DEBUG_ENABLED = false

local function log_util(message)
    if DEBUG_ENABLED then
        log("[传送门 Util] " .. message)
    end
end

function Util.set_debug_mode(is_enabled)
    DEBUG_ENABLED = is_enabled
    log_util("调试模式已 " .. (is_enabled and "开启" or "关闭") .. "。")
end

---------------------------------------------------------------------------
-- 向量与几何 (保持不变)
---------------------------------------------------------------------------
function Util.vectors_add(a, b)
    return { x = a.x + b.x, y = a.y + b.y }
end

function Util.position_in_rect(rect, pos)
    if not (rect and rect.left_top and rect.right_bottom and pos) then
        return false
    end
    return pos.x >= rect.left_top.x
        and pos.x <= rect.right_bottom.x
        and pos.y >= rect.left_top.y
        and pos.y <= rect.right_bottom.y
end

function Util.get_rolling_stock_train_id(rolling_stock)
    if rolling_stock and rolling_stock.valid and rolling_stock.train and rolling_stock.train.valid then
        return rolling_stock.train.id
    end
    return nil
end

---------------------------------------------------------------------------
-- 【SE兼容核心】底层内容转移函数 (借鉴自Space Exploration)
---------------------------------------------------------------------------
function Util.se_move_inventory_items(source_inv, destination_inv)
    if not (source_inv and source_inv.valid and destination_inv and destination_inv.valid) then
        return
    end
    for i = 1, #source_inv do
        local stack = source_inv[i]
        if stack and stack.valid_for_read then
            if not destination_inv[i].transfer_stack(stack) then
                destination_inv.insert(stack)
            end
        end
    end
    if not source_inv.is_empty() then
        local entity = destination_inv.entity_owner
        if entity and entity.valid then
            log_util(
                "!! 警告 (se_move_inventory_items): 目标物品栏已满，部分物品将被丢弃在地上。"
            )
            for i = 1, #source_inv do
                if source_inv[i].valid_for_read then
                    entity.surface.spill_item_stack({
                        position = entity.position,
                        stack = source_inv[i],
                        enable_looted = true,
                        force = entity.force,
                        allow_belts = false,
                    })
                end
            end
        end
    end
    source_inv.clear()
end

function Util.se_transfer_burner(source_entity, destination_entity)
    if source_entity.burner and destination_entity.burner then
        if source_entity.burner.currently_burning then
            destination_entity.burner.currently_burning = source_entity.burner.currently_burning.name
            destination_entity.burner.remaining_burning_fuel = source_entity.burner.remaining_burning_fuel
        end
        if source_entity.burner.inventory then
            Util.se_move_inventory_items(source_entity.burner.inventory, destination_entity.burner.inventory)
            if source_entity.burner.burnt_result_inventory then
                Util.se_move_inventory_items(
                    source_entity.burner.burnt_result_inventory,
                    destination_entity.burner.burnt_result_inventory
                )
            end
        end
    end
end

---------------------------------------------------------------------------
-- 高级内容转移 (整合了SE逻辑的终极兼容版)
---------------------------------------------------------------------------
function Util.transfer_fluids(source_entity, destination_entity)
    log_util("DEBUG (transfer_fluids): 开始转移流体...")
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        log_util("错误 (transfer_fluids): 源或目标实体无效。")
        return
    end
    if not (source_entity.fluids_count and source_entity.fluids_count > 0) then
        log_util("DEBUG (transfer_fluids): 源实体中没有流体，无需转移。")
        return
    end
    log_util(
        "DEBUG (transfer_fluids): 找到 " .. source_entity.fluids_count .. " 个流体容器。正在逐一复制..."
    )
    for i = 1, source_entity.fluids_count do
        local success, err_msg = pcall(function()
            destination_entity.set_fluid(i, source_entity.get_fluid(i))
        end)
        if not success then
            log_util(
                "!! 严重兼容性错误 (transfer_fluids): 在复制第 "
                .. i
                .. " 个流体容器时失败！错误: "
                .. tostring(err_msg)
            )
        end
    end
    log_util("DEBUG (transfer_fluids): 流体转移流程结束。")
end

function Util.transfer_equipment_grid(source_entity, destination_entity)
    log_util("DEBUG (transfer_equipment_grid): 开始转移装备网格...")
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end
    if source_entity.grid and destination_entity.grid then
        for _, item_stack in pairs(source_entity.grid.equipment) do
            if item_stack then
                destination_entity.grid.put({ name = item_stack.name, position = item_stack.position })
            end
        end
    end
    log_util("DEBUG (transfer_equipment_grid): 装备网格转移结束。")
end

function Util.transfer_all_inventories(source_entity, destination_entity, move_items)
    log_util("DEBUG (transfer_all_inventories): 开始转移所有物品栏 (终极兼容模式)...")
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    log_util("DEBUG (transfer_all_inventories): 正在尝试 [主方案] 'get_inventories'...")
    local success, inventories_or_error = pcall(function()
        return source_entity.get_inventories(source_entity)
    end)
    if success and inventories_or_error then
        log_util("DEBUG (transfer_all_inventories): [主方案成功] 'get_inventories' 调用成功。")
        local source_inventories = inventories_or_error
        local dest_inventories = destination_entity.get_inventories(destination_entity)
        if dest_inventories then
            for i, source_inv in pairs(source_inventories) do
                if source_inv and dest_inventories[i] then
                    Util.se_move_inventory_items(source_inv, dest_inventories[i])
                end
            end
            log_util("DEBUG (transfer_all_inventories): 所有物品栏转移结束 (主方案)。")
            return
        end
    else
        log_util(
            "!! 警告 (transfer_all_inventories): [主方案失败] 'get_inventories' 调用失败。错误: "
            .. tostring(inventories_or_error)
            .. " 将启动 [SE后备方案]..."
        )
    end

    log_util("DEBUG (transfer_all_inventories): [SE后备方案] 正在根据实体类型进行转移...")
    local entity_type = source_entity.type
    if entity_type == "cargo-wagon" then
        log_util("DEBUG (transfer_all_inventories): 检测到货运车厢。")
        local source_inv = source_entity.get_inventory(defines.inventory.cargo_wagon)
        local dest_inv = destination_entity.get_inventory(defines.inventory.cargo_wagon)
        Util.se_move_inventory_items(source_inv, dest_inv)
    elseif entity_type == "locomotive" then
        log_util("DEBUG (transfer_all_inventories): 检测到机车。")
        Util.se_transfer_burner(source_entity, destination_entity)
    elseif entity_type == "artillery-wagon" then
        log_util("DEBUG (transfer_all_inventories): 检测到炮兵车厢。")
        local source_inv = source_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
        local dest_inv = destination_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
        Util.se_move_inventory_items(source_inv, dest_inv)
    elseif entity_type == "fluid-wagon" then
        log_util("DEBUG (transfer_all_inventories): 检测到流体车厢，检查是否有物品栏。")
        if defines.inventory.fluid_wagon then
            local source_inv = source_entity.get_inventory(defines.inventory.fluid_wagon)
            if source_inv then
                Util.se_move_inventory_items(
                    source_inv,
                    destination_entity.get_inventory(defines.inventory.fluid_wagon)
                )
            end
        else
            log_util(
                "DEBUG (transfer_all_inventories): defines.inventory.fluid_wagon 不存在，跳过物品栏检查。"
            )
        end
    else
        log_util(
            "警告 (transfer_all_inventories): [SE后备方案] 未知的实体类型 '"
            .. entity_type
            .. "'，无法确定如何转移物品。"
        )
    end
    log_util("DEBUG (transfer_all_inventories): 后备方案执行完毕。")
end

function Util.transfer_inventory_filters(source_entity, destination_entity, inventory_index)
    log_util(
        "DEBUG (transfer_inventory_filters): 开始转移物品栏过滤器 (index: "
        .. tostring(inventory_index)
        .. ")..."
    )
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    local source_inv = source_entity.get_inventory(inventory_index)
    local dest_inv = destination_entity.get_inventory(inventory_index)
    if not (source_inv and dest_inv) then
        return
    end

    if source_inv.is_filtered() then
        log_util(
            "DEBUG (transfer_inventory_filters): 检测到源物品栏已启用过滤，正在逐一复制格子..."
        )
        for i = 1, #dest_inv do
            local filter = source_inv.get_filter(i)
            if filter then
                dest_inv.set_filter(i, filter)
            end
        end
        dest_inv.filter_mode = source_inv.filter_mode
        log_util("DEBUG (transfer_inventory_filters): 过滤器格子和模式复制完毕。")
    end

    log_util("DEBUG (transfer_inventory_filters): 正在安全地检查和转移过滤条...")
    local pcall_success, pcall_result_or_error = pcall(function()
        return destination_entity.supports_inventory_bar()
    end)
    if not pcall_success then
        log_util(
            "!! 严重兼容性错误 (transfer_inventory_filters): 尝试调用 'supports_inventory_bar' 时发生崩溃！错误信息: "
            .. tostring(pcall_result_or_error)
        )
    elseif pcall_result_or_error == true then
        log_util("DEBUG (transfer_inventory_filters): 实体报告支持过滤条，正在尝试转移...")
        local transfer_success, transfer_error = pcall(function()
            local bar = source_entity.get_inventory_bar(inventory_index)
            destination_entity.set_inventory_bar(inventory_index, bar)
        end)
        if not transfer_success then
            log_util(
                "!! 警告 (transfer_inventory_filters): 在转移过滤条时发生错误。错误信息: "
                .. tostring(transfer_error)
            )
        else
            log_util("DEBUG (transfer_inventory_filters): 过滤条转移成功。")
        end
    else
        log_util(
            "DEBUG (transfer_inventory_filters): 实体报告不支持过滤条（或调用失败），安全跳过。"
        )
    end
    log_util("DEBUG (transfer_inventory_filters): 物品栏过滤器转移结束。")
end

---
-- 【重写】尝试从配对的传送门网络中消耗资源 (goto 修复版)
---
function Util.consume_shared_resources(player, entry_portal, opposite_portal, items_to_consume)
    log_util("DEBUG (consume_shared_resources): 开始共享资源消耗检查...")

    -- 【goto 修复】在函数顶部声明所有可能被 goto 跳过的局部变量
    local opposite_inv = nil

    local function check_inventory(inventory, items)
        if not inventory then
            return false
        end
        for _, item_stack in ipairs(items) do
            if inventory.get_item_count(item_stack.name) < item_stack.count then
                return false
            end
        end
        return true
    end

    -- 1. 尝试从入口传送门消耗
    local entry_inv = entry_portal.entity.get_inventory(defines.inventory.assembling_machine_input)
    if check_inventory(entry_inv, items_to_consume) then
        for _, item_stack in ipairs(items_to_consume) do
            entry_inv.remove(item_stack)
        end
        log_util(
            "DEBUG (consume_shared_resources): 在入口传送门 (ID: "
            .. entry_portal.id
            .. ") 成功消耗本地资源。"
        )
        return { success = true, consumed_at = entry_portal }
    end

    -- 2. 尝试从对侧传送门消耗
    if not (opposite_portal and opposite_portal.entity and opposite_portal.entity.valid) then
        goto fail -- 现在这个 goto 不会跳过任何局部变量的定义
    end

    opposite_inv = opposite_portal.entity.get_inventory(defines.inventory.assembling_machine_input)
    if check_inventory(opposite_inv, items_to_consume) then
        for _, item_stack in ipairs(items_to_consume) do
            opposite_inv.remove(item_stack)
        end
        log_util(
            "DEBUG (consume_shared_resources): 在对侧传送门 (ID: "
            .. opposite_portal.id
            .. ") 成功消耗远程资源。"
        )

        local gps_tag = "[gps="
            .. opposite_portal.position.x
            .. ","
            .. opposite_portal.position.y
            .. ","
            .. opposite_portal.surface.name
            .. "]"
        local message = {
            "messages.chuansongmen-info-remote-consumption",
            entry_portal.name,
            gps_tag,
            opposite_portal.name,
        }

        if player and player.valid then
            player.print(message)
        else
            game.print(message)
        end

        return { success = true, consumed_at = opposite_portal }
    end

    -- 3. 如果两边都失败
    ::fail::
    log_util(
        "!! 警告 (consume_shared_resources): 入口 (ID: "
        .. entry_portal.id
        .. ") "
        .. (opposite_portal and ("和对侧 (ID: " .. opposite_portal.id .. ") ") or "")
        .. "均缺少资源。"
    )
    local failed_message = {
        "messages.chuansongmen-error-teleport-failed-resources",
        entry_portal.name,
        (opposite_portal and opposite_portal.name or "???"),
    }
    if player and player.valid then
        player.print(failed_message)
    else
        game.print(failed_message)
    end

    return { success = false, consumed_at = nil }
end

--- 【新增】将一个 SignalID 表转换为可以在 GUI 或车站名称中显示的富文本字符串。
-- 备注：这是实现“图标+名称”格式的核心辅助工具。
-- @param signal_id table: 一个标准的 Factorio SignalID，例如 {type="item", name="iron-plate"}
-- @return string: 对应的富文本字符串，例如 "[item=iron-plate]"。如果输入无效则返回空字符串。
function Util.signal_to_richtext(signal_id)
    -- 安全检查：确保输入是一个包含 type 和 name 的表
    if not (signal_id and signal_id.type and signal_id.name) then
        if DEBUG_LOGGING_ENABLED then -- 使用 control.lua 中定义的全局开关
            log_debug(
                "传送门 Util 警告 (signal_to_richtext): 接收到无效的 signal_id: " .. serpent.line(signal_id)
            )
        end
        return "" -- 返回空字符串以避免后续代码出错
    end
    -- 构建并返回富文本字符串
    return "[" .. signal_id.type .. "=" .. signal_id.name .. "]"
end

-- [新增] 旋转向量 (移植自 SE 0.7.36)
function Util.rotate_vector(orientation, a)
    if orientation == 0 then
        return { x = a.x, y = a.y }
    else
        return {
            x = -a.y * math.sin(orientation * 2 * math.pi) + a.x * math.sin((orientation + 0.25) * 2 * math.pi),
            y = a.y * math.cos(orientation * 2 * math.pi) - a.x * math.cos((orientation + 0.25) * 2 * math.pi),
        }
    end
end

-- [新增] 旋转包围盒 (移植自 SE 0.7.36，用于修复断头 Bug)
function Util.rotate_box(box, pivot)
    if (not box.orientation) or box.orientation == 0 then
        return box
    end

    local negative_pivot = { x = -pivot.x, y = -pivot.y }
    local lt = Util.vectors_add(box.left_top, negative_pivot)
    lt = Util.rotate_vector(box.orientation, lt)
    lt = Util.vectors_add(lt, pivot)

    local rb = Util.vectors_add(box.right_bottom, negative_pivot)
    rb = Util.rotate_vector(box.orientation, rb)
    rb = Util.vectors_add(rb, pivot)

    -- 重新排序角点
    if lt.x > rb.x then
        lt.x, rb.x = rb.x, lt.x
    end
    if lt.y > rb.y then
        lt.y, rb.y = rb.y, lt.y
    end

    return { left_top = lt, right_bottom = rb }
end

return Util
