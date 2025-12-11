-- RailJump Debug Configuration
-- 在scripts中使用此配置

local debug_config = {
  enabled = true,
  log_level = "debug", -- debug, info, warn, error
  modules = {
    constants = true,
    portal_manager = true,
    schedule_handler = true,
    gui = true,
    teleport_handler = true,
    cybersyn_compat = true
  }
}

-- 调试日志函数
function debug_log(module, level, message)
  if not debug_config.enabled then return end
  if not debug_config.modules[module] then return end
  
  local timestamp = game and game.tick or os.date("%H:%M:%S")
  local log_msg = string.format("[%s] %s [%s]: %s", timestamp, level:upper(), module, message)
  
  if level == "error" then
    game.print(log_msg)  -- 显示在游戏中
  end
  
  log(log_msg)  -- 写入日志文件
end

return debug_config
