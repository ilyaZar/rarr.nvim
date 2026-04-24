local M = {}
local slot = require("rarr.terminal_slot")

-- Intended rarr mode. Focus hooks may need to restore Neovim's
-- terminal state to match it.
M.mode = "normal"
M.resume_insert = false

local DEFAULT_INSERT_COLOR = "#c9826b"
local DEFAULT_NORMAL_COLOR = "#81a1c1"
local DEFAULT_WINBAR_FG = "#1f2335"
local TMP_RARR_COMMENT =
  "# Artefact for starting rarr file when no R-files are present in R/. Can be deleted safely."

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

local function package_root(bufnr)
  return require("rarr.context").package_root(bufnr)
end

local function package_r_path(bufnr)
  local root = package_root(bufnr)
  if not root then
    return nil
  end

  local r_dir = vim.fs.joinpath(root, "R")
  local paths = vim.fn.globpath(r_dir, "**/*.R", false, true)
  if #paths > 0 then
    return paths[1]
  end

  if vim.fn.isdirectory(r_dir) == 0 then
    vim.fn.mkdir(r_dir, "p")
  end

  local tmp_path = vim.fs.joinpath(r_dir, "tmp_rarr.R")
  if vim.fn.filereadable(tmp_path) == 0 then
    vim.fn.writefile({ TMP_RARR_COMMENT }, tmp_path)
  end
  return tmp_path
end

local function package_r_buffer(bufnr)
  local root = package_root(bufnr)
  if not root then
    return nil
  end

  for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(candidate)
      and vim.bo[candidate].buflisted
      and require("rarr.context").is_r_filetype(candidate)
      and package_root(candidate) == root
    then
      return candidate
    end
  end
end

local function edit_buffer(bufnr)
  vim.cmd("buffer " .. bufnr)
end

local function edit_path(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function route_to_package_r_buffer(bufnr)
  local existing = package_r_buffer(bufnr)
  if existing then
    edit_buffer(existing)
    return vim.api.nvim_buf_get_name(existing), true
  end

  local path = package_r_path(bufnr)
  if not path then
    return nil
  end

  edit_path(path)
  return path, false
end

local function sync_r_config_to_slot()
  local ok, r_config = pcall(require, "r.config")
  if not ok then
    return
  end

  local cfg = r_config.get_config()
  local ctx = slot.context()
  if ctx.position == "right" then
    cfg.rconsole_width = ctx.width
  else
    cfg.rconsole_height = ctx.height
  end
end

local function start_when_ready(attempt)
  attempt = attempt or 0
  if (vim.g.R_Nvim_status or 0) >= 3 then
    sync_r_config_to_slot()
    require("r.run").start_R("R")
    return
  end
  if attempt >= 40 then
    vim.notify(
      "R.nvim is still initializing; press Ctrl+/ again from the R buffer",
      vim.log.levels.WARN,
      { title = "rarr.nvim" }
    )
    return
  end

  vim.defer_fn(function()
    start_when_ready(attempt + 1)
  end, 100)
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

function M.is_visible()
  return console_win() ~= nil
end

function M.hide()
  local win = console_win()
  if not win then
    return
  end

  slot.remember_window(win, "r")
  arm_insert_return(vim.api.nvim_win_get_buf(win))
  vim.api.nvim_win_call(win, function()
    vim.cmd("hide")
  end)
  slot.clear_active("r")
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
    M.hide()
    return
  end

  local ok_shell, shell = pcall(require, "rarr.shell")
  if ok_shell and shell.is_visible and shell.is_visible() then
    shell.hide()
  end

  -- If R is running and the buffer exists, reopen it directly.
  -- R.nvim's reopen_win uses vnew which orphans empty buffers.
  local bufnr = console_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local reopen_win = slot.open_buffer(bufnr, "r")
    focus_console(reopen_win)
    set_insert_mode(bufnr, nil)
    slot.set_active("r")
    return
  end

  local context = require("rarr.context")
  if context.is_r_filetype(0) then
    sync_r_config_to_slot()
    require("r.run").start_R("R")
    return
  end

  if context.is_package_context(0) then
    local path, reused = route_to_package_r_buffer(0)
    if not path then
      vim.notify(
        "R console could not find or create a package R bootstrap file",
        vim.log.levels.WARN
      )
      return
    end

    local root = package_root(0)
    local label = root and vim.fs.relpath(root, path) or vim.fs.basename(path)
    vim.notify(
      (reused and "Starting R from open package buffer "
        or "First R start requires an R buffer; opened ") .. label,
      vim.log.levels.INFO,
      { title = "rarr.nvim", timeout = 10000 }
    )
    start_when_ready()
    return
  end

  vim.notify(
    "R console starts only from R buffers or inside an R package",
    vim.log.levels.WARN
  )
  return

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

  local resize = {
    ["<C-M-Left>"] = ok_ss and smart_splits.resize_left
      or function() vim.cmd("vertical resize -2") end,
    ["<C-M-Right>"] = ok_ss and smart_splits.resize_right
      or function() vim.cmd("vertical resize +2") end,
    ["<C-M-Up>"] = ok_ss and smart_splits.resize_up
      or function() vim.cmd("resize -2") end,
    ["<C-M-Down>"] = ok_ss and smart_splits.resize_down
      or function() vim.cmd("resize +2") end,
  }

  for lhs, resize_window in pairs(resize) do
    vim.keymap.set({ "n", "t" }, lhs, resize_window, {
      buffer = bufnr,
      desc = "Resize window from console",
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
  local ok_shell, shell = pcall(require, "rarr.shell")
  if ok_shell and shell.set_keymaps then
    shell.set_keymaps(bufnr)
  end

  local win = console_win()
  win = slot.normalize_window(win, "r") or win
  slot.set_active("r")
  focus_console(win)
  set_insert_mode(bufnr, nil)
end

return M
