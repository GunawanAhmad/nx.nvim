# nx.nvim

Run NX targets without leaving Neovim. Pick any project and target from a native tree UI and run it in a split.

## Requirements

- Neovim 0.9+
- `find` (POSIX standard, available everywhere)
- An NX workspace (`nx.json` present)

## Installation

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

No build step. No compiled binary. No extra dependencies.

## Setup

```lua
require("nx").setup({
  -- Override the nx command (auto-detected from lockfile if nil)
  -- e.g. "pnpm nx", "yarn nx", "npx nx"
  nx_cmd = nil,

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
| `:NxPick` | Open the project tree, expand a project to see targets, run one |
| `:NxRun <project> <target> [args]` | Run directly with tab-completion |
| `:NxAffected [target]` | Run `nx affected --target=<target>` |
| `:NxGraph` | Open the NX project graph |
| `:NxRefresh` | Clear the project/target cache |

## UI

`:NxPick` opens a floating tree. All projects are listed collapsed. Press `<CR>` or `<Space>` on a project to expand it — targets are fetched async and shown inline with a loading spinner. Press `<CR>` on a target to run it.

```
╭─────── NX ────────╮
│  ▸ api            │
│  ▾ backend        │   ← expanded
│    build          │
│    lint           │
│    test           │   ← <CR> to run
│  ▸ frontend       │
│  ▸ shared         │
╰───────────────────╯
```

Keys inside the picker:

| Key | Action |
|---|---|
| `<CR>` | Expand/collapse project, or run target |
| `<Space>` | Expand/collapse project |
| `q` / `<Esc>` | Close |

## Package manager detection

Detected automatically from the workspace root lockfile:

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
vim.keymap.set("n", "<leader>nx", "<cmd>NxPick<cr>",     { desc = "NX pick & run" })
vim.keymap.set("n", "<leader>na", "<cmd>NxAffected<cr>", { desc = "NX affected" })
vim.keymap.set("n", "<leader>ng", "<cmd>NxGraph<cr>",    { desc = "NX graph" })
```

## How it works

On first use, `find` locates every `project.json` in the workspace (skipping `node_modules`, `.git`, `dist`, `.nx`). Each file is parsed and both project names and their targets are cached in a single pass. All subsequent interactions — picker, tab-completion, target expansion — read from cache with no I/O.

```
:NxPick
  └── find . -name project.json ...   (one pass, skips heavy dirs)
        └── parse each project.json   (name + targets cached together)
              └── floating tree UI    (projects collapsed, expand to load targets)
                    └── <CR> on target
                          └── terminal: pnpm nx run <project>:<target>
```
