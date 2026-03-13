------------------------------------------------------------
-- Python: auto .venv creation + requirements install
--
-- On the first Python file opened per project root:
--   1. Detect root: walk up from the file looking for requirements*.txt
--      (use that level); if none found, fall back to git repo root;
--      if not in a git repo, fall back to cwd
--   2. Create .venv with `uv venv` (falls back to python3 -m venv)
--   3. Run `uv pip install -r` on every requirements*.txt found at root
--      (falls back to pip inside the venv)
--
-- Progress is shown via Snacks.notifier spinner (updates in-place).
--
-- Pyright root_dir override:
--   Always use the git repo root so sibling packages (e.g.
--   applications/shared/) are visible. The active venv is picked up
--   via $VIRTUAL_ENV (set by _auto_venv in zshrc).
------------------------------------------------------------

-- Ruff doesn't provide go-to-definition or hover; disable those capabilities
-- so basedpyright handles them exclusively and gd/K work correctly.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("RuffCapabilities", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= "ruff" then return end
    client.server_capabilities.definitionProvider = false
    client.server_capabilities.hoverProvider = false
  end,
})

-- Pyright inherits Neovim's process environment when it spawns.
-- BufReadPre fires before FileType (which triggers basedpyright start), so we
-- can inject VIRTUAL_ENV + PYTHONPATH into vim.env in time.
-- If basedpyright is already running (different project), restart it.
local _last_venv = nil

vim.api.nvim_create_autocmd("BufReadPre", {
  group = vim.api.nvim_create_augroup("PyrightEnv", { clear = true }),
  pattern = "*.py",
  callback = function(ev)
    local file_dir = vim.fn.fnamemodify(ev.file, ":h")

    -- Walk up to find nearest .venv
    local venv
    local dir = file_dir
    while dir ~= "/" do
      if vim.fn.isdirectory(dir .. "/.venv") == 1 then
        venv = dir .. "/.venv"
        break
      end
      local parent = vim.fn.fnamemodify(dir, ":h")
      if parent == dir then break end
      dir = parent
    end
    if not venv or venv == _last_venv then return end
    _last_venv = venv

    -- Git root for PYTHONPATH (resolves sibling packages)
    local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(file_dir) .. " rev-parse --show-toplevel")[1]

    vim.env.VIRTUAL_ENV = venv
    vim.env.PATH = venv .. "/bin:" .. vim.env.PATH
    if vim.v.shell_error == 0 and git_root ~= "" then vim.env.PYTHONPATH = git_root end

    -- Restart basedpyright if already running so it picks up the new env
    vim.schedule(function()
      for _, client in ipairs(vim.lsp.get_clients({ name = "basedpyright" })) do
        vim.lsp.stop_client(client.id, true)
      end
    end)
  end,
})

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Start a spinner notification that updates in-place.
-- Returns a stop() function that resolves the notification.
local function start_spinner(id, msg)
  local idx = 1
  local timer = vim.uv.new_timer()
  timer:start(
    0,
    120,
    vim.schedule_wrap(function()
      vim.notify(SPINNER[idx] .. " " .. msg, vim.log.levels.INFO, {
        id = id,
        title = "Python",
        timeout = false,
      })
      idx = (idx % #SPINNER) + 1
    end)
  )

  return function(ok, done_msg)
    timer:stop()
    timer:close()
    local level = ok and vim.log.levels.INFO or vim.log.levels.ERROR
    local icon = ok and "✓" or "✗"
    vim.schedule(
      function()
        vim.notify(icon .. " " .. done_msg, level, {
          id = id,
          title = "Python",
          timeout = ok and 3000 or 8000,
        })
      end
    )
  end
end

local function find_root(bufnr)
  local file_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")

  -- 1. Walk up looking for the nearest requirements*.txt
  local path = file_dir
  while path and path ~= "/" do
    if #vim.fn.glob(path .. "/requirements*.txt", false, true) > 0 then return path end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then break end
    path = parent
  end

  -- 2. No requirements.txt found — fall back to git root
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(file_dir) .. " rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then return git_root end

  -- 3. Not a git repo either — use cwd
  return vim.fn.getcwd()
end

local function install_reqs(root, venv, has_uv)
  local reqs = vim.fn.glob(root .. "/requirements*.txt", false, true)
  if #reqs == 0 then return end

  local pending = #reqs
  local all_ok = true

  for _, req in ipairs(reqs) do
    local name = vim.fn.fnamemodify(req, ":t")
    local id = "python_install_" .. root .. "_" .. name
    local stop = start_spinner(id, "Installing " .. name .. "…")

    local cmd = has_uv and { "uv", "pip", "install", "--python", venv .. "/bin/python", "-r", req } or { venv .. "/bin/pip", "install", "-r", req }

    vim.fn.jobstart(cmd, {
      cwd = root,
      on_exit = function(_, code)
        local ok = code == 0
        if not ok then all_ok = false end
        stop(ok, ok and (name .. " installed") or (name .. " install failed"))
        pending = pending - 1
        if pending == 0 then
          if not all_ok then
            vim.schedule(
              function()
                vim.notify("One or more requirements failed — check notifications above", vim.log.levels.WARN, {
                  title = "Python",
                  timeout = 8000,
                })
              end
            )
          else
            -- Restart LSP so it picks up the newly installed packages
            vim.schedule(function()
              for _, client in ipairs(vim.lsp.get_clients({ name = "basedpyright" })) do
                vim.lsp.stop_client(client.id, true)
              end
            end)
          end
        end
      end,
    })
  end
end

-- Guard: only run setup once per project root per session
local _done = {}

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("PythonVenv", { clear = true }),
  pattern = "python",
  callback = function(ev)
    local root = find_root(ev.buf)
    if _done[root] then return end
    _done[root] = true

    local venv = root .. "/.venv"
    local has_uv = vim.fn.exepath("uv") ~= ""

    if vim.fn.isdirectory(venv) == 0 then
      local id = "python_venv_" .. root
      local stop = start_spinner(id, "Creating .venv…")
      local cmd = has_uv and { "uv", "venv", venv } or { "python3", "-m", "venv", venv }

      vim.fn.jobstart(cmd, {
        cwd = root,
        on_exit = function(_, code)
          if code ~= 0 then
            stop(false, ".venv creation failed")
            return
          end
          stop(true, ".venv created")
          install_reqs(root, venv, has_uv)
        end,
      })
    else
      install_reqs(root, venv, has_uv)
    end
  end,
})

return {}
