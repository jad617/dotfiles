return {
  {
    "natecraddock/workspaces.nvim",
    dependencies = { "folke/snacks.nvim" },

    -- Plugin options for workspaces.nvim
    opts = {
      hooks = {
        -- After switching workspace, open Snacks file picker
        open = function()
          require("snacks").picker.files({ hidden = true })
        end,
      },
    },

    config = function(_, opts)
      ---------------------------------------------------------------------------
      -- Setup: workspaces.nvim
      ---------------------------------------------------------------------------
      local workspaces = require("workspaces")
      workspaces.setup(opts)

      ---------------------------------------------------------------------------
      -- Helpers: detect current Git repo name and root
      -- 1) Prefer remote 'origin' to extract {repo}; fallback to root dir name
      -- 2) Return nil,nil if we're not inside a Git repo
      ---------------------------------------------------------------------------
      local function get_git_repo_name_and_root()
        local trim = function(s)
          return (s:gsub("%s+$", ""))
        end
        local remote = trim(vim.fn.system("git remote get-url origin 2>/dev/null"))
        local root = trim(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"))
        if root == "" then
          return nil, nil
        end

        local name
        if remote ~= "" then
          -- Matches both ssh and https forms:
          --   git@github.com:org/repo.git
          --   https://github.com/org/repo.git
          name = remote:match("[:/](.-)%.git$")
          name = name and name:match("([^/]+)$") or nil
        end
        if not name or name == "" then
          name = root:match("([^/]+)$")
        end
        return name, root
      end

      ---------------------------------------------------------------------------
      -- Auto-add the current Git repo to Workspaces on startup (idempotent)
      -- Uses the Lua API (add(path, name)) instead of shelling commands.
      ---------------------------------------------------------------------------
      local function validate_and_add_workspace()
        local ok, ws = pcall(require, "workspaces")
        if not ok then
          vim.notify("workspaces.nvim not available", vim.log.levels.WARN)
          return
        end

        local name, root = get_git_repo_name_and_root()
        if not name or not root then
          return
        end

        -- Fast lookup for existing entries (by name or path)
        local by_name, by_path = {}, {}
        for _, item in ipairs(ws.get() or {}) do
          by_name[item.name] = true
          by_path[item.path] = true
        end
        if by_name[name] or by_path[root] then
          return
        end

        ws.add(root, name) -- note: path first, then name
        vim.notify(("Added workspace: %s → %s"):format(name, root), vim.log.levels.INFO)
      end

      -- Run once after startup (scheduled to avoid races with lazy-loading)
      local aug = vim.api.nvim_create_augroup("WorkspaceValidation", { clear = true })
      vim.api.nvim_create_autocmd("VimEnter", {
        group = aug,
        desc = "Auto-add current Git repo as a workspace if missing",
        callback = function()
          vim.schedule(validate_and_add_workspace)
        end,
      })

      ---------------------------------------------------------------------------
      -- :SnacksWorkspaces command
      -- Uses Snacks' lightweight `select()` picker.
      -- - Aligned two-column layout: "<name> │ <path>"
      -- - Temporarily tints list text green to mimic "green path" (select() does
      --   not support per-item spans). Colors are restored after closing.
      -- - Opens in Insert mode automatically for quick filtering.
      ---------------------------------------------------------------------------
      vim.api.nvim_create_user_command("SnacksWorkspaces", function()
        -- Ensure both plugins are available
        local ok_ws, ws = pcall(require, "workspaces")
        local ok_sel, select_mod = pcall(require, "snacks.picker.select")
        if not ok_ws or not ok_sel then
          vim.notify("Snacks/Workspaces not available", vim.log.levels.ERROR)
          return
        end

        local list = ws.get()
        if not list or #list == 0 then
          vim.notify("No workspaces found", vim.log.levels.WARN)
          return
        end

        -- Compute max display width for the name column (handles wide glyphs)
        local max_name = 0
        for _, it in ipairs(list) do
          local w = vim.fn.strdisplaywidth(it.name)
          if w > max_name then
            max_name = w
          end
        end

        -- Build rows with aligned columns
        local items = {}
        for _, it in ipairs(list) do
          local pad = max_name - vim.fn.strdisplaywidth(it.name)
          local left = it.name .. string.rep(" ", pad + 2) .. "│  "
          local line = left .. it.path
          items[#items + 1] = { text = line, value = it }
        end

        -- Temporarily tint list entries green (closest to “green path” in select())
        local OLD = vim.api.nvim_get_hl(0, { name = "SnacksPickerListText", link = true })
        vim.api.nvim_set_hl(0, "SnacksPickerListText", { fg = "#9ECE6A" }) -- tweak if desired

        local function restore_hl()
          if OLD and (OLD.link or OLD.fg or OLD.bg or OLD.bold or OLD.italic or OLD.underline) then
            vim.api.nvim_set_hl(0, "SnacksPickerListText", OLD.link and { link = OLD.link } or {
              fg = OLD.fg,
              bg = OLD.bg,
              bold = OLD.bold,
              italic = OLD.italic,
              underline = OLD.underline,
            })
          else
            vim.api.nvim_set_hl(0, "SnacksPickerListText", {})
          end
        end

        select_mod.select(items, {
          title = "Workspaces",
          layout = "ivy", -- try: "vertical", "dropdown", "vscode", "select"
          win = { width = 0.9, height = 0.6 },
          format_item = function(it)
            return it.text
          end,
        }, function(choice)
          restore_hl()

          if not choice or not choice.value then
            return
          end
          local it = choice.value
          if not vim.loop.fs_stat(it.path) then
            vim.notify("Workspace path missing: " .. it.path, vim.log.levels.ERROR)
            return
          end
          ws.open(it.name)
        end)

        -- Auto-focus in insert mode
        vim.cmd("startinsert")

        -- Also restore colors shortly after (covers cancel/esc paths)
        vim.defer_fn(restore_hl, 1000)
      end, {})

      -- Keymap shortcut
      vim.keymap.set("n", "<c-l>", "<cmd>SnacksWorkspaces<cr>", { desc = "Workspaces (Snacks)" })
    end,
  },
}
