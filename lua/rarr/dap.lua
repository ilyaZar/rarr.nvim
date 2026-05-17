local M = {}

local uv = vim.uv or vim.loop

local config = {
  enabled = true,
  host = "127.0.0.1",
  port = 0,
  metadata_path = nil,
  auto_attach = false,
  auto_attach_delay_ms = 100,
  auto_attach_timeout_ms = 5000,
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

local function dap_r_is_active(dap_r)
  if type(dap_r.is_active) == "function" then
    return dap_r.is_active()
  end

  local ok, dap = pcall(require, "dap")
  if not ok or type(dap.session) ~= "function" then
    return false
  end

  local session = dap.session()
  return session and session.config and session.config.type == "r"
end

function M.auto_attach()
  if not config.enabled or not config.auto_attach then
    return
  end

  local ok, dap_r = pcall(require, "dap-r")
  if not ok then
    return
  end

  local deadline = uv.now() + (config.auto_attach_timeout_ms or 5000)

  local function poll()
    if dap_r_is_active(dap_r) then
      return
    end

    local session = M.session()
    if session then
      local attached, err = pcall(dap_r.attach, {
        host = session.host,
        port = session.port,
      })
      if not attached then
        vim.notify(tostring(err), vim.log.levels.WARN)
      end
      return
    end

    if uv.now() > deadline then
      return
    end

    vim.defer_fn(poll, config.auto_attach_delay_ms or 100)
  end

  vim.defer_fn(poll, config.auto_attach_delay_ms or 100)
end

return M
