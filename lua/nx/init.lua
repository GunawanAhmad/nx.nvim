local M = {}

local _cache = { root = nil, projects = nil, targets = {} }

local config = {
  nx_cmd = nil,       -- auto-detected if nil (pnpm/yarn/bun/npx/nx)
  terminal = "horizontal", -- "horizontal" | "vertical" | "float"
  float_opts = { width = 0.8, height = 0.8 },
}

-- resolve the nx-runner binary: explicit config > sibling to plugin > PATH
local function runner_bin()
  local src = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(src, ":h:h:h")
  local candidate = plugin_root .. "/go/nx-runner"
  if vim.fn.executable(candidate) == 1 then return candidate end
  if vim.fn.executable("nx-runner") == 1 then return "nx-runner" end
  return nil
end

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

-- use nx-runner binary for fast filesystem-based listing
local function get_projects()
  local root = get_workspace_root()
  if not root then return {} end

  if _cache.root == root and _cache.projects then return _cache.projects end

  local bin = runner_bin()
  local cmd
  if bin then
    cmd = "cd " .. vim.fn.shellescape(root) .. " && " .. bin .. " projects 2>/dev/null"
  else
    local nx = detect_nx_cmd(root)
    cmd = "cd " .. vim.fn.shellescape(root) .. " && " .. nx .. " show projects 2>/dev/null"
  end

  local raw = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then return {} end

  local projects = {}
  for _, line in ipairs(raw) do
    local t = vim.trim(line)
    if t ~= "" and not t:match("^>") then table.insert(projects, t) end
  end
  _cache.root = root
  _cache.projects = projects
  return projects
end

local function get_projects_async(cb)
  local root = get_workspace_root()
  if not root then cb({}); return end
  if _cache.root == root and _cache.projects then cb(_cache.projects); return end

  local bin = runner_bin()
  local cmd
  if bin then
    cmd = "cd " .. vim.fn.shellescape(root) .. " && " .. bin .. " projects 2>/dev/null"
  else
    local nx = detect_nx_cmd(root)
    cmd = "cd " .. vim.fn.shellescape(root) .. " && " .. nx .. " show projects 2>/dev/null"
  end

  vim.system({ "sh", "-c", cmd }, { text = true }, function(result)
    vim.schedule(function()
      local projects = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
          local t = vim.trim(line)
          if t ~= "" and not t:match("^>") then table.insert(projects, t) end
        end
      end
      _cache.root = root
      _cache.projects = projects
      cb(projects)
    end)
  end)
end

local function get_targets_for_project(project)
  local root = get_workspace_root()
  if not root then return {} end

  if _cache.root == root and _cache.targets[project] then return _cache.targets[project] end

  local targets = {}
  local bin = runner_bin()
  if bin then
    local raw = vim.fn.systemlist(
      "cd " .. vim.fn.shellescape(root) .. " && " .. bin .. " targets " .. vim.fn.shellescape(project) .. " 2>/dev/null"
    )
    if vim.v.shell_error ~= 0 then return {} end
    for _, line in ipairs(raw) do
      local t = vim.trim(line)
      if t ~= "" then table.insert(targets, t) end
    end
  else
    local nx = detect_nx_cmd(root)
    local result = vim.fn.systemlist(
      "cd " .. vim.fn.shellescape(root) .. " && " .. nx .. " show project " .. vim.fn.shellescape(project) .. " --json 2>/dev/null"
    )
    if vim.v.shell_error ~= 0 then return {} end

    local json_start = 0
    for i, line in ipairs(result) do
      if vim.trim(line):sub(1, 1) == "{" then json_start = i; break end
    end
    if json_start == 0 then return {} end

    local ok, data = pcall(vim.fn.json_decode, table.concat(result, "\n", json_start))
    if not ok or type(data) ~= "table" or not data.targets then return {} end

    for target in pairs(data.targets) do table.insert(targets, target) end
    table.sort(targets)
  end

  _cache.targets[project] = targets
  return targets
end

