local M = {}

local uv = vim.uv or vim.loop

local config = {
  enabled = true,
  host = "127.0.0.1",
  port = 0,
  metadata_path = nil,
}

local function joinpath(...)
  return table.concat({ ... }, "/")
end

local function default_metadata_path()
  if vim.env.RNVIM_TMPDIR and vim.env.RNVIM_TMPDIR ~= "" then
    return joinpath(vim.env.RNVIM_TMPDIR, "rarr-dap-session.json")
  end

  if vim.env.XDG_RUNTIME_DIR and vim.env.XDG_RUNTIME_DIR ~= "" then
    return joinpath(vim.env.XDG_RUNTIME_DIR, "rarr", "dap-session.json")
  end

  return joinpath(uv.os_tmpdir(), "rarr-dap-session.json")
end

local function read_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

local function process_exists(pid)
  if type(pid) ~= "number" or pid <= 0 then
    return true
  end

  if vim.fn.has("unix") == 1 then
    return vim.fn.isdirectory("/proc/" .. pid) == 1
  end

  return true
end

local function console_bufnr()
  local ok, builtin = pcall(require, "r.term.builtin")
  if not ok then
    return nil
  end
  return builtin.get_buf_nr()
end

local function console_job_id(bufnr)
  if not bufnr then
    return nil
  end

  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok then
    return job_id
  end
end

function M.setup(user_config)
  if user_config == false then
    config.enabled = false
    return
  end

  config = vim.tbl_deep_extend("force", config, user_config or {})
  config.enabled = config.enabled ~= false
end

function M.metadata_path()
  return config.metadata_path or default_metadata_path()
end

function M.rarr_args()
  if not config.enabled then
    return {}
  end

  local args = {
    "--dap",
    "--dap-host",
    config.host,
    "--dap-port",
    tostring(config.port or 0),
  }

  if config.metadata_path then
    vim.list_extend(args, { "--dap-metadata", config.metadata_path })
  end

  return args
end

function M.session()
  if not config.enabled then
    return nil
  end

  local metadata_path = M.metadata_path()
  local session = read_json(metadata_path)
  if not session or not session.host or not session.port then
    return nil
  end
  if not process_exists(session.pid) then
    return nil
  end

  local bufnr = console_bufnr()
  session.metadata_path = metadata_path
  session.bufnr = bufnr
  session.job_id = console_job_id(bufnr)

  return session
end

return M
