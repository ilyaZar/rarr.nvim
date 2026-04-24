local M = {}

local defaults = {
  height = 15,
  width = 80,
  rconsole_width = 80,
}

local config = {
  sync = {
    height = true,
    width = true,
  },
  bottom = {
    full_width = false,
  },
  width_source = "last",
}

local saved_height = nil
local saved_width = nil
local active = nil

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.configure(opts, slot_config)
  opts = opts or {}
  defaults.height = opts.rconsole_height or defaults.height
  if type(opts.rconsole_width) == "number" then
    defaults.rconsole_width = opts.rconsole_width
    if opts.rconsole_width > 0 then
      defaults.width = opts.rconsole_width
    end
  end

  config = vim.tbl_deep_extend(
    "force",
    config,
    opts.terminal_slot or {},
    slot_config or {}
  )
end

function M.position()
  return defaults.rconsole_width > 0 and "right" or "bottom"
end

function M.context(extra)
  extra = extra or {}
  return vim.tbl_extend("force", {
    position = M.position(),
    height = saved_height or defaults.height,
    width = saved_width or defaults.width or vim.o.columns,
    shell = vim.o.shell,
  }, extra)
end

local function should_remember_width(kind)
  if config.sync.width == false then
    return false
  end
  if config.width_source == "editor" then
    return false
  end
  if config.width_source == "shell" then
    return kind == "shell"
  end
  if config.width_source == "r" then
    return kind == "r"
  end
  return true
end

function M.remember_window(win, kind)
  if not valid_win(win) then
    return
  end

  if config.sync.height ~= false then
    saved_height = vim.api.nvim_win_get_height(win)
  end
  if should_remember_width(kind) then
    saved_width = vim.api.nvim_win_get_width(win)
  end
end

local function move_to_full_width_bottom(win)
  if not valid_win(win) then
    return
  end

  local tabpage = vim.api.nvim_win_get_tabpage(win)
  if tabpage ~= vim.api.nvim_get_current_tabpage() then
    return
  end

  vim.api.nvim_set_current_win(win)
  vim.cmd("wincmd J")
end

function M.resize_window(win)
  if not valid_win(win) then
    return
  end

  local ctx = M.context()
  if ctx.position == "right" then
    if config.sync.width ~= false and ctx.width and ctx.width > 0 then
      vim.api.nvim_win_set_width(win, ctx.width)
    end
  elseif config.sync.height ~= false and ctx.height and ctx.height > 0 then
    vim.api.nvim_win_set_height(win, ctx.height)
  end
end

function M.normalize_window(win, kind)
  if not valid_win(win) then
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  if M.position() == "bottom" and config.bottom.full_width then
    move_to_full_width_bottom(win)
    win = vim.api.nvim_get_current_win()
  end

  M.resize_window(win)
  M.remember_window(win, kind)
  if valid_win(previous_win) and previous_win ~= win then
    vim.api.nvim_set_current_win(previous_win)
  end
  return win
end

function M.open_buffer(bufnr, kind)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ctx = M.context()
  local vertical = ctx.position == "right" and "vertical " or ""
  local split = ctx.position == "bottom" and config.bottom.full_width
      and "botright "
    or "belowright "
  vim.cmd(split .. vertical .. "sbuffer " .. bufnr)
  local win = vim.api.nvim_get_current_win()
  return M.normalize_window(win, kind)
end

function M.set_active(kind)
  active = kind
end

function M.active()
  return active
end

function M.clear_active(kind)
  if not kind or active == kind then
    active = nil
  end
end

return M
