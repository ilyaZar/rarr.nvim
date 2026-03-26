local M = {}

-- Authoritative console mode. Every transition updates this before
-- sending keys to rarr. Read it to know the current mode without
-- guessing. Initialized to "normal" in setup_console().
M.mode = "normal"

local DEFAULT_INSERT_COLOR = "#c9826b"
local DEFAULT_NORMAL_COLOR = "#81a1c1"
local DEFAULT_WINBAR_FG = "#1f2335"

local function lualine_bg(name)
  local ok, highlight = pcall(require, "lualine.highlight")
  if not ok then
    return nil
  end

  local ok_hl, hl = pcall(highlight.get_lualine_hl, name)
  if ok_hl and type(hl) == "table" and type(hl.bg) == "string" then
    return hl.bg
  end
end

local function palette()
  return {
    fg = DEFAULT_WINBAR_FG,
    insert = lualine_bg("lualine_a_terminal") or DEFAULT_INSERT_COLOR,
    normal = lualine_bg("lualine_a_normal") or DEFAULT_NORMAL_COLOR,
  }
end

local function console_bufnr()
  local ok, builtin = pcall(require, "r.term.builtin")
  if not ok then
    return nil
  end
  return builtin.get_buf_nr()
end

local function console_job_id(bufnr)
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok then
    return job_id
  end
end

local function console_win()
  local bufnr = console_bufnr()
  if not bufnr then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
end

local function send_console_key(bufnr, key)
  local job_id = console_job_id(bufnr)
  if job_id then
    vim.fn.chansend(job_id, key)
  end
end

function M.set_console_winbar(mode)
  local win = console_win()
  if not win then
    return
  end

  local terminal = require("rarr.terminal")
  local colors = palette()
  local active_mode = mode or M.mode
  local bg = active_mode == "insert" and colors.insert or colors.normal

  vim.api.nvim_set_hl(0, "RConsoleWinBar", {
    fg = colors.fg,
    bg = bg,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "RConsoleWinBarNC", {
    fg = colors.fg,
    bg = bg,
    bold = true,
  })

  vim.api.nvim_set_option_value(
    "winbar",
    "%#RConsoleWinBar#  " .. terminal.terminal_label() .. "  ",
    { scope = "local", win = win }
  )
  vim.api.nvim_set_option_value(
    "winhighlight",
    "WinBar:RConsoleWinBar,WinBarNC:RConsoleWinBarNC",
    { scope = "local", win = win }
  )
end

local function set_console_insert(bufnr, key)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.mode = "insert"

  -- Re-enter terminal mode if Neovim is in normal mode (after
  -- startup, <C-\><C-n>, or toggle reopen).
  if vim.api.nvim_get_current_buf() == bufnr
    and vim.api.nvim_get_mode().mode ~= "t"
  then
    vim.cmd("startinsert")
  end

  if key then
    send_console_key(bufnr, key)
  end

  M.set_console_winbar("insert")
end

local function set_console_normal(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.mode = "normal"

  send_console_key(bufnr, "\027")

  -- Exit terminal mode so Neovim normal-mode keys (window
  -- navigation, i/a/I/A bridge) work on the console buffer.
  if vim.api.nvim_get_current_buf() == bufnr
    and vim.api.nvim_get_mode().mode == "t"
  then
    vim.cmd("stopinsert")
  end

  M.set_console_winbar("normal")
end

--- Transition the console to the given mode. Skips if already
--- in the requested mode (no redundant key sends).
--- @param bufnr integer
--- @param mode "insert"|"normal"
--- @param key? string  initiating key for insert (i/a/I/A)
local function set_mode(bufnr, mode, key)
  if mode == M.mode then
    return
  end

  if mode == "normal" then
    set_console_normal(bufnr)
    return
  end

  if mode == "insert" then
    set_console_insert(bufnr, key)
  end
end

function M.r_app_command()
  local colors = palette()
  return table.concat({
    "env",
    "RARR_PROMPT_INSERT_COLOR='" .. colors.insert .. "'",
    "RARR_PROMPT_NORMAL_COLOR='" .. colors.normal .. "'",
    "rarr",
  }, " ")
end

function M.toggle_console()
  local win = console_win()
  if win then
    vim.api.nvim_win_call(win, function()
      vim.cmd("hide")
    end)
    return
  end

  -- If R is running and the buffer exists, reopen it directly.
  -- R.nvim's reopen_win uses vnew which orphans empty buffers.
  local bufnr = console_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local cfg = require("r.config").get_config()
    local vertical = cfg.rconsole_width > 0 and "vertical " or ""
    vim.cmd("belowright " .. vertical .. "sbuffer " .. bufnr)
    -- Restore the mode that was active before hide. Reedline's
    -- mode is unchanged (process kept running), but Neovim always
    -- reopens the terminal in normal mode. Re-apply M.mode to
    -- sync Neovim's terminal state and winbar with reedline.
    if M.mode == "insert" then
      set_console_insert(bufnr, nil)
    else
      set_console_normal(bufnr)
    end
    return
  end

  require("r.run").start_R("R")
end

function M.set_toggle_keymaps(bufnr)
  if not require("rarr.package").is_package_context(bufnr) then
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

local function set_mode_bridge(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.keymap.set("t", "<Esc>", function()
    -- Always exit terminal mode, even if rarr is already in
    -- normal mode (handles external terminal-mode entry that
    -- bypassed set_mode). Esc is idempotent in vi.
    set_console_normal(bufnr)
  end, {
    buffer = bufnr,
    desc = "Switch rarr and Neovim to normal mode",
    silent = true,
  })

  for _, key in ipairs({ "i", "a", "I", "A" }) do
    vim.keymap.set("n", key, function()
      set_mode(bufnr, "insert", key)
    end, {
      buffer = bufnr,
      desc = "Switch rarr and Neovim to insert mode",
      silent = true,
    })
  end

  -- Window navigation from terminal mode. Transitions to normal
  -- (syncs M.mode + sends Esc to reedline) before navigating,
  -- so the i/a/I/A bridge works correctly on return.
  local ok_ss, smart_splits = pcall(require, "smart-splits")
  local nav = {
    ["<C-h>"] = ok_ss and smart_splits.move_cursor_left
      or function() vim.cmd("wincmd h") end,
    ["<C-j>"] = ok_ss and smart_splits.move_cursor_down
      or function() vim.cmd("wincmd j") end,
    ["<C-k>"] = ok_ss and smart_splits.move_cursor_up
      or function() vim.cmd("wincmd k") end,
    ["<C-l>"] = ok_ss and smart_splits.move_cursor_right
      or function() vim.cmd("wincmd l") end,
  }

  for lhs, move in pairs(nav) do
    vim.keymap.set("t", lhs, function()
      set_console_normal(bufnr)
      move()
    end, {
      buffer = bufnr,
      desc = "Navigate window from console",
      silent = true,
    })
  end
end

function M.setup_console()
  local bufnr = console_bufnr()
  if not bufnr then
    return
  end

  set_mode_bridge(bufnr)
  M.set_toggle_keymaps(bufnr)
  -- Force normal mode at startup regardless of M.mode's current
  -- value. Reedline starts in insert mode by default, so we must
  -- always send Esc to align both sides.
  set_console_normal(bufnr)
end

return M
