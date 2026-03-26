-- Re-export task_definition from package module for overseer templates.
local M = {}

--- Build an overseer task definition for a given action key.
--- @param action_key string  one of the keys from package.actions
--- @param cwd string|nil     override working directory
--- @return table|nil
function M.task_definition(action_key, cwd)
  return require("rarr.package").task_definition(action_key, cwd)
end

return M
