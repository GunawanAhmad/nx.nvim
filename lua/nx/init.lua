local M = {}

local _cache = { root = nil, projects = nil, targets = {} }
local ns = vim.api.nvim_create_namespace("nx_picker")

local config = {
  nx_cmd = nil,       -- auto-detected if nil (pnpm/yarn/bun/npx/nx)
  terminal = "horizontal", -- "horizontal" | "vertical" | "float"
  float_opts = { width = 0.8, height = 0.8 },
}

local function get_workspace_root()
  local path = vim.fn.getcwd()
  while path ~= "/" do
    if vim.fn.filereadable(path .. "/nx.json") == 1 then return path end
    path = vim.fn.fnamemodify(path, ":h")
  end
  return nil
end

local function detect_nx_cmd(root)
  if config.nx_cmd then return config.nx_cmd end
  if vim.fn.filereadable(root .. "/pnpm-lock.yaml") == 1 then return "pnpm nx" end
  if vim.fn.filereadable(root .. "/yarn.lock") == 1 then return "yarn nx" end
  if vim.fn.filereadable(root .. "/bun.lockb") == 1 or vim.fn.filereadable(root .. "/bun.lock") == 1 then
    return "bunx nx"
  end
  if vim.fn.filereadable(root .. "/package-lock.json") == 1 then return "npx nx" end
  if vim.fn.executable("nx") == 1 then return "nx" end
  return "npx nx"
end

local function run_in_terminal(cmd)
  local term = config.terminal
  if term == "float" then
    local w = math.floor(vim.o.columns * config.float_opts.width)
    local h = math.floor(vim.o.lines * config.float_opts.height)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = w, height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      style = "minimal", border = "rounded",
    })
    vim.fn.termopen(cmd)
    vim.cmd("startinsert")
  elseif term == "vertical" then
    vim.cmd("vsplit | terminal " .. cmd)
    vim.cmd("startinsert")
  else
    vim.cmd("split | terminal " .. cmd)
    vim.cmd("startinsert")
  end
end

-- find all project.json files under root, skipping heavy dirs
-- TODO: add support for non find based discovery
local find_cmd = "find %s \\( -name node_modules -o -name .git -o -name dist -o -name .nx \\) -prune -o -name project.json -print"

-- parse one project.json: returns name, sorted targets (or nil on failure)
local function parse_project_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return
    vim.notify("nx.nvim: failed to read " .. path, vim.log.levels.ERROR)
  end
  local ok2, data = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not ok2 or type(data) ~= "table" or not data.name then
    vim.notify("nx.nvim: invalid project.json", vim.log.levels.ERROR)
  end
  local targets = {}
  for t in pairs(data.targets or {}) do table.insert(targets, t) end
  table.sort(targets)
  return data.name, targets
end

-- single pass: find every project.json, parse it, cache projects + targets together
local function scan_workspace(root)
  if _cache.root == root and _cache.projects then return _cache.projects end
  local paths = vim.fn.systemlist(string.format(find_cmd, vim.fn.shellescape(root)))
  local projects = {}
  for _, path in ipairs(paths) do
    local name, targets = parse_project_json(vim.trim(path))
    if name then
      table.insert(projects, name)
      _cache.targets[name] = targets
    end
  end
  table.sort(projects)
  _cache.root = root
  _cache.projects = projects
  return projects
end

local function scan_workspace_async(root, cb)
  if _cache.root == root and _cache.projects then cb(_cache.projects); return end
  local cmd = string.format(find_cmd, vim.fn.shellescape(root))
  vim.system({ "sh", "-c", cmd }, { text = true }, function(result)
    vim.schedule(function()
      local projects = {}
      if result.code == 0 then
        for _, path in ipairs(vim.split(result.stdout or "", "\n")) do
          local name, targets = parse_project_json(vim.trim(path))
          if name then
            table.insert(projects, name)
            _cache.targets[name] = targets
          end
        end
        table.sort(projects)
      end
      _cache.root = root
      _cache.projects = projects
      cb(projects)
    end)
  end)
end

local function get_projects()
  local root = get_workspace_root()
  if not root then return {} end
  return scan_workspace(root)
end

local function get_projects_async(cb)
  local root = get_workspace_root()
  if not root then cb({}); return end
  scan_workspace_async(root, cb)
end

local function get_targets_for_project(project)
  local root = get_workspace_root()
  if not root then return {} end
  scan_workspace(root)  -- no-op if already cached
  return _cache.targets[project] or {}
