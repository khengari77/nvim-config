local M = { active = vim.env.NVIM_INTERVIEW == "1" }
local resume_supermaven = false
local function guard(fn)
  return function(...)
    if M.active then
      vim.notify("AI action blocked: interview practice is on", vim.log.levels.WARN)
      return ""
    end
    return fn(...)
  end
end
function M.supermaven()
  local api = require("supermaven-nvim.api")
  if not api._practice_guard then
    api.start = guard(api.start)
    api._practice_guard = true
  end
end
function M.opencode()
  local oc = require("opencode")
  if oc._practice_guard then
    return
  end
  for _, name in ipairs({ "ask", "select", "prompt", "operator", "command", "toggle", "start" }) do
    oc[name] = guard(oc[name])
  end
  local provider = require("opencode.provider")
  provider.start = guard(provider.start)
  provider.toggle = guard(provider.toggle)
  local events = require("opencode.events")
  events.subscribe = guard(events.subscribe)
  oc._practice_guard = true
end
function M.set(enabled)
  if enabled == M.active then
    return
  end
  M.active = enabled
  if package.loaded["supermaven-nvim.api"] then
    local api = require("supermaven-nvim.api")
    if enabled then
      resume_supermaven = api.is_running()
      api.stop()
      require("supermaven-nvim.completion_preview"):dispose_inlay()
    elseif resume_supermaven then
      api.start()
    end
  end
  if enabled and package.loaded.opencode then
    pcall(require("opencode").stop)
  end
  if package.loaded.lualine then
    require("lualine").refresh({ place = { "statusline" } })
  end
end
function M.statusline()
  return M.active and "AI OFF" or "AI allowed"
end
function M.command(arg)
  if arg == "" or arg == "toggle" then
    M.set(not M.active)
  elseif arg == "on" then
    M.set(true)
  elseif arg == "off" then
    M.set(false)
  elseif arg ~= "status" then
    return vim.notify("Use on, off, toggle, or status", vim.log.levels.ERROR)
  end
  vim.notify("Interview practice: " .. (M.active and "ON (AI blocked)" or "OFF"))
end
return M
