local M = {}

local function toggle_debug_center()
  local config = require("r.config").get_config()
  config.debug_center = not config.debug_center
  vim.notify(
    "R debug_center: " .. (config.debug_center and "on" or "off"),
    vim.log.levels.INFO
  )
end

local function action_keymap(action_name, mode)
  return function()
    require("r.run").action(action_name, mode)
  end
end

local function send(expr)
  return function()
    require("r.send").cmd(expr)
  end
end

--- Set R debug keymaps on the given buffer.
--- @param bufnr integer
function M.set_keymaps(bufnr)
  local maps = {
    { "n", "<leader>dd", action_keymap("debug"), "R debug: debug(func)" },
    { "v", "<leader>dd", action_keymap("debug", "v"), "R debug: debug(func)" },
    { "n", "<leader>du", action_keymap("undebug"), "R debug: undebug(func)" },
    { "v", "<leader>du", action_keymap("undebug", "v"), "R debug: undebug(func)" },
    { "n", "<leader>do", action_keymap("debugonce"), "R debug: debugonce(func)" },
    { "v", "<leader>do", action_keymap("debugonce", "v"), "R debug: debugonce(func)" },
    { "n", "<leader>dt", send("traceback()"), "R debug: traceback" },
    { "n", "<leader>dr", send("options(error = recover)"), "R debug: error -> recover" },
    { "n", "<leader>dR", send("options(error = NULL)"), "R debug: error -> NULL" },
    { "n", "<leader>dc", toggle_debug_center, "R debug: toggle center" },
  }

  for _, m in ipairs(maps) do
    vim.keymap.set(m[1], m[2], m[3], {
      buffer = bufnr,
      desc = m[4],
      silent = true,
    })
  end
end

return M
