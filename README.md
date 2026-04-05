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
- `task_name` (string) -- [overseer.nvim](https://github.com/stevearc/overseer.nvim) task name
- `package` (boolean, default `false`) -- guard behind `DESCRIPTION`

Actions with `package = true` only run inside an R package
directory. Actions without it run anywhere R.nvim is active.

## Console toggle

`Ctrl+/` toggles the R console window. When hidden, the console
is armed to restore insert mode on reopen. Window dimensions
persist across toggle cycles.

In non-R buffers inside an R package, the first cold toggle opens the
first file under `R/` so `R.nvim` can start from a real R buffer. If
the package has no files under `R/`, `rarr.nvim` creates
`R/tmp_rarr.R` with a comment that it is safe to delete.

## How it works

Three actors cooperate: R.nvim owns the terminal buffer lifecycle
and code sending. rarr.nvim owns the mode bridge, winbar, and
keymaps. rarr (Rust) owns vi mode, prompt rendering, and the R
session. Communication happens through env vars at startup, key
events at runtime, and bracketed paste for code sending.

## License

[MIT](LICENSE)
