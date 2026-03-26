local M = {}
local current_test_file
local quoted_r_string

M.actions = {
  {
    key = "test_file",
    command = "RtestFile",
    map = "<C-t>",
    desc = "R package: test current file",
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
  },
  {
    key = "load",
    command = "Rload",
    map = "<C-b>",
    expr = "devtools::load_all()",
    desc = "R package: load",
    task_name = "R package: load",
  },
  {
    key = "test",
    command = "Rtest",
    map = "<C-S-t>",
    expr = "devtools::test()",
    desc = "R package: test",
    task_name = "R package: test",
  },
  {
    key = "build",
    command = "Rbuild",
    map = "<C-S-b>",
    expr = "devtools::build()",
    desc = "R package: build",
    task_name = "R package: build",
  },
  {
    key = "check",
    command = "Rcheck",
    map = "<C-S-e>",
    expr = "devtools::check()",
    desc = "R package: check",
    task_name = "R package: check",
  },
}

local action_map = {}
for _, action in ipairs(M.actions) do
  action_map[action.key] = action
end

local function read_theme_color(name, fallback)
  local theme_file = vim.fs.normalize(
    "~/.config/omarchy/current/theme/colors.toml"
  )
  local ok, lines = pcall(vim.fn.readfile, theme_file)
  if not ok then
    return fallback
  end
  local pattern = "^" .. name .. "%s*=%s*\"(#[0-9A-Fa-f]+)\""
  for _, line in ipairs(lines) do
    local color = line:match(pattern)
    if color then
      return color
    end
  end
  return fallback
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
  return nil
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

-- R console window helpers ----------------------------------------

local function visible_r_window()
  local ok, builtin = pcall(require, "r.term.builtin")
  if not ok then
    return nil
  end
  local rbuf = builtin.get_buf_nr()
  if not rbuf then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == rbuf then
      return win
    end
  end
end

function M.set_console_winbar()
  local win = visible_r_window()
  if not win then
    return
  end

  local terminal = require("rarr.terminal")
  local tmux_blue = read_theme_color("color4", "#81a1c1")
  local inactive_tmux_blue = read_theme_color("color12", tmux_blue)
  local label = terminal.terminal_label()

  vim.api.nvim_set_hl(0, "RConsoleWinBar", {
    fg = "#1f2335",
    bg = tmux_blue,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "RConsoleWinBarNC", {
    fg = "#1f2335",
    bg = inactive_tmux_blue,
    bold = true,
  })

  vim.api.nvim_set_option_value(
    "winbar",
    "%#RConsoleWinBar#  " .. label .. "  %#RConsoleWinBarNC#",
    { scope = "local", win = win }
  )
  vim.api.nvim_set_option_value(
    "winhighlight",
    "WinBar:RConsoleWinBar,WinBarNC:RConsoleWinBarNC",
    { scope = "local", win = win }
  )
end

-- Console toggle --------------------------------------------------

function M.toggle_console()
  if vim.api.nvim_get_mode().mode == "t" then
    vim.cmd("stopinsert")
  end
  local status = vim.g.R_Nvim_status or 0
  if status == 7 then
    local win = visible_r_window()
    if win then
      vim.api.nvim_win_call(win, function()
        vim.cmd("hide")
      end)
      return
    end
  end
  require("r.run").start_R("R")
end

-- Send action to R ------------------------------------------------

function M.send(action_key)
  local action = action_map[action_key]
  if not action then
    return
  end
  if not M.require_package_root(0) then
    return
  end
  local expr = action_expr(action, 0)
  if not expr then
    return
  end
  require("r.send").cmd(expr)
end

-- User commands ---------------------------------------------------

function M.register_commands()
  if vim.g.rarr_package_commands_registered then
    return
  end
  for _, action in ipairs(M.actions) do
    vim.api.nvim_create_user_command(action.command, function()
      M.send(action.key)
    end, { desc = action.desc })
  end
  vim.g.rarr_package_commands_registered = true
end

-- Keymaps ---------------------------------------------------------

function M.set_keymaps(bufnr)
  for _, action in ipairs(M.actions) do
    vim.keymap.set("n", action.map, function()
      M.send(action.key)
    end, {
      buffer = bufnr,
      desc = action.desc,
      silent = true,
    })
  end
end

function M.set_toggle_keymaps(bufnr)
  if not M.is_package_context(bufnr) then
    return
  end
  for _, mode in ipairs({ "n", "t" }) do
    vim.keymap.set(mode, "<C-/>", M.toggle_console, {
      buffer = bufnr,
      desc = "R package: toggle R console",
      silent = true,
    })
    vim.keymap.set(mode, "<C-_>", M.toggle_console, {
      buffer = bufnr,
      desc = "R package: toggle R console",
      silent = true,
    })
  end
end

function M.set_console_navigation_keymaps()
  local ok, builtin = pcall(require, "r.term.builtin")
  if not ok then
    return
  end
  local bufnr = builtin.get_buf_nr()
  if not bufnr then
    return
  end

  local ss_ok, smart_splits = pcall(require, "smart-splits")
  if ss_ok then
    local moves = {
      ["<C-h>"] = smart_splits.move_cursor_left,
      ["<C-j>"] = smart_splits.move_cursor_down,
      ["<C-k>"] = smart_splits.move_cursor_up,
      ["<C-l>"] = smart_splits.move_cursor_right,
      ["<C-\\>"] = smart_splits.move_cursor_previous,
    }

    for lhs, rhs in pairs(moves) do
      vim.keymap.set("t", lhs, function()
        vim.cmd("stopinsert")
        rhs()
      end, {
        buffer = bufnr,
        desc = "Move between windows and tmux panes",
        silent = true,
      })
      vim.keymap.set("n", lhs, rhs, {
        buffer = bufnr,
        desc = "Move between windows and tmux panes",
        silent = true,
      })
    end
  end

  M.set_console_winbar()
  M.set_toggle_keymaps(bufnr)
end

-- Autocmd for toggle keymaps on BufEnter/TermOpen -----------------

function M.register_package_buffer_autocmd()
  if vim.g.rarr_package_toggle_autocmd_registered then
    return
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "TermOpen" }, {
    group = vim.api.nvim_create_augroup(
      "rarr-package-toggle",
      { clear = true }
    ),
    callback = function(event)
      M.set_toggle_keymaps(event.buf)
    end,
  })
  vim.g.rarr_package_toggle_autocmd_registered = true
end

-- Overseer task definition ----------------------------------------

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
