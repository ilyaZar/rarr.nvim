-- Overseer template: R package actions (rarr.nvim)
-- Auto-loaded by overseer from the runtimepath.
-- Appears in :OverseerRun when editing an R package file.

return {
  condition = {
    filetype = { "r", "rmd", "quarto" },
  },
  generator = function(opts)
    local package = require("rarr.package")
    local description = vim.fs.find("DESCRIPTION", {
      upward = true,
      path = opts.dir,
      type = "file",
    })[1]

    if not description then
      return {}
    end

    local cwd = vim.fs.dirname(description)
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
