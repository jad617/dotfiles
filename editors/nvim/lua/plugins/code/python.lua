------------------------------------------------------------
-- Python: auto .venv creation + requirements install
--
-- On the first Python file opened per project root:
--   1. Detect project root (requirements*.txt / pyproject.toml / setup.py / .git)
--   2. Create .venv with `uv venv` (falls back to python3 -m venv)
--   3. Run `uv pip install -r` on every requirements*.txt found
--      (falls back to pip inside the venv)
------------------------------------------------------------

local function find_root(bufnr)
  local markers = { "requirements.txt", "pyproject.toml", "setup.py", "setup.cfg", ".git" }
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")
  while path and path ~= "/" do
    for _, m in ipairs(markers) do
      local full = path .. "/" .. m
      if vim.fn.filereadable(full) == 1 or vim.fn.isdirectory(full) == 1 then
        return path
      end
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
  return vim.fn.getcwd()
end

local function install_reqs(root, venv, has_uv)
  local reqs = vim.fn.glob(root .. "/requirements*.txt", false, true)
  if #reqs == 0 then
    return
  end
  for _, req in ipairs(reqs) do
    local name = vim.fn.fnamemodify(req, ":t")
    local cmd = has_uv
        and { "uv", "pip", "install", "--python", venv .. "/bin/python", "-r", req }
      or { venv .. "/bin/pip", "install", "-r", req }
    vim.fn.jobstart(cmd, {
      cwd = root,
      on_exit = function(_, code)
        if code == 0 then
          vim.notify("[python] installed " .. name, vim.log.levels.INFO)
        else
          vim.notify("[python] failed to install " .. name, vim.log.levels.WARN)
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
    if _done[root] then
      return
    end
    _done[root] = true

    local venv = root .. "/.venv"
    local has_uv = vim.fn.exepath("uv") ~= ""

    if vim.fn.isdirectory(venv) == 0 then
      local cmd = has_uv and { "uv", "venv", venv } or { "python3", "-m", "venv", venv }
      vim.notify("[python] creating .venv in " .. root, vim.log.levels.INFO)
      vim.fn.jobstart(cmd, {
        cwd = root,
        on_exit = function(_, code)
          if code ~= 0 then
            vim.notify("[python] .venv creation failed", vim.log.levels.ERROR)
            return
          end
          install_reqs(root, venv, has_uv)
        end,
      })
    else
      install_reqs(root, venv, has_uv)
    end
  end,
})

-- No plugin needed — this file is pure autocmd config.
-- Return an empty table so lazy.nvim doesn't error when it sources this file.
return {}
