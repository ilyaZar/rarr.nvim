local M = {}

local DEFAULT_KEYS = {
  console = {
    maps = { "<C-/>", "<C-_>" },
  },
  shell = {
    maps = { "<C-S-/>", "<C-?>" },
  },
}

local ACTOR_LABELS = {
  console = "R console toggle",
  shell = "shell terminal toggle",
}

local state = {
  keys = vim.deepcopy(DEFAULT_KEYS),
  enabled = {
    console = true,
    shell = false,
  },
  active_maps = {
    console = {},
    shell = {},
  },
  conflicts_by_lhs = {},
  conflicts = {},
}

local function canonical_lhs(lhs)
  local aliases = {
    ["<C-/>"] = "<C-/>",
    ["<C-_>"] = "<C-/>",
    ["<C-S-/>"] = "<C-S-/>",
    ["<C-?>"] = "<C-S-/>",
  }
  return aliases[lhs] or lhs
end

local function normalize_maps(maps)
  if maps == false then
    return {}
  end
  if type(maps) ~= "table" then
    return {}
  end

  local normalized = {}
  local seen = {}
  for _, lhs in ipairs(maps) do
    if type(lhs) == "string" and lhs ~= "" and not seen[lhs] then
      normalized[#normalized + 1] = lhs
      seen[lhs] = true
    end
  end
  return normalized
end

local function normalize_keys(user_keys)
  user_keys = user_keys or {}
  local keys = vim.deepcopy(DEFAULT_KEYS)

  for actor, _ in pairs(DEFAULT_KEYS) do
    local actor_keys = user_keys[actor]
    if type(actor_keys) == "table" and actor_keys.maps ~= nil then
      keys[actor].maps = normalize_maps(actor_keys.maps)
    end
  end

  return keys
end

local function conflict_message(conflict)
  local console = table.concat(conflict.actors.console or {}, ", ")
  local shell = table.concat(conflict.actors.shell or {}, ", ")
  return table.concat({
    "Keymap conflict: " .. conflict.display
      .. " is assigned to both "
      .. ACTOR_LABELS.console
      .. " ("
      .. console
      .. ") and "
      .. ACTOR_LABELS.shell
      .. " ("
      .. shell
      .. ").",
    "No action was run. Configure different keys under keys.console.maps and keys.shell.maps.",
  }, "\n")
end

local function notify_conflict(conflict)
  vim.notify(conflict_message(conflict), vim.log.levels.ERROR, {
    title = "rarr.nvim",
    timeout = 20000,
  })
end

local function rebuild_maps()
  state.active_maps = {
    console = {},
    shell = {},
  }
  state.conflicts_by_lhs = {}
  state.conflicts = {}

  local by_canonical = {}
  for actor, actor_keys in pairs(state.keys) do
    if state.enabled[actor] then
      for _, lhs in ipairs(actor_keys.maps or {}) do
        local canonical = canonical_lhs(lhs)
        by_canonical[canonical] = by_canonical[canonical] or {}
        by_canonical[canonical][actor] = by_canonical[canonical][actor] or {}
        table.insert(by_canonical[canonical][actor], lhs)
      end
    end
  end

  for canonical, actors in pairs(by_canonical) do
    local actor_count = 0
    for _ in pairs(actors) do
      actor_count = actor_count + 1
    end

    if actor_count > 1 then
      local conflict = {
        canonical = canonical,
        display = canonical,
        actors = actors,
      }
      table.insert(state.conflicts, conflict)
      for _, lhses in pairs(actors) do
        for _, lhs in ipairs(lhses) do
          state.conflicts_by_lhs[lhs] = conflict
        end
      end
    end
  end

  for actor, actor_keys in pairs(state.keys) do
    if state.enabled[actor] then
      for _, lhs in ipairs(actor_keys.maps or {}) do
        if not state.conflicts_by_lhs[lhs] then
          table.insert(state.active_maps[actor], lhs)
        end
      end
    end
  end
end

function M.setup(config)
  config = config or {}
  state.keys = normalize_keys(config.keys)
  state.enabled = {
    console = true,
    shell = config.shell ~= nil,
  }
  rebuild_maps()

  if #state.conflicts > 0 then
    vim.schedule(function()
      for _, conflict in ipairs(state.conflicts) do
        notify_conflict(conflict)
      end
    end)
  end
end

function M.set_actor_keymaps(actor, modes, bufnr, rhs, desc)
  for _, lhs in ipairs(state.active_maps[actor] or {}) do
    vim.keymap.set(modes, lhs, rhs, {
      buffer = bufnr,
      desc = desc,
      silent = true,
    })
  end

  for lhs, conflict in pairs(state.conflicts_by_lhs) do
    if conflict.actors[actor] then
      vim.keymap.set(modes, lhs, function()
        notify_conflict(conflict)
      end, {
        buffer = bufnr,
        desc = "Show rarr.nvim keymap conflict",
        silent = true,
      })
    end
  end
end

function M.keys(actor)
  return vim.deepcopy(state.active_maps[actor] or {})
end

return M
