return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local lualine = require("lualine")
      local lazy_status = require("lazy.status") -- to configure lazy pending updates count

      local project_root = {
        function()
          return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
        end,
        icon = "",
        separator = "",
        color = { fg = "#ff8050" },
      }

      local python_venv = {
        function()
          -- 1. Prefer $VIRTUAL_ENV (venv activated in shell before nvim launched)
          local venv = vim.env.VIRTUAL_ENV
          if venv and venv ~= "" then
            return "(" .. vim.fn.fnamemodify(venv, ":t") .. ")"
          end
          -- 2. Fall back: look for .venv at the LSP root or cwd
          local clients = vim.lsp.get_clients({ bufnr = 0, name = "basedpyright" })
          local root = (clients[1] and clients[1].config.root_dir) or vim.fn.getcwd()
          if vim.fn.isdirectory(root .. "/.venv") == 1 then
            return "(.venv)"
          end
          return ""
        end,
        cond = function() return vim.bo.filetype == "python" end,
        icon = "",
        color = { fg = "#E5C07B" },
      }

      -- configure lualine with modified theme
      lualine.setup({
        options = {
          -- theme = my_lualine_theme,
          theme = "onedark",
        },
        sections = {
          lualine_c = {
            project_root,
            {
              "filename",
              file_status = true,
              newfile_status = true,
              path = 1,
              color = { fg = "#99bc80" },
            },
          },
          lualine_x = {
            {
              lazy_status.updates,
              cond = lazy_status.has_updates,
              color = { fg = "#ff9e64" },
            },
            { "encoding" },
            { "fileformat" },
            python_venv,
            { "filetype" },
          },
        },
      })
    end,
  },
}
