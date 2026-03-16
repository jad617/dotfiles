return {
  {
    "iamcco/markdown-preview.nvim",
    build = "cd app && npm install",
    ft = { "markdown" },
    init = function()
      vim.g.mkdp_auto_start = 0 -- manual only
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_browserfunc = "" -- open fresh tab each time (avoids 404 on refresh/back)

      local function run_mkdp(autofunc)
        local ok_lazy, lazy = pcall(require, "lazy")
        if ok_lazy then lazy.load({ plugins = { "markdown-preview.nvim" } }) end

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