function M.run(project, target, args)
  local root = get_workspace_root()
  if not root then
    vim.notify("nx.nvim: nx.json not found in any parent directory", vim.log.levels.ERROR)
    return
  end

  local bin = runner_bin()
  local cmd
  if bin and project and target then
    cmd = bin .. " run " .. vim.fn.shellescape(project) .. " " .. vim.fn.shellescape(target)
    if args and args ~= "" then cmd = cmd .. " " .. args end
  else
    local nx = detect_nx_cmd(root)
    if project and target then
      cmd = nx .. " run " .. project .. ":" .. target
      if args and args ~= "" then cmd = cmd .. " " .. args end
    elseif project then
      cmd = nx .. " " .. project
    else
      vim.notify("nx.nvim: project required", vim.log.levels.WARN)
      return
    end
  end

  run_in_terminal("cd " .. vim.fn.shellescape(root) .. " && " .. cmd)
end

local function pick_with_telescope()
  local ok, pickers  = pcall(require, "telescope.pickers")
  if not ok then return false end
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local phase = "project"
  local chosen_project = nil

  local picker = pickers.new({}, {
    prompt_title = "NX Project",
    finder = finders.new_table({ results = {} }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end

        if phase == "project" then
          chosen_project = entry[1]
          local targets = get_targets_for_project(chosen_project)
          if vim.tbl_isempty(targets) then
            vim.notify("nx.nvim: no targets for " .. chosen_project, vim.log.levels.WARN)
            return
          end
          phase = "target"
          local p = action_state.get_current_picker(prompt_bufnr)
          p.prompt_title = "NX Target (" .. chosen_project .. ")"
          p:refresh(finders.new_table({ results = targets }), { reset_prompt = true })
        else
          actions.close(prompt_bufnr)
          M.run(chosen_project, entry[1])
        end
      end)
      return true
    end,
  })
  picker:find()

  get_projects_async(function(projects)
    if vim.tbl_isempty(projects) then
      vim.notify("nx.nvim: no projects found", vim.log.levels.WARN)
      return
    end
    picker:refresh(finders.new_table({ results = projects }), { reset_prompt = true })
  end)

  return true
end

function M.pick_project_target()
  if pick_with_telescope() then return end

  -- fallback: two-step vim.ui.select (blocking)
  local projects = get_projects()
  if vim.tbl_isempty(projects) then
    vim.notify("nx.nvim: no projects found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(projects, { prompt = "NX Project> " }, function(project)
    if not project then return end
    local targets = get_targets_for_project(project)
    if vim.tbl_isempty(targets) then
      vim.notify("nx.nvim: no targets for " .. project, vim.log.levels.WARN)
      return
    end
    vim.ui.select(targets, { prompt = "NX Target (" .. project .. ")> " }, function(target)
      if not target then return end
      M.run(project, target)
    end)
  end)
end

function M.pick_project()
  local projects = get_projects()
  if vim.tbl_isempty(projects) then
    vim.notify("nx.nvim: no projects found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(projects, { prompt = "NX Project> " }, function(project)
    if not project then return end
    M.run(project)
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

function M.build()
  local src = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(src, ":h:h:h")
  local go_dir = plugin_root .. "/go"
  local out = go_dir .. "/nx-runner"
  if vim.fn.executable("go") == 0 then
    vim.notify("nx.nvim: 'go' not found — cannot build nx-runner", vim.log.levels.ERROR)
    return
  end
  local result = vim.fn.system(
    "cd " .. vim.fn.shellescape(go_dir) .. " && go build -o " .. vim.fn.shellescape(out) .. " ."
  )
  if vim.v.shell_error ~= 0 then
    vim.notify("nx.nvim: build failed:\n" .. result, vim.log.levels.ERROR)
  else
    vim.notify("nx.nvim: nx-runner built at " .. out, vim.log.levels.INFO)
  end
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

  vim.api.nvim_create_user_command("NxRefresh", function()
    _cache.root = nil; _cache.projects = nil; _cache.targets = {}
    vim.notify("nx.nvim: cache cleared", vim.log.levels.INFO)
  end, { desc = "Clear nx.nvim project/target cache" })
end

return M
