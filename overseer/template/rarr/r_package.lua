-- Overseer template: R package actions (rarr.nvim)
-- Auto-loaded by overseer from the runtimepath.
-- Appears in :OverseerRun when editing an R package file.

return {
  condition = {
    filetype = require("rarr.context").r_filetypes,
  },
  generator = function(opts)
    local context = require("rarr.context")
    local package = require("rarr.package")
    local cwd = context.package_root(opts.dir)

    if not cwd then
      return {}
    end

    local templates = {}
    for _, action in ipairs(package.actions) do
      if action.task_name then
        templates[#templates + 1] = {
          name = action.task_name,
          builder = function()
            return package.task_definition(action.key, cwd)
          end,
        }
      end
    end
    return templates
  end,
}
