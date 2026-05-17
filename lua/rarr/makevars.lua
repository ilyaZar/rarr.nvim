local M = {}

local context = require("rarr.context")

local DEFAULT_CONFIG = {
  command = "RMakevars",
  user_dir = "~/.R",
  marker = "*",
  include_site = true,
  include_package = true,
  sync_overseer_env = true,
}

local config = vim.deepcopy(DEFAULT_CONFIG)
local ns = vim.api.nvim_create_namespace("RarrMakevars")

local state = {
  active_path = nil,
}

local ui = nil

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
end

local function user_dir()
  return normalize_path(config.user_dir)
end

local function is_abs(path)
  return path:match("^/")
    or path:match("^%a:[/\\]")
    or path:match("^\\\\")
end

local function resolve_input_path(input)
  input = trim(input)
  if input == "" then
    return nil
  end

  if input:sub(1, 1) == "~" or is_abs(input) then
    return normalize_path(input)
  end

  return normalize_path(vim.fs.joinpath(user_dir(), input))
end

local function readable(path)
  return path and vim.fn.filereadable(path) == 1
end

local function r_string(value)
  return string.format(
    '"%s"',
    value:gsub("\\", "\\\\"):gsub('"', '\\"')
  )
end

local function active_path()
  if state.active_path then
    return state.active_path
  end

  local env = vim.env.R_MAKEVARS_USER
  if env and env ~= "" then
    return normalize_path(env)
  end
end

local function paths_equal(left, right)
  left = normalize_path(left)
  right = normalize_path(right)
  return left and right and left == right
end

local function parent_dir(path)
  return vim.fs.dirname(path)
end

local function ensure_parent(path)
  local dir = parent_dir(path)
  if dir and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

local function send_to_r(expr)
  local ok, result = pcall(require("r.send").cmd, expr)
  if not ok or result == false then
    vim.notify(
      "R is not ready for Makevars changes",
      vim.log.levels.WARN,
      { title = "rarr.nvim" }
    )
    return false
  end
  return true
end

local function set_active(path)
  path = normalize_path(path)
  if not path then
    return
  end

  if not send_to_r(
    "Sys.setenv(R_MAKEVARS_USER = " .. r_string(path) .. ")"
  ) then
    return
  end

  state.active_path = path
  if config.sync_overseer_env then
    vim.env.R_MAKEVARS_USER = path
  end

  vim.notify(
    "R_MAKEVARS_USER -> " .. path,
    vim.log.levels.INFO,
    { title = "rarr.nvim" }
  )
end

local function unset_active()
  if not send_to_r('Sys.unsetenv("R_MAKEVARS_USER")') then
    return
  end

  state.active_path = nil
  if config.sync_overseer_env then
    vim.env.R_MAKEVARS_USER = nil
  end

  vim.notify(
    "R_MAKEVARS_USER unset",
    vim.log.levels.INFO,
    { title = "rarr.nvim" }
  )
end

