local M = {}

local config = {
  maps = {},
  adapter = nil,
  cwd = nil,
}

local handle = nil
local group = nil

local function call(fn, ...)
  if type(fn) == "function" then
    return fn(...)
  end
end

local function shell_cwd()
  if type(config.cwd) == "function" then
    return config.cwd()
  end
  if type(config.cwd) == "string" then
    return config.cwd
  end
  return vim.uv.cwd()
end

local function terminal_job_id(bufnr)
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok then
    return job_id
  end
end

local function builtin_show(ctx)
  local slot = require("rarr.terminal_slot")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].filetype = "rarr_shell"

  local win = slot.open_buffer(bufnr)
  if not win then
    return nil
  end

  vim.fn.jobstart(ctx.shell, {
    cwd = ctx.cwd,
    term = true,
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
      end)
    end,
  })
  M.setup_builtin_buffer(bufnr)
  vim.cmd("startinsert")

  return { bufnr = bufnr, win = win }
end

local builtin_adapter = {
  show = builtin_show,
  hide = function(h)
    if h and h.win and vim.api.nvim_win_is_valid(h.win) then
      vim.api.nvim_win_call(h.win, function()
        vim.cmd("hide")
      end)
    end
  end,
  is_visible = function(h)
    return h and h.win and vim.api.nvim_win_is_valid(h.win) or false
  end,
  win = function(h)
    return h and h.win
  end,
  buf = function(h)
    return h and h.bufnr
  end,
  resize = function(h)
    if h and h.win then
      require("rarr.terminal_slot").resize_window(h.win)
    end
  end,
}

local function adapter()
  return config.adapter or builtin_adapter
end

local function shell_win()
  local a = adapter()
  return call(a.win, handle)
end

function M.is_visible()
  local a = adapter()
  if type(a.is_visible) == "function" then
    return a.is_visible(handle)
  end

  local win = shell_win()
  return win and vim.api.nvim_win_is_valid(win) or false
end

function M.hide()
  if not M.is_visible() then
    return
  end

  local slot = require("rarr.terminal_slot")
  local win = shell_win()
  slot.remember_window(win)

  local a = adapter()
  call(a.hide, handle)
  slot.clear_active("shell")
end

function M.toggle()
  local slot = require("rarr.terminal_slot")

  if M.is_visible() then
    M.hide()
    return
  end

  local ok_console, console = pcall(require, "rarr.console")
  if ok_console and console.is_visible and console.is_visible() then
    console.hide()
  end

  local ctx = slot.context({ cwd = shell_cwd() })
  local a = adapter()

  if type(a.toggle) == "function" and not a.show then
    a.toggle(ctx)
    slot.set_active("shell")
    return
  end

  if handle and type(a.is_visible) == "function" and not a.is_visible(handle) then
    call(a.resize, handle, ctx)
    if type(a.show) == "function" then
      handle = a.show(ctx, handle)
    end
  else
    handle = call(a.show, ctx, handle)
  end

  local win = shell_win()
  if win then
    slot.resize_window(win)
  end
  slot.set_active("shell")
end

function M.set_keymaps(bufnr)
  if not config.maps or vim.tbl_isempty(config.maps) then
    return
  end

  for _, mode in ipairs({ "n", "t" }) do
    for _, lhs in ipairs(config.maps) do
      vim.keymap.set(mode, lhs, M.toggle, {
        buffer = bufnr,
        desc = "Toggle shell terminal",
        silent = true,
      })
    end
  end
end

function M.setup(shell_config)
  shell_config = shell_config or {}
  config = vim.tbl_deep_extend("force", {
    maps = {},
    adapter = nil,
    cwd = nil,
  }, shell_config)
  config.maps = config.maps or {}
  handle = nil

  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
  group = vim.api.nvim_create_augroup("RarrShell", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "TermOpen" }, {
    group = group,
    callback = function(event)
      M.set_keymaps(event.buf)
    end,
  })
end

function M.setup_builtin_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.keymap.set("t", "<C-d>", function()
    local job_id = terminal_job_id(bufnr)
    if job_id then
      vim.fn.chansend(job_id, "\004")
    end
  end, {
    buffer = bufnr,
    desc = "Send EOF to shell terminal",
    silent = true,
  })
end

return M
