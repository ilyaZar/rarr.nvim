local M = {}

local current_test_file
local quoted_r_string

M.actions = {
  {
    key = "test_file",
    command = "RtestFile",
    map = "<C-t>",
    desc = "R package: test current file",
    package = true,
    expr = function(bufnr)
      local path = current_test_file(bufnr)
      if not path then
        vim.notify(
          "Current file is not a testthat test file under tests/testthat/",
          vim.log.levels.WARN
        )
        return nil
      end
      return "testthat::test_file(" .. quoted_r_string(path) .. ")"
    end,
  },
  {
    key = "doc",
    command = "Rdoc",
    map = "<C-S-d>",
    expr = "devtools::document()",
    desc = "R package: document",
    task_name = "R package: document",
    package = true,
  },
  {
    key = "load",
    command = "Rload",
    map = "<C-b>",
    expr = "devtools::load_all()",
    desc = "R package: load",
    task_name = "R package: load",
    package = true,
  },
  {
    key = "test",
    command = "Rtest",
    map = "<C-S-t>",
    expr = "devtools::test()",
    desc = "R package: test",
    task_name = "R package: test",
    package = true,
  },
  {
    key = "build",
    command = "Rbuild",
    map = "<C-S-b>",
    expr = "devtools::build()",
    desc = "R package: build",
    task_name = "R package: build",
    package = true,
  },
  {
    key = "check",
    command = "Rcheck",
    map = "<C-S-e>",
    expr = "devtools::check()",
    desc = "R package: check",
    task_name = "R package: check",
    package = true,
  },
}

local action_map = {}

local function rebuild_action_map()
  action_map = {}
  for _, action in ipairs(M.actions) do
    action_map[action.key] = action
  end
end

rebuild_action_map()

function M.configure(user_actions)
  local by_key = {}
  for i, action in ipairs(M.actions) do
    by_key[action.key] = i
  end

  for _, ua in ipairs(user_actions) do
    local idx = by_key[ua.key]
    if idx then
      M.actions[idx] = ua
    else
      M.actions[#M.actions + 1] = ua
    end
  end

  rebuild_action_map()
end

local function current_path(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  if path == "" then
    return vim.uv.cwd()
  end

  local term_cwd = path:match("^term://(.-)//%d+:")
  if term_cwd then
    return term_cwd
  end

  if vim.fn.isdirectory(path) == 1 then
    return path
  end

  return vim.fs.dirname(path)
end

current_test_file = function(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  if path == "" then
    return nil
  end

  local normalized = vim.fs.normalize(path)
  if normalized:match("/tests/testthat/test%-.+%.R$") then
    return normalized
  end
end

quoted_r_string = function(value)
  return string.format(
    '"%s"',
    value:gsub("\\", "\\\\"):gsub('"', '\\"')
  )
end

local function action_expr(action, bufnr)
  if type(action.expr) == "function" then
    return action.expr(bufnr)
  end
  return action.expr
end

function M.package_root(bufnr)
  local found = vim.fs.find("DESCRIPTION", {
    upward = true,
    path = current_path(bufnr),
    type = "file",
  })[1]

  if found then
    return vim.fs.dirname(found)
  end
end

function M.require_package_root(bufnr)
  local root = M.package_root(bufnr)
  if root then
    return root
  end

  vim.notify(
    "No DESCRIPTION found for current R package",
    vim.log.levels.WARN
  )
end

function M.is_package_context(bufnr)
  return M.package_root(bufnr) ~= nil
end

function M.send(action_key)
  local action = action_map[action_key]
  if not action then
    return
  end

  if action.package and not M.require_package_root(0) then
    return
  end

  local expr = action_expr(action, 0)
  if not expr then
    return
  end

  require("r.send").cmd(expr)
end

function M.register_commands()
  if vim.g.rarr_package_commands_registered then
    return
  end

  for _, action in ipairs(M.actions) do
    if action.command then
      vim.api.nvim_create_user_command(action.command, function()
        M.send(action.key)
      end, { desc = action.desc })
    end
  end

  vim.g.rarr_package_commands_registered = true
end

function M.set_keymaps(bufnr, modes)
  modes = modes or { "n" }
  for _, action in ipairs(M.actions) do
    if action.map then
      vim.keymap.set(modes, action.map, function()
        M.send(action.key)
      end, {
        buffer = bufnr,
        desc = action.desc,
        silent = true,
      })
    end
  end
end

function M.task_definition(action_key, cwd)
  local action = action_map[action_key]
  if not action then
    return nil
  end

  cwd = cwd or M.require_package_root(0)
  if not cwd then
    return nil
  end

  local expr = action_expr(action, 0)
  if not expr or not action.task_name then
    return nil
  end

  return {
    name = action.task_name,
    cmd = { "R", "--quiet", "--no-save", "-e", expr },
    cwd = cwd,
    components = {
      "default",
      "on_complete_notify",
      "display_duration",
    },
  }
end

return M
