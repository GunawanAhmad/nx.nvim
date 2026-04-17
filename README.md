# nx.nvim

Run NX targets without leaving Neovim. Pick any project and target from a fuzzy menu and run it in a split.

## Why

On large monorepos, looking up projects and targets can be slow. The bundled `nx-runner` binary walks the filesystem and parses `project.json` files directly, making listings near-instant.

## Requirements

- Neovim 0.9+
- Go 1.21+ (to build the binary)
- An NX workspace (`nx.json` present)

## Installation

### 1. Build the binary

```bash
cd <plugin-dir>/go
go build -o ~/.local/bin/nx-runner .
```

Or install it anywhere on your `$PATH`.

### 2. Add the plugin

**lazy.nvim**
```lua
{
  "gunawanahmad/nx.nvim",
  config = function()
    require("nx").setup()
  end,
}
```

**packer.nvim**
```lua
use {
  "gunawanahmad/nx.nvim",
  config = function()
    require("nx").setup()
  end,
}
```

## Setup

```lua
require("nx").setup({
  -- Override the nx command (auto-detected from lockfile if nil)
  -- e.g. "pnpm nx", "yarn nx", "npx nx"
  nx_cmd = nil,

  -- Path to nx-runner binary (auto-resolved if nil)
  runner_bin = nil,

  -- Terminal split style: "horizontal" | "vertical" | "float"
  terminal = "horizontal",

  float_opts = {
    width = 0.8,
    height = 0.8,
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:NxPick` | Interactively select a project then a target and run it |
| `:NxRun <project> <target> [args]` | Run directly with tab-completion |
| `:NxAffected [target]` | Run `nx affected --target=<target>` |
| `:NxGraph` | Open the NX project graph |

## Package manager detection

The plugin (and binary) automatically detect your package manager from the workspace root:

| Lockfile | Command used |
|---|---|
| `pnpm-lock.yaml` | `pnpm nx` |
| `yarn.lock` | `yarn nx` |
| `bun.lockb` / `bun.lock` | `bunx nx` |
| `package-lock.json` | `npx nx` |
| none / global nx | `nx` |

Override with `nx_cmd` in setup if needed.

## Suggested keymaps

```lua
vim.keymap.set("n", "<leader>nx", "<cmd>NxPick<cr>", { desc = "NX pick & run" })
vim.keymap.set("n", "<leader>na", "<cmd>NxAffected<cr>", { desc = "NX affected" })
vim.keymap.set("n", "<leader>ng", "<cmd>NxGraph<cr>", { desc = "NX graph" })
```

## How it works

```
:NxPick
  └── nx-runner projects          (reads project.json files, no Node spawn)
        └── vim.ui.select (project)
              └── nx-runner targets <project>   (parses same project.json)
                    └── vim.ui.select (target)
                          └── terminal: pnpm nx run <project>:<target>
```

If `nx-runner` is not found, the plugin falls back to calling the NX CLI directly.
