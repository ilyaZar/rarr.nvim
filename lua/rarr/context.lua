local M = {}

M.r_filetypes = { "r", "rmd", "quarto" }

local function start_path(start)
  if type(start) == "string" then
    if vim.fn.isdirectory(start) == 1 then
      return start
    end
    return vim.fs.dirname(start)
  end

  local bufnr = start or 0
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return vim.uv.cwd()
  end

  local term_cwd = path:match("^term://(.-)//%d+:")
  if term_cwd then
    return term_cwd
  end

  if vim.fn.isdirectory(path) == 1 then
    return path
  end

  return vim.fs.dirname(path)
end

function M.is_r_filetype(bufnr)
  local filetype = vim.bo[bufnr or 0].filetype
  return vim.tbl_contains(M.r_filetypes, filetype)
end

function M.package_root(start)
  local found = vim.fs.find("DESCRIPTION", {
    upward = true,
    path = start_path(start),
    type = "file",
  })[1]

  if found then
    return vim.fs.dirname(found)
  end
end

function M.is_package_context(start)
  return M.package_root(start) ~= nil
end

return M