end

local function get_targets_for_project_async(project, cb)
  local root = get_workspace_root()
  if not root then cb({}); return end
  if _cache.root == root and _cache.targets[project] then cb(_cache.targets[project]); return end
  scan_workspace_async(root, function()
    cb(_cache.targets[project] or {})
  end)
end

function M.run(project, target, args)
  local root = get_workspace_root()
  if not root then
    vim.notify("nx.nvim: nx.json not found in any parent directory", vim.log.levels.ERROR)
    return
  end
  if not project then
    vim.notify("nx.nvim: project required", vim.log.levels.WARN)
    return
  end
  local nx = detect_nx_cmd(root)
  local cmd = target and (nx .. " run " .. project .. ":" .. target) or (nx .. " " .. project)
  if args and args ~= "" then cmd = cmd .. " " .. args end
  run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. cmd)
end

local spin_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local uv = vim.uv or vim.loop

local function open_float(title)
  local width  = math.min(60, math.floor(vim.o.columns * 0.6))
  local height = math.min(30, math.floor(vim.o.lines   * 0.6))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width, height = height,
    row       = math.floor((vim.o.lines   - height) / 2),
    col       = math.floor((vim.o.columns - width)  / 2),
    style     = "minimal", border = "rounded",
    title     = title, title_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap       = false
  return buf, win
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function create_picker(title, items, on_select)
  if vim.tbl_isempty(items) then return end
  local buf, win = open_float(" " .. title .. " ")

  local lines = {}
  for _, item in ipairs(items) do table.insert(lines, "  " .. item) end
  set_lines(buf, lines)

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })

  local map_opts = { noremap = true, silent = true, buffer = buf, nowait = true }
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local selected = items[row]
    if selected then close(); on_select(selected) end
  end, map_opts)
  vim.keymap.set("n", "q",     close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
end

local function create_tree_picker(projects, on_run)
  local buf, win = open_float(" NX ")

  local tree = {}
  for _, p in ipairs(projects) do
    table.insert(tree, { name = p, expanded = false, loading = false, targets = nil })
  end

  local line_map  = {}
  local spin_idx  = 1
  local spin_timer = nil

  local function build()
    local lines = {}
    line_map = {}
    for i, node in ipairs(tree) do
      local icon = node.expanded and "▾" or "▸"
      table.insert(lines, string.format("  %s %s", icon, node.name))
      line_map[#lines] = { proj = i }
      if node.expanded then
        if node.loading then
          table.insert(lines, "    " .. spin_frames[spin_idx] .. " loading…")
          line_map[#lines] = { proj = i, loading = true }
        elseif node.targets then
          if #node.targets == 0 then
            table.insert(lines, "    (no targets)")
            line_map[#lines] = { proj = i, empty = true }
          else
            for _, t in ipairs(node.targets) do
              table.insert(lines, "    › " .. t)
              line_map[#lines] = { proj = i, target = t }
            end
          end
        end
      end
    end
    return lines
  end

  -- byte offsets for multi-byte UTF-8 chars:
  --   project row  "  ▸ name"  : icon at [2,5), name at [6,∞)  (▸ = 3 bytes)
  --   target row   "    › name": bullet at [4,7), name at [8,∞) (› = 3 bytes)
  local function apply_hl()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for lnr, entry in pairs(line_map) do
      if entry.target then
        vim.api.nvim_buf_add_highlight(buf, ns, "NonText",    lnr - 1, 4, 7)
        vim.api.nvim_buf_add_highlight(buf, ns, "String",     lnr - 1, 8, -1)
      elseif entry.loading or entry.empty then
        vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnr - 1, 0, -1)
      else
        vim.api.nvim_buf_add_highlight(buf, ns, "Comment",  lnr - 1, 2, 5)
        vim.api.nvim_buf_add_highlight(buf, ns, "Special", lnr - 1, 6, -1)
      end
    end
  end

  local function render()
    set_lines(buf, build())
    apply_hl()
  end

  render()

  local function close()
    if spin_timer then spin_timer:stop(); spin_timer:close(); spin_timer = nil end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })

  local function stop_spinner()
    for _, node in ipairs(tree) do if node.loading then return end end
    if spin_timer then spin_timer:stop(); spin_timer:close(); spin_timer = nil end
  end

  local function start_spinner()
    if spin_timer then return end
    spin_timer = uv.new_timer()
    spin_timer:start(0, 80, vim.schedule_wrap(function()
      if not vim.api.nvim_win_is_valid(win) then
        spin_timer:stop(); spin_timer:close(); spin_timer = nil; return
      end
      spin_idx = (spin_idx % #spin_frames) + 1
      render()
    end))
  end

  local function toggle_project(node)
    if node.expanded then
      node.expanded = false
      render()
    else
      node.expanded = true
      if node.targets ~= nil then
        render()
      else
        node.loading = true
        render()
        start_spinner()
        get_targets_for_project_async(node.name, function(targets)
          node.targets = targets
          node.loading = false
          stop_spinner()
          render()
        end)
      end
    end
  end

  local map_opts = { noremap = true, silent = true, buffer = buf, nowait = true }

  vim.keymap.set("n", "<CR>", function()
    local entry = line_map[vim.api.nvim_win_get_cursor(win)[1]]
    if not entry or entry.loading or entry.empty then return end
    if entry.target then
      local name = tree[entry.proj].name
      close(); on_run(name, entry.target)
    else
      toggle_project(tree[entry.proj])
    end
  end, map_opts)

  vim.keymap.set("n", "<Space>", function()
    local entry = line_map[vim.api.nvim_win_get_cursor(win)[1]]
    if entry and not entry.target and not entry.loading and not entry.empty then
      toggle_project(tree[entry.proj])
    end
  end, map_opts)

  vim.keymap.set("n", "q",     close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
end

function M.pick_project_target()
  get_projects_async(function(projects)
    if vim.tbl_isempty(projects) then
      vim.notify("nx.nvim: no projects found", vim.log.levels.WARN)
      return
    end
    create_tree_picker(projects, M.run)
  end)
end

function M.pick_project()
  get_projects_async(function(projects)
    if vim.tbl_isempty(projects) then
      vim.notify("nx.nvim: no projects found", vim.log.levels.WARN)
      return
    end
    create_picker("NX Project", projects, function(project)
      M.run(project)
    end)
  end)
end

function M.run_affected(target)
  local root = get_workspace_root()
  if not root then
    vim.notify("nx.nvim: nx.json not found", vim.log.levels.ERROR)
    return
  end
  local nx = detect_nx_cmd(root)
  if not target then
    vim.ui.input({ prompt = "NX Affected Target: " }, function(t)
      if t and t ~= "" then
        run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. nx .. " affected --target=" .. t)
      end
    end)
    return
  end
  run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. nx .. " affected --target=" .. target)
end

function M.graph()
  local root = get_workspace_root()
  if not root then
    vim.notify("nx.nvim: nx.json not found", vim.log.levels.ERROR)
    return
  end
  run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. detect_nx_cmd(root) .. " graph")
end

function M.reset()
  local root = get_workspace_root()
  if not root then
    vim.notify("nx.nvim: nx.json not found", vim.log.levels.ERROR)
    return
  end
  run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. detect_nx_cmd(root) .. " reset")
