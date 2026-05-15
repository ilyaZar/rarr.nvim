# rarr.nvim

Neovim companion plugin for [rarr](https://github.com/ilyaZar/rarr),
a Rust-based R console with vi mode. Integrates rarr into
[R.nvim](https://github.com/R-nvim/R.nvim) and adds package-dev
keymaps, console toggle, and a mode bridge between Neovim and
rarr's reedline prompt.

## Requirements

- Neovim >= 0.10
- [rarr](https://github.com/ilyaZar/rarr) (the Rust R console)
- [R.nvim](https://github.com/R-nvim/R.nvim)

Install rarr first. Then add this plugin as an R.nvim dependency.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ilyaZar/rarr.nvim",
  lazy = true,
},
{
  "R-nvim/R.nvim",
  dependencies = { "rarr.nvim" },
  opts = function(_, opts)
    opts.rconsole_width = 0
    opts.rconsole_height = 15
    require("rarr").setup(opts)
  end,
},
```

`setup(opts)` mutates R.nvim's options table in place. Call it
inside the R.nvim `opts` function.

## DAP and debugger UI

`rarr.nvim` can start the live R console with DAP metadata so
[nvim-dap-r](https://github.com/ilyaZar/nvim-dap-r) can attach to it.
It does not require `nvim-dap`, `nvim-dap-r`, or any debugger UI plugin
for the normal R console workflow.

The boundary is:

- `rarr.nvim` starts the console and exposes DAP session metadata
- `nvim-dap-r` reads that metadata and registers an R adapter with
  `nvim-dap`
- debugger UI plugins read the active `nvim-dap` session and events

That keeps debugger panes separate from the console integration. For
the debugger UI itself, use the same generic `nvim-dap` extensions used
by other language adapters:

- [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) for scopes,
  stack frames, watches, breakpoints, and REPL/console panes
- [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) as an
  alternative `nvim-dap` UI
- [nvim-dap-virtual-text](https://github.com/theHamsta/nvim-dap-virtual-text)
  for inline variable values and stop reasons

These plugins should not need R-specific integration points in
`rarr.nvim`; they should work through `nvim-dap`.

## R.nvim options set by rarr.nvim

`setup()` sets the following R.nvim options. If you set
`hl_term` or `esc_term` to conflicting values before calling
`setup()`, you will get a warning.

| Option           | Value                | Why                         |
|------------------|----------------------|-----------------------------|
| `R_app`          | `env ... rarr`       | launch rarr as R console    |
| `R_cmd`          | `"R"`                | R.nvim's R command name     |
| `bracketed_paste`| `true`               | safe code sending in vi mode|
| `hl_term`        | `false`              | rarr renders its own ANSI   |
| `esc_term`       | `false`              | Esc must reach reedline     |

## Default keymaps

Package-dev keymaps are set on R file buffers (normal mode) and
on the console buffer (terminal mode). They require a
`DESCRIPTION` file in the project tree.

| Keymap     | Action                  | R expression             |
|------------|-------------------------|--------------------------|
| `<C-t>`    | Test current file       | `testthat::test_file()` |
| `<C-S-d>`  | Document                | `devtools::document()`   |
| `<C-b>`    | Load                    | `devtools::load_all()`   |
| `<C-S-t>`  | Test                    | `devtools::test()`       |
| `<C-S-b>`  | Install                 | `devtools::install()`    |
| `<C-S-e>`  | Check                   | `devtools::check()`      |
| `<C-/>`    | Toggle console          | --                       |

Console and shell toggle maps are configured from one top-level
`keys` table:

```lua
require("rarr").setup(opts, {
  keys = {
    console = {
      maps = { "<C-/>", "<C-_>" },
    },
    shell = {
      maps = { "<C-S-/>", "<C-?>" },
    },
  },
})
```

If the same physical key is assigned to both actors, `rarr.nvim`
shows a 20 second warning at setup and installs a warning mapping on
that key. Pressing it does not toggle either terminal; it explains the
conflict and asks you to configure different maps under
`keys.console.maps` and `keys.shell.maps`.

Set an actor's `maps` to `{}` or `false` to leave its toggle unmapped.

## Custom actions

Pass a second table to `setup()` to add or override actions:

```lua
require("rarr").setup(opts, {
  actions = {
    -- runs anywhere (no DESCRIPTION required)
    { key = "search", map = "<C-x>",
      expr = "search()", desc = "R: search" },

    -- override a default (same key replaces it)
    { key = "load", map = "<C-S-l>",
      expr = "devtools::load_all()",
      desc = "R package: load", package = true },
  },
})
```

Action fields:

- `key` (string, required) -- unique identifier
- `expr` (string or `function(bufnr) -> string`) -- R code to send
- `desc` (string, required) -- keymap description
- `map` (string) -- keymap LHS
- `command` (string) -- ex command name (e.g. `"Rload"`)
- `task_name` (string) --
  [overseer.nvim](https://github.com/stevearc/overseer.nvim) task name
- `package` (boolean, default `false`) -- guard behind `DESCRIPTION`

Actions with `package = true` only run inside an R package
directory. Actions without it run anywhere R.nvim is active.

## Makevars manager

`:RMakevars` opens a floating Makevars manager for the active R
session. The left pane lists files under `~/.R/`, with `Makevars*`
files sorted first, plus readable site Makevars files and existing
package `src/Makevars*` files when they are relevant. The right pane
is a real editable file buffer for the selected path, so normal
`:write` saves changes.

Press `Enter` on a user Makevars file to set it for future package
compilation in the running R process:

```r
Sys.setenv(R_MAKEVARS_USER = "...")
```

The active `R_MAKEVARS_USER` path is marked with `*`. Press `u` to
unset it with `Sys.unsetenv("R_MAKEVARS_USER")`. Package
`src/Makevars`, `src/Makevars.win`, and `src/Makevars.ucrt` entries
are edit-only; rarr.nvim never points `R_MAKEVARS_USER` at a
package-local Makevars file.

In the left pane, use `j`/`k` to move, `Enter` to set the active user
Makevars path, `Tab` to focus the editable preview, and `i` to focus
the top filename prompt.

The top prompt accepts either a name under `~/.R/` or a full path. If
the file does not exist, rarr.nvim asks before creating it. Explicit
selection also updates Neovim's `R_MAKEVARS_USER` environment by
default, so rarr.nvim's Overseer package tasks inherit the same user
Makevars path.

Configuration:

```lua
require("rarr").setup(opts, {
  makevars = {
    command = "RMakevars",
    user_dir = "~/.R",
    marker = "*",
    include_site = true,
    include_package = true,
    sync_overseer_env = true,
  },
})
```

Changing Makevars does not force native code to rebuild by itself.
Use a rebuild path such as `devtools::load_all(recompile = TRUE)`,
`pkgbuild::clean_dll()` followed by `devtools::load_all()`, or
`devtools::install()`/`R CMD INSTALL --preclean` when you need new
compiler flags to take effect.

## Console toggle

`Ctrl+/` toggles the R console window. When hidden, the console
is armed to restore insert mode on reopen. Window dimensions
persist across toggle cycles.

In non-R buffers inside an R package, the first cold toggle opens the
first file under `R/` so `R.nvim` can start from a real R buffer. If
the package has no files under `R/`, `rarr.nvim` creates
`R/tmp_rarr.R` with a comment that it is safe to delete.

> [!NOTE]
> The R console buffer uses `filetype=rarr_console` for UI integrations.

## Shell terminal overlay

`rarr.nvim` can also coordinate a regular shell terminal with the R
console so both occupy the same terminal slot. This is optional:
`rarr.nvim` does not try to replace your terminal plugin. Exact
overlay behavior requires a slot-aware adapter that can show, hide,
inspect, and resize the terminal window.

Recommended LazyVim/Snacks setup:

```lua
require("rarr").setup(opts, {
  keys = {
    shell = {
      maps = { "<C-S-/>", "<C-?>" },
    },
  },
  shell = {
    adapter = require("rarr.adapters.snacks_terminal").setup({
      cwd = function()
        return LazyVim.root()
      end,
    }),
  },
})
```

Basic fallback setup, using `vim.o.shell` in a plain Neovim terminal:

```lua
require("rarr").setup(opts, {
  keys = {
    shell = {
      maps = { "<C-S-/>", "<C-?>" },
    },
  },
  shell = {},
})
```

If you use another terminal plugin, provide the same adapter contract:

```lua
require("rarr").setup(opts, {
  keys = {
    shell = {
      maps = { "<C-S-/>", "<C-?>" },
    },
  },
  shell = {
    adapter = {
      show = function(ctx, handle) return handle end,
      hide = function(handle) end,
      is_visible = function(handle) return false end,
      win = function(handle) return nil end,
      resize = function(handle, ctx) end,
    },
  },
})
```

The `ctx` table contains `position`, `height`, `width`, `cwd`, and
`shell`. Adapters that ignore `ctx.height`/`ctx.width` still work, but
they cannot guarantee exact overlay with the R console.

## Troubleshooting

### `Ctrl+Shift+/` sends Backspace in tmux

When Neovim runs inside tmux in Ghostty, some keyboard/layout paths can
encode `Ctrl+Shift+/` as DEL/Backspace before Neovim receives it. In
normal mode this looks like the cursor moving one character left instead
of opening the shell terminal.

Configure Ghostty to send a CSI-u sequence for that chord:

```conf
keybind = ctrl+shift+/=csi:47;6u
```

Reload Ghostty or open a new Ghostty window, then start a fresh tmux
session. Neovim will receive the key as `<C-S-/>`, so the default
shell terminal mapping works inside tmux.

## How it works

Three actors cooperate: R.nvim owns the terminal buffer lifecycle
and code sending. rarr.nvim owns the mode bridge, winbar, and
keymaps. Optional shell adapters own regular terminal UX while
rarr.nvim only coordinates the shared terminal slot. rarr (Rust)
owns vi mode, prompt rendering, and the R session. Communication
happens through env vars at startup, key events at runtime, and
bracketed paste for code sending.

## License

[MIT](LICENSE)
