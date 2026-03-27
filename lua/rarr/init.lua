-- rarr.nvim -- R.nvim companion plugin for the rarr console
--
-- Usage with lazy.nvim:
--
--   {
--     "R-nvim/R.nvim",
--     dependencies = { "path/to/rarr.nvim" },
--     opts = function(_, opts)
--       require("rarr").setup(opts, {
--         actions = {
--           { key = "search", map = "<C-x>",
--             expr = "search()", desc = "R: search" },
--         },
--       })
--     end,
--   }

local M = {}

--- Wire rarr into R.nvim opts.
--- Call this inside the R.nvim opts function.
--- @param opts table   R.nvim options table (mutated in place)
--- @param config table|nil  rarr-specific config (optional)
function M.setup(opts, config)
  config = config or {}
  local package = require("rarr.package")
  local console = require("rarr.console")
  local debug = require("rarr.debug")

  local prev_on_filetype = opts.hook and opts.hook.on_filetype
  local prev_after_r_start = opts.hook and opts.hook.after_R_start

  if config.actions then
    package.configure(config.actions)
  end

  package.register_commands()

  opts.R_app = console.r_app_command()
  opts.R_cmd = "R"
  opts.bracketed_paste = true
  -- rarr renders its own ANSI-colored prompt and banner.
  -- Disable R.nvim's terminal syntax highlighting fallback so it
  -- does not override or partially recolor terminal output.
  opts.hl_term = false
  -- Let rarr/reedline receive <Esc> directly so vi mode can switch
  -- between insert and normal inside the R console.
  opts.esc_term = false
  opts.hook = opts.hook or {}

  opts.hook.on_filetype = function()
    if prev_on_filetype then
      prev_on_filetype()
    end
    local bufnr = vim.api.nvim_get_current_buf()
    package.set_keymaps(bufnr)
    console.set_toggle_keymaps(bufnr)
    debug.set_keymaps(bufnr)
  end

  opts.hook.after_R_start = function()
    if prev_after_r_start then
      prev_after_r_start()
    end
    console.setup_console()
  end
end

return M