end


function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  vim.api.nvim_create_user_command("NxRun", function(args)
    local parts = vim.split(args.args, "%s+", { trimempty = true })
    M.run(parts[1], parts[2], table.concat(vim.list_slice(parts, 3), " "))
  end, {
    nargs = "+",
    desc = "Run nx <project> <target> [args]",
    complete = function(arglead, cmdline, _)
      local parts = vim.split(cmdline, "%s+", { trimempty = true })
      if #parts <= 2 then
        return vim.tbl_filter(function(p) return p:find(arglead, 1, true) end, get_projects())
      elseif #parts == 3 then
        return vim.tbl_filter(function(t) return t:find(arglead, 1, true) end, get_targets_for_project(parts[2]))
      end
      return {}
    end,
  })

  vim.api.nvim_create_user_command("NxPick", function() M.pick_project_target() end,
    { desc = "Interactively pick nx project and target" })

  vim.api.nvim_create_user_command("NxAffected", function(args)
    M.run_affected(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Run nx affected --target=<target>" })

  vim.api.nvim_create_user_command("NxGraph", function() M.graph() end,
    { desc = "Open nx graph" })

  vim.api.nvim_create_user_command("NxReset", function() M.reset() end,
    { desc = "Run nx reset to clear the NX computation cache" })

  vim.api.nvim_create_user_command("NxRefresh", function()
    _cache.root = nil; _cache.projects = nil; _cache.targets = {}
    vim.notify("nx.nvim: cache cleared", vim.log.levels.INFO)
  end, { desc = "Clear nx.nvim project/target cache" })
end

return M
