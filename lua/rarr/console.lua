local M = {}

-- Intended rarr mode. Focus hooks may need to restore Neovim's
-- terminal state to match it.
M.mode = "normal"
M.resume_insert = false

local saved_height = nil
local saved_width = nil

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

local function focus_console(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

local function send_console_key(bufnr, key)
  local job_id = console_job_id(bufnr)
  if job_id then
    pcall(vim.fn.chansend, job_id, key)
  end
end

local function stop_terminal_mode(bufnr)
  if vim.api.nvim_get_current_buf() == bufnr
    and vim.api.nvim_get_mode().mode == "t"
  then
    vim.cmd("stopinsert")
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

local function set_insert_mode(bufnr, key)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.mode = "insert"
  M.resume_insert = false

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

local function arm_insert_return(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local was_normal = M.mode ~= "insert"
  M.mode = "insert"
  M.resume_insert = true

  if was_normal then
    send_console_key(bufnr, "i")
  end

  M.set_console_winbar("insert")
end

local function set_console_normal(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.mode = "normal"
  M.resume_insert = false

  send_console_key(bufnr, "\027")
  stop_terminal_mode(bufnr)

  M.set_console_winbar("normal")
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
    saved_height = vim.api.nvim_win_get_height(win)
    saved_width = vim.api.nvim_win_get_width(win)
    arm_insert_return(vim.api.nvim_win_get_buf(win))
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

    local reopen_win = console_win()
    if vertical ~= "" then
      local w = saved_width or cfg.rconsole_width
      if w > 0 then
        vim.api.nvim_win_set_width(reopen_win, w)
      end
    else
      local h = saved_height or cfg.rconsole_height
      if h > 0 then
        vim.api.nvim_win_set_height(reopen_win, h)
      end
    end

    focus_console(reopen_win)
    set_insert_mode(bufnr, nil)
    return
  end

  require("r.run").start_R("R")
end

function M.set_toggle_keymaps(bufnr)
  for _, mode in ipairs({ "n", "t" }) do
    vim.keymap.set(mode, "<C-/>", M.toggle_console, {
      buffer = bufnr,
      desc = "Toggle R console",
      silent = true,
    })
    vim.keymap.set(mode, "<C-_>", M.toggle_console, {
      buffer = bufnr,
      desc = "Toggle R console",
      silent = true,
    })
  end
end

local function set_mode_bridge(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local group = vim.api.nvim_create_augroup("RarrConsole", { clear = true })

  vim.keymap.set("t", "<Esc>", function()
    set_console_normal(bufnr)
  end, {
    buffer = bufnr,
    desc = "Switch rarr and Neovim to normal mode",
    silent = true,
  })

  for _, key in ipairs({ "i", "a", "I", "A" }) do
    vim.keymap.set("n", key, function()
      if M.mode ~= "insert" then
        set_insert_mode(bufnr, key)
      end
    end, {
      buffer = bufnr,
      desc = "Switch rarr and Neovim to insert mode",
      silent = true,
    })
  end

  vim.keymap.set("n", "<C-d>", function()
    send_console_key(bufnr, "i\004")
  end, {
    buffer = bufnr,
    desc = "Send EOF to R console",
    silent = true,
  })

  -- R operator shortcuts. Neovim's terminal doesn't pass Ctrl +
  -- punctuation keys through to crossterm, so we send the text
  -- directly via chansend (reedline is in vi insert per bridge).
  local operators = {
    ["<C-;>"] = " <- ",
    ["<C-S-;>"] = " |> ",
    ["<C-'>"] = " %||% ",
    ["<C-S-'>"] = " %in% ",
  }

  for lhs, text in pairs(operators) do
    vim.keymap.set("t", lhs, function()
      send_console_key(bufnr, text)
    end, {
      buffer = bufnr,
      desc = "Insert R operator",
      silent = true,
    })
  end

  -- Window navigation leaves the console armed for insert on
  -- return, whether we leave from terminal insert or console
  -- normal mode.
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
    local function navigate_away()
      arm_insert_return(bufnr)
      stop_terminal_mode(bufnr)
      move()
    end

    vim.keymap.set({ "n", "t" }, lhs, navigate_away, {
      buffer = bufnr,
      desc = "Navigate window from console",
      silent = true,
    })
  end

  -- Autocmd firing order for each user action:
  --
  -- <Esc> (bridge):    set_console_normal runs directly;
  --                    TermLeave fires but M.mode=="normal" -> no-op
  -- <C-h/j/k/l> (nav): arm_insert_return + stop_terminal_mode;
  --                    TermLeave fires but resume_insert -> no-op
  -- Ctrl+/ (hide):    arm_insert_return runs; window closes
  -- <C-\><C-n>:       TermLeave fires, still on buffer ->
  --                    set_console_normal
  -- Mouse away (from terminal mode):
  --                    TermLeave fires, not on buffer ->
  --                    arm_insert_return
  -- Mouse away (from normal mode):
  --                    WinLeave fires -> arm_insert_return
  -- Return to console: BufEnter/WinEnter fires ->
  --                    if resume_insert, startinsert

  vim.api.nvim_create_autocmd("TermLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      if M.resume_insert or M.mode == "normal" then
        return
      end

      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == bufnr then
          set_console_normal(bufnr)
          return
        end

        arm_insert_return(bufnr)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      if M.resume_insert or M.mode ~= "normal" then
        return
      end

      arm_insert_return(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if not M.resume_insert then
        return
      end

      M.resume_insert = false

      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == bufnr then
          vim.cmd("startinsert")
        end
      end)
    end,
  })
end

function M.setup_console()
  local bufnr = console_bufnr()
  if not bufnr then
    return
  end

  set_mode_bridge(bufnr)
  require("rarr.package").set_keymaps(bufnr, { "t" })
  M.set_toggle_keymaps(bufnr)
  focus_console(console_win())
  set_insert_mode(bufnr, nil)
end

return M
