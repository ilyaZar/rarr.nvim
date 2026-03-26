local M = {}

--- Detect R + rarr versions for the winbar label.
--- @return string label e.g. "R 4.5.3 via RARR v0.1.0 (...)"
function M.terminal_label()
  local r_ver = nil
  local rarr_ver = nil

  -- Get rarr version
  if vim.fn.executable("rarr") == 1 then
    local out = vim.fn.systemlist({ "rarr", "--version" })
    if vim.v.shell_error == 0 and out[1] then
      rarr_ver = out[1]:match("(%d+%.%d+%.%d+)")
    end
  end

  -- Get R version
  if vim.fn.executable("R") == 1 then
    local out = vim.fn.systemlist({ "R", "--version" })
    if vim.v.shell_error == 0 and out[1] then
      r_ver = out[1]:match("R version ([0-9.]+)")
    end
  end

  -- Build label
  local label
  if r_ver and rarr_ver then
    label = "R " .. r_ver .. " via RARR v" .. rarr_ver
  elseif rarr_ver then
    label = "RARR v" .. rarr_ver
  elseif r_ver then
    label = "R " .. r_ver
  else
    label = "R"
  end

  return label
    .. " (:cmds for command list, Ctrl+/ to toggle, Ctrl+D to quit())"
end

return M
