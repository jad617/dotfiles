return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local lualine = require("lualine")
      local lazy_status = require("lazy.status") -- to configure lazy pending updates count

      local project_root = {
        function() return vim.fn.fnamemodify(vim.fn.getcwd(), ":t") end,
        icon = "",
        separator = "",
        color = { fg = "#ff8050" },
      }

      local python_venv = {
        function()
          -- 1. Prefer $VIRTUAL_ENV (venv activated in shell before nvim launched)
          local venv = vim.env.VIRTUAL_ENV
          if venv and venv ~= "" then return "(" .. vim.fn.fnamemodify(venv, ":t") .. ")" end
          -- 2. Fall back: look for .venv at the LSP root or cwd
          local clients = vim.lsp.get_clients({ bufnr = 0, name = "basedpyright" })
          local root = (clients[1] and clients[1].config.root_dir) or vim.fn.getcwd()
          if vim.fn.isdirectory(root .. "/.venv") == 1 then return "(.venv)" end
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

      -- Orange statusline when cursor is inside the snacks explorer.
      -- lualine's highlight groups are global, so we bypass it entirely
      -- for snacks windows and set vim.wo.statusline directly.
      vim.cmd("highlight ExplorerStatusLine guifg=#282c34 guibg=#c9622a gui=bold")
      vim.cmd("highlight ExplorerStatusLineNC guifg=#1e2127 guibg=#8f4520 gui=bold")

      local explorer_stl = table.concat({
        "%#ExplorerStatusLine#",
        "  󰙅 Explorer ",
        "%=",                   -- right-align the rest
        " %l/%L ",
      })

      vim.api.nvim_create_augroup("explorer_statusline", { clear = true })

      -- Explorer windows are floating (snacks uses floats even for split layouts).
      -- Check the window belongs to an active explorer picker instance.
      local function is_explorer_win(w)
        if not vim.api.nvim_win_is_valid(w) then return false end
        local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
        if not ft:match("^snacks_") then return false end
        local Snacks = rawget(_G, "Snacks")
        if not (Snacks and Snacks.picker) then return false end
        local ok, pickers = pcall(Snacks.picker.get, { source = "explorer" })
        if not ok or not pickers then return false end
        for _, picker in ipairs(pickers) do
          if picker.layout and picker.layout.wins then
            for _, win_obj in pairs(picker.layout.wins) do
              if win_obj.win == w then return true end
            end
          end
        end
        return false
      end

      vim.api.nvim_create_autocmd("WinEnter", {
        group = "explorer_statusline",
        callback = function()
          local cur = vim.api.nvim_get_current_win()
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if not is_explorer_win(w) then goto continue end
            if w == cur then
              vim.wo[w].statusline = explorer_stl
            else
              if vim.wo[w].statusline == explorer_stl then
                vim.wo[w].statusline = ""
              end
            end
            ::continue::
          end
        end,
      })

      vim.api.nvim_create_autocmd("WinLeave", {
        group = "explorer_statusline",
        callback = function()
          local cur = vim.api.nvim_get_current_win()
          if is_explorer_win(cur) and vim.wo[cur].statusline == explorer_stl then
            vim.wo[cur].statusline = ""
          end
        end,
      })
    end,
  },
}
