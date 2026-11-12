return {
  {
    "iamcco/markdown-preview.nvim",
    enabled = true,
    build = function(plugin)
      -- NixOS can't run the prebuilt binary mkdp#util#install downloads (a
      -- generic dynamically linked Linux executable). Without it the plugin
      -- runs the same server with node (app/index.js), so install the app's
      -- node packages instead and drop any downloaded binary
      if vim.fn.filereadable("/etc/NIXOS") == 1 then
        local app = plugin.dir .. "/app"
        vim.fn.delete(app .. "/bin", "rf")
        -- yarn (through npx, nothing to install) with the plugin's yarn.lock:
        -- the exact versions the app is built for (npm resolves newer ones that
        -- miss msgpack-lite), and --frozen-lockfile leaves the checkout clean
        -- so Lazy can still update it
        local out = vim.fn.system({ "npx", "--yes", "yarn", "install", "--cwd", app,
          "--frozen-lockfile", "--production", "--non-interactive", "--silent" })
        if vim.v.shell_error ~= 0 then
          error("markdown-preview: yarn install failed:\n" .. out)
        end
        return
      end
      require("lazy").load({ plugins = { "markdown-preview.nvim" } })
      vim.fn["mkdp#util#install"]()
    end,
    ft = { "markdown" },
    init = function()
      vim.g.mkdp_auto_start = 0 -- manual only
      vim.g.mkdp_filetypes = { "markdown" }

      local function run_mkdp(autofunc)
        local ok_lazy, lazy = pcall(require, "lazy")
        if ok_lazy then
          lazy.load({ plugins = { "markdown-preview.nvim" } })
        end

        local fn = vim.fn[autofunc]
        if type(fn) ~= "function" then
          vim.notify("markdown-preview.nvim is not ready yet", vim.log.levels.ERROR)
          return
        end

        local ok, err = pcall(fn)
        if not ok then
          vim.notify("markdown-preview.nvim error: " .. tostring(err), vim.log.levels.ERROR)
        end
      end

      vim.api.nvim_create_user_command("MarkdownPreview", function()
        run_mkdp("mkdp#util#open_preview_page")
      end, {})
      vim.api.nvim_create_user_command("MarkdownPreviewStop", function()
        run_mkdp("mkdp#util#stop_preview")
      end, {})
      vim.api.nvim_create_user_command("MarkdownPreviewToggle", function()
        run_mkdp("mkdp#util#toggle_preview")
      end, {})

      local map = vim.api.nvim_set_keymap
      local options = { noremap = true, silent = true }

      map("n", "<A-m>", ":MarkdownPreviewToggle<CR>", options)
      map("n", "µ", ":MarkdownPreviewToggle<CR>", options)
    end,
  },
}