local function r_home()
  if vim.fn.executable("R") == 0 then
    return nil
  end

  local out = vim.fn.systemlist({ "R", "RHOME" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end

  return normalize_path(out[1])
end

local function add_entry(entries, entry)
  entries[#entries + 1] = entry
end

local function scan_user_files(entries)
  local dir = user_dir()
  add_entry(entries, {
    kind = "header",
    label = dir,
    selectable = false,
  })

  if vim.fn.isdirectory(dir) == 0 then
    add_entry(entries, {
      kind = "info",
      label = "(directory does not exist yet)",
      selectable = false,
    })
    return
  end

  local files = {}
  local handle = vim.uv.fs_scandir(dir)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if typ == "file" or typ == "link" then
        files[#files + 1] = name
      end
    end
  end

  table.sort(files, function(a, b)
    local am = a:match("^Makevars") ~= nil
    local bm = b:match("^Makevars") ~= nil
    if am ~= bm then
      return am
    end
    return a < b
  end)

  if #files == 0 then
    add_entry(entries, {
      kind = "info",
      label = "(no files under ~/.R)",
      selectable = false,
    })
    return
  end

  for _, name in ipairs(files) do
    local path = normalize_path(vim.fs.joinpath(dir, name))
    add_entry(entries, {
      kind = "user",
      label = name,
      path = path,
      selectable = true,
      settable = true,
      editable = true,
    })
  end
end

local function has_path(entries, path)
  for _, entry in ipairs(entries) do
    if entry.path and paths_equal(entry.path, path) then
      return true
    end
  end
  return false
end

local function scan_current_custom_path(entries)
  local path = active_path()
  if not path or has_path(entries, path) then
    return
  end

  add_entry(entries, {
    kind = "header",
    label = "current R_MAKEVARS_USER",
    selectable = false,
  })
  add_entry(entries, {
    kind = "custom",
    label = path,
    path = path,
    selectable = true,
    settable = true,
    editable = true,
  })
end

local function scan_site_files(entries)
  if not config.include_site then
    return
  end

  local candidates = {}
  if vim.env.R_MAKEVARS_SITE and vim.env.R_MAKEVARS_SITE ~= "" then
    candidates[#candidates + 1] = normalize_path(vim.env.R_MAKEVARS_SITE)
  end

  local home = r_home()
  if home then
    local arch = vim.env.R_ARCH
    if arch and arch ~= "" then
      candidates[#candidates + 1] = normalize_path(
        vim.fs.joinpath(home, "etc", arch, "Makevars.site")
      )
    end
    candidates[#candidates + 1] = normalize_path(
      vim.fs.joinpath(home, "etc", "Makevars.site")
    )
  end

  local seen = {}
  local visible = {}
  for _, path in ipairs(candidates) do
    if path and not seen[path] and readable(path) then
      visible[#visible + 1] = path
      seen[path] = true
    end
  end

  if #visible == 0 then
    return
  end

  add_entry(entries, {
    kind = "header",
    label = "site Makevars",
    selectable = false,
  })
  for _, path in ipairs(visible) do
    add_entry(entries, {
      kind = "site",
      label = path,
      path = path,
      selectable = true,
      settable = false,
      editable = true,
    })
  end
end

local function scan_package_files(entries)
  if not config.include_package then
    return
  end

  local root = ui and ui.package_root or context.package_root(0)
  if not root then
    return
  end

  local src = vim.fs.joinpath(root, "src")
  local candidates = {
    "Makevars",
    "Makevars.win",
    "Makevars.ucrt",
  }
  local visible = {}
  for _, name in ipairs(candidates) do
    local path = normalize_path(vim.fs.joinpath(src, name))
    if readable(path) then
      visible[#visible + 1] = path
    end
  end

  if #visible == 0 then
    return
  end

  add_entry(entries, {
    kind = "header",
    label = "package src Makevars (edit only)",
    selectable = false,
  })
  for _, path in ipairs(visible) do
    add_entry(entries, {
      kind = "package",
      label = vim.fs.relpath(root, path) or path,
      path = path,
      selectable = true,
      settable = false,
      editable = true,
    })
  end
end

local function build_entries()
  local entries = {}
  add_entry(entries, {
    kind = "unset",
    label = "unset R_MAKEVARS_USER",
    selectable = true,
    settable = true,
    editable = false,
  })

  scan_user_files(entries)
  scan_current_custom_path(entries)
  scan_site_files(entries)
  scan_package_files(entries)
  return entries
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function set_buf_lines(buf, lines, modifiable)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", modifiable, { buf = buf })
end

local function line_for_entry(entry)
  if entry.kind == "header" then
    return " " .. entry.label
  end
  if entry.kind == "info" then
    return "   " .. entry.label
  end

  local marker = " "
  if entry.kind == "unset" and not active_path() then
    marker = config.marker
  elseif entry.path and paths_equal(entry.path, active_path()) then
    marker = config.marker
  end

  local suffix = entry.settable and "" or "  [edit only]"
  return marker .. " " .. entry.label .. suffix
end

local function open_file_in_preview(path)
  if not ui or not valid_win(ui.right_win) then
    return
  end

  local current = vim.api.nvim_win_get_buf(ui.right_win)
  if valid_buf(current)
    and vim.bo[current].modified
    and normalize_path(vim.api.nvim_buf_get_name(current)) ~= normalize_path(path)
  then
    vim.notify(
      "Write or discard the current Makevars buffer before switching",
      vim.log.levels.WARN,
      { title = "rarr.nvim" }
    )
    return
  end

  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.api.nvim_win_set_buf(ui.right_win, buf)
  vim.bo[buf].buflisted = true
end

local function show_info(lines)
  if not ui or not valid_win(ui.right_win) then
    return
  end

  if not valid_buf(ui.info_buf) then
    ui.info_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = ui.info_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = ui.info_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = ui.info_buf })
  end

  set_buf_lines(ui.info_buf, lines, false)
  vim.api.nvim_win_set_buf(ui.right_win, ui.info_buf)
end

local function preview_entry(entry)
  if not entry then
    return
  end

  if entry.path then
    open_file_in_preview(entry.path)
    return
  end

  show_info({
    "R_MAKEVARS_USER is unset.",
    "",
    "R will use its documented default user Makevars lookup.",
    "",
    "Press Enter on a file under ~/.R to set R_MAKEVARS_USER.",
    "Press u to unset it again.",
  })
end

local function first_selectable(entries)
  for i, entry in ipairs(entries) do
    if entry.selectable then
      return i
    end
  end
  return 1
end

local function render_left()
  if not ui or not valid_buf(ui.left_buf) then
    return
  end

  local lines = {}
  for _, entry in ipairs(ui.entries) do
    lines[#lines + 1] = line_for_entry(entry)
  end

  set_buf_lines(ui.left_buf, lines, false)
  vim.api.nvim_buf_clear_namespace(ui.left_buf, ns, 0, -1)

  for row, entry in ipairs(ui.entries) do
    if entry.kind == "header" then
      vim.api.nvim_buf_add_highlight(
        ui.left_buf,
        ns,
        "Title",
        row - 1,
        0,
        -1
      )
    elseif entry.kind == "info" then
      vim.api.nvim_buf_add_highlight(
        ui.left_buf,
        ns,
        "Comment",
        row - 1,
        0,
        -1
      )
    elseif line_for_entry(entry):sub(1, 1) == config.marker then
      vim.api.nvim_buf_add_highlight(
        ui.left_buf,
        ns,
        "DiagnosticOk",
        row - 1,
        0,
        1
      )
    elseif not entry.settable then
      vim.api.nvim_buf_add_highlight(
        ui.left_buf,
        ns,
        "DiagnosticInfo",
        row - 1,
        0,
        -1
      )
    end
  end
end

local function set_index(index)
  if not ui then
    return
  end

  local entry = ui.entries[index]
  if not entry or not entry.selectable then
    return
  end

  ui.index = index
  if valid_win(ui.left_win) then
    vim.api.nvim_win_set_cursor(ui.left_win, { index, 0 })
  end
  preview_entry(entry)
end

local function move_index(delta)
  if not ui then
    return
  end

  local index = ui.index
  for _ = 1, #ui.entries do
    index = index + delta
    if index < 1 then
      index = #ui.entries
    elseif index > #ui.entries then
      index = 1
    end
    if ui.entries[index].selectable then
      set_index(index)
      return
    end
  end
end

local function refresh_entries()
  if not ui then
    return
  end

  ui.entries = build_entries()
  ui.index = math.min(ui.index or 1, #ui.entries)
  if not ui.entries[ui.index] or not ui.entries[ui.index].selectable then
    ui.index = first_selectable(ui.entries)
  end
  render_left()
  set_index(ui.index)
end

local function close_ui()
  if not ui then
    return
  end

  for _, win in ipairs({ ui.top_win, ui.left_win, ui.right_win }) do
    if valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  for _, buf in ipairs({ ui.top_buf, ui.left_buf, ui.info_buf }) do
    if valid_buf(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  ui = nil
end

local function current_entry()
  if ui then
    return ui.entries[ui.index]
  end
end

local function choose_current()
  local entry = current_entry()
  if not entry then
    return
  end

  if entry.kind == "unset" then
    unset_active()
    refresh_entries()
    return
  end

  if entry.path and entry.settable then
    set_active(entry.path)
    refresh_entries()
    return
  end

  if entry.path then
    preview_entry(entry)
    if valid_win(ui.right_win) then
      vim.api.nvim_set_current_win(ui.right_win)
    end
  end
end

local function set_top_prompt(text)
  if not ui or not valid_buf(ui.top_buf) then
    return
  end
  set_buf_lines(ui.top_buf, { text or "" }, true)
end

local function create_file(path)
  ensure_parent(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

local function focus_matching_path(path)
  if not ui then
    return
  end

  for i, entry in ipairs(ui.entries) do
    if entry.path and paths_equal(entry.path, path) then
      set_index(i)
      return
    end
  end
end

local function create_and_select(path)
  create_file(path)
  refresh_entries()
  focus_matching_path(path)
  set_active(path)
  refresh_entries()
  focus_matching_path(path)
  open_file_in_preview(path)
end

local function confirm_create(path)
  vim.ui.select({ "create", "cancel" }, {
    prompt = "Create " .. path .. "?",
  }, function(choice)
    if choice == "create" then
      create_and_select(path)
    end
  end)
end

local function submit_prompt()
  if not ui or not valid_buf(ui.top_buf) then
    return
  end

  local line = vim.api.nvim_buf_get_lines(ui.top_buf, 0, 1, false)[1]
  local path = resolve_input_path(line)
  if not path then
    return
  end

  set_top_prompt("")
  if readable(path) then
    refresh_entries()
    focus_matching_path(path)
    set_active(path)
    refresh_entries()
    focus_matching_path(path)
    open_file_in_preview(path)
    return
  end

  confirm_create(path)
end

local function make_scratch_buf(filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
  end
  return buf
end

local function open_window(buf, opts)
  return vim.api.nvim_open_win(buf, opts.enter or false, {
    relative = "editor",
    width = opts.width,
    height = opts.height,
    row = opts.row,
    col = opts.col,
    style = "minimal",
    border = opts.border or "single",
    title = opts.title,
    title_pos = opts.title_pos or "center",
    footer = opts.footer,
    footer_pos = opts.footer and "center" or nil,
  })
end

local function window_layout()
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local width = math.max(78, math.floor(editor_w * 0.84))
  local height = math.max(20, math.floor(editor_h * 0.72))
  width = math.min(width, editor_w - 4)
  height = math.min(height, editor_h - 4)

  local row = math.floor((editor_h - height) / 2)
  local col = math.floor((editor_w - width) / 2)
  local top_height = 1
  local body_row = row + top_height + 2
  local body_height = height - top_height - 2
  local left_width = math.max(28, math.floor(width * 0.35))
  local right_width = width - left_width - 2

  return {
    row = row,
    col = col,
    width = width,
    top_height = top_height,
    body_row = body_row,
    body_height = body_height,
    left_width = left_width,
    right_width = right_width,
    right_col = col + left_width + 2,
  }
end

local function set_ui_keymaps()
  local kopts = { buffer = ui.left_buf, noremap = true, silent = true }

  vim.keymap.set("n", "j", function() move_index(1) end, kopts)
  vim.keymap.set("n", "<Down>", function() move_index(1) end, kopts)
  vim.keymap.set("n", "k", function() move_index(-1) end, kopts)
  vim.keymap.set("n", "<Up>", function() move_index(-1) end, kopts)
  vim.keymap.set("n", "<CR>", choose_current, kopts)
  vim.keymap.set("n", "u", function()
    unset_active()
    refresh_entries()
  end, kopts)
  vim.keymap.set("n", "r", refresh_entries, kopts)
  for _, lhs in ipairs({ "l", "<Tab>" }) do
    vim.keymap.set("n", lhs, function()
      if valid_win(ui.right_win) then
        vim.api.nvim_set_current_win(ui.right_win)
      end
    end, kopts)
  end
  vim.keymap.set("n", "i", function()
    if valid_win(ui.top_win) then
      vim.api.nvim_set_current_win(ui.top_win)
      vim.cmd("startinsert")
    end
  end, kopts)
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close_ui, kopts)
  end

  local top_opts = { buffer = ui.top_buf, noremap = true, silent = true }
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if vim.api.nvim_get_mode().mode == "i" then
      vim.cmd("stopinsert")
    end
    submit_prompt()
  end, top_opts)
  vim.keymap.set("n", "<Tab>", function()
    if valid_win(ui.left_win) then
      vim.api.nvim_set_current_win(ui.left_win)
    end
  end, top_opts)
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close_ui, top_opts)
  end
end

local function open_ui()
  if ui then
    close_ui()
  end

  local layout = window_layout()
  local top_buf = make_scratch_buf("rarr_makevars_prompt")
  local left_buf = make_scratch_buf("rarr_makevars")

  set_buf_lines(top_buf, { "" }, true)
  set_buf_lines(left_buf, {}, false)

  ui = {
    top_buf = top_buf,
    left_buf = left_buf,
    info_buf = nil,
    package_root = context.package_root(0),
    entries = {},
    index = 1,
  }

  local active = active_path()
  local active_label = active and (" active: " .. active) or " active: <unset>"
  local top_title = {
    { " Editing Makevars -- setting R_MAKEVARS_USER path ", "FloatTitle" },
    { active_label .. " ", active and "DiagnosticOk" or "Comment" },
  }

  ui.top_win = open_window(top_buf, {
    enter = false,
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.top_height,
    title = top_title,
    footer = {
      { " type a file name or path, then " },
      { "CR", "DiagnosticOk" },
      { " " },
    },
  })

  ui.left_win = open_window(left_buf, {
    enter = true,
    row = layout.body_row,
    col = layout.col,
    width = layout.left_width,
    height = layout.body_height,
    title = { { " Makevars files ", "FloatTitle" } },
    title_pos = "left",
    footer = {
      { "j/k", "DiagnosticOk" },
      { ":nav  " },
      { "CR", "DiagnosticOk" },
      { ":set  " },
      { "u", "DiagnosticOk" },
      { ":unset  " },
      { "Tab", "DiagnosticOk" },
      { ":edit  " },
      { "i", "DiagnosticOk" },
      { ":name  " },
      { "q", "DiagnosticOk" },
      { ":quit " },
    },
  })

  ui.right_win = open_window(make_scratch_buf("text"), {
    enter = false,
    row = layout.body_row,
    col = layout.right_col,
    width = layout.right_width,
    height = layout.body_height,
    title = { { " editable preview ", "FloatTitle" } },
    title_pos = "left",
  })

  vim.api.nvim_set_option_value("cursorline", true, { win = ui.left_win })
  vim.api.nvim_set_option_value("wrap", false, { win = ui.left_win })

  set_ui_keymaps()
  refresh_entries()
  vim.api.nvim_set_current_win(ui.left_win)
end

function M.setup(user_config)
  if user_config == false then
    config.enabled = false
    return
  end

  config = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(DEFAULT_CONFIG),
    user_config or {}
  )
  config.enabled = true
end

function M.register_commands()
  if config.enabled == false then
    return
  end
  if vim.g.rarr_makevars_commands_registered then
    return
  end

  vim.api.nvim_create_user_command(config.command, open_ui, {
    desc = "Manage R Makevars files",
  })
  vim.g.rarr_makevars_commands_registered = true
end

function M.task_env()
  if config.enabled == false or not config.sync_overseer_env then
    return nil
  end

  local path = active_path()
  if not path then
    return nil
  end

  return {
    R_MAKEVARS_USER = path,
  }
end

return M
