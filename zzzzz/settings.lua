-- =================================================================================================
-- 传送门 Mod (独立版) - settings.lua
-- 功能：定义模组的设置选项
-- 诊断性修复：强制使用旧的 data:extend 语法，以绕过罕见的 data = {} 赋值错误
-- =================================================================================================

-- 确保 data 表存在，以兼容旧的 extend 语法
if not data then
  data = {}
end

-- 使用旧的 data:extend 语法来添加设置
data:extend({
  {
    type = "bool-setting",
    name = "chuansongmen-enable-resource-cost", -- 新设置的内部名称
    setting_type = "startup",                 -- 这是一个全局启动设置，修改后需要重启游戏
    default_value = true,                     -- 默认开启资源消耗
    order = "a",                              -- 在设置菜单中排在最前面
    -- 备注：当这个设置为 true 时，我们将启用“有消耗模式”
    localised_name = { "mod-setting-name.chuansongmen-enable-resource-cost" },
    localised_description = { "mod-setting-description.chuansongmen-enable-resource-cost" },
  },
  {
    type = "bool-setting",
    name = "chuansongmen_show_preview", -- 这是在 control.lua 中使用的内部名称
    setting_type = "runtime-per-user", -- 这是一个每个玩家可以独立设置的选项
    default_value = false,            -- 默认不勾选
    order = "z-a",                    -- 在设置菜单中的排序
    localised_name = { "mod-setting-name.chuansongmen_show_preview" },
    localised_description = { "mod-setting-description.chuansongmen_show_preview" },
  },
  -- =======================================================
  -- 【电网维持 - 新增设置】
  -- =======================================================
  {
    type = "int-setting",
    name = "chuansongmen-power-grid-duration",
    setting_type = "runtime-global", -- 全局运行时设置，立即生效
    default_value = 1,             -- 默认值是1分钟
    minimum_value = 1,             -- 最小1分钟
    maximum_value = 5,             -- 最大5分钟
    order = "b[power]-a[duration]", -- 排序
    localised_name = { "mod-setting-name.chuansongmen-power-grid-duration" },
    localised_description = { "mod-setting-description.chuansongmen-power-grid-duration" },
  },
  {
    type = "bool-setting",
    name = "chuansongmen-show-power-warnings",
    setting_type = "runtime-per-user", -- 玩家个人运行时设置，立即生效
    default_value = true,            -- 默认开启警告
    order = "b[power]-b[warnings]",  -- 排序
    localised_name = { "mod-setting-name.chuansongmen-show-power-warnings" },
    localised_description = { "mod-setting-description.chuansongmen-show-power-warnings" },
  },
  -- =======================================================
  -- 【Cybersyn 兼容 - 新增设置】
  -- =======================================================
  {
    type = "bool-setting",
    name = "chuansongmen-show-cybersyn-notifications",
    setting_type = "runtime-per-user", -- 玩家个人设置
    default_value = true,            -- 默认开启
    order = "z-b",                   -- 排在后面
    localised_name = { "mod-setting-name.chuansongmen-show-cybersyn-notifications" },
    localised_description = { "mod-setting-description.chuansongmen-show-cybersyn-notifications" },
  },
  -- [新增] 调试日志开关
  {
    type = "bool-setting",
    name = "chuansongmen-debug-mode", -- 内部名称
    setting_type = "runtime-global", -- 全局设置
    default_value = false,          -- 默认关闭
    order = "z",                    -- 排在最后
    localised_name = { "mod-setting-name.chuansongmen-debug-mode" },
  },
})
