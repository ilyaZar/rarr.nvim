local M = {}

local defaults = {
  height = 15,
  width = 80,
}

local saved_height = nil
local saved_width = nil
local active = nil

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.configure(opts)
  opts = opts or {}
  defaults.height = opts.rconsole_height or defaults.height
  defaults.width = opts.rconsole_width or defaults.width
end

function M.position()
  return defaults.width > 0 and "right" or "bottom"
end

function M.context(extra)
  extra = extra or {}
  return vim.tbl_extend("force", {
    position = M.position(),
    height = saved_height or defaults.height,
    width = saved_width or defaults.width,
    shell = vim.o.shell,
  }, extra)
end

function M.remember_window(win)
  if not valid_win(win) then
    return
  end
  saved_height = vim.api.nvim_win_get_height(win)
  saved_width = vim.api.nvim_win_get_width(win)
end

function M.resize_window(win)
  if not valid_win(win) then
    return
  end

  local ctx = M.context()
  if ctx.position == "right" then
    if ctx.width and ctx.width > 0 then
      vim.api.nvim_win_set_width(win, ctx.width)
    end
  elseif ctx.height and ctx.height > 0 then
    vim.api.nvim_win_set_height(win, ctx.height)
  end
end

function M.open_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ctx = M.context()
  local vertical = ctx.position == "right" and "vertical " or ""
  vim.cmd("belowright " .. vertical .. "sbuffer " .. bufnr)
  local win = vim.api.nvim_get_current_win()
  M.resize_window(win)
  return win
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
