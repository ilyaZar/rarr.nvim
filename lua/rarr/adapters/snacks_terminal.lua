local M = {}

local function value(v, ...)
  if type(v) == "function" then
    return v(...)
  end
  return v
end

function M.setup(opts)
  opts = opts or {}
  local terminal = nil

  return {
    show = function(ctx, existing)
      local Snacks = _G.Snacks or require("snacks")
      terminal = existing or terminal
      local win_opts = vim.tbl_deep_extend("force", {
        position = ctx.position,
        height = ctx.height,
        width = ctx.width,
        stack = false,
      }, opts.win or {})

      local terminal_opts = vim.tbl_deep_extend("force", opts.terminal or {}, {
        cwd = value(opts.cwd, ctx) or ctx.cwd,
        shell = opts.shell or ctx.shell,
        win = win_opts,
      })

      if terminal and terminal.buf_valid and terminal:buf_valid() then
        terminal.opts = vim.tbl_deep_extend("force", terminal.opts or {}, win_opts)
        terminal:show()
        terminal:focus()
        return terminal
      end

      terminal = Snacks.terminal(opts.cmd, terminal_opts)
      return terminal
    end,
    hide = function(handle)
      if handle and handle.hide then
        handle:hide()
      end
    end,
    is_visible = function(handle)
      return handle and handle.valid and handle:valid() or false
    end,
    win = function(handle)
      if handle and handle.win_valid and handle:win_valid() then
        return handle.win
      end
    end,
    resize = function(handle, ctx)
      if not (handle and handle.win_valid and handle:win_valid()) then
        return
      end
      handle.opts.height = ctx.height
      handle.opts.width = ctx.width
      handle:update()
    end,
  }
end

return M
