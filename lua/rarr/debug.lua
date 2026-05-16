local M = {}

local DEFAULT_KEYMAPS = {
  debug = "<leader>dd",
  undebug = "<leader>du",
  debugonce = "<leader>do",
  traceback = "<leader>dt",
  recover = "<leader>dr",
  clear_error = "<leader>dR",
  center = "<leader>dc",
}

local config = {
  enabled = true,
  keymaps = vim.deepcopy(DEFAULT_KEYMAPS),
}

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

function M.setup(user_config)
  if user_config == false then
    config.enabled = false
    return
  end

  user_config = user_config or {}
  config.enabled = user_config.enabled ~= false
  if user_config.keymaps == false then
    config.keymaps = {}
  else
    config.keymaps = vim.tbl_extend(
      "force",
      vim.deepcopy(DEFAULT_KEYMAPS),
      user_config.keymaps or {}
    )
  end
end

--- Set R debug keymaps on the given buffer.
--- @param bufnr integer
function M.set_keymaps(bufnr)
  if not config.enabled then
    return
  end

  local maps = {
    { "n", config.keymaps.debug, action_keymap("debug"), "R debug: debug(func)" },
    { "v", config.keymaps.debug, action_keymap("debug", "v"), "R debug: debug(func)" },
    { "n", config.keymaps.undebug, action_keymap("undebug"), "R debug: undebug(func)" },
    { "v", config.keymaps.undebug, action_keymap("undebug", "v"), "R debug: undebug(func)" },
    { "n", config.keymaps.debugonce, action_keymap("debugonce"), "R debug: debugonce(func)" },
    { "v", config.keymaps.debugonce, action_keymap("debugonce", "v"), "R debug: debugonce(func)" },
    { "n", config.keymaps.traceback, send("traceback()"), "R debug: traceback" },
    { "n", config.keymaps.recover, send("options(error = recover)"), "R debug: error -> recover" },
    { "n", config.keymaps.clear_error, send("options(error = NULL)"), "R debug: error -> NULL" },
    { "n", config.keymaps.center, toggle_debug_center, "R debug: toggle center" },
  }

  for _, m in ipairs(maps) do
    if m[2] then
      vim.keymap.set(m[1], m[2], m[3], {
        buffer = bufnr,
        desc = m[4],
        silent = true,
      })
    end
  end
end

return M
