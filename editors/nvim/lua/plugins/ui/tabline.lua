return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",

  opts = function(_, opts)
    local function three_layer_relpath(buf)
      local full = buf.path or buf.name or ""
      if full == "" then return "[No Name]" end

      local rel = vim.fn.fnamemodify(full, ":.")
      local parts = vim.split(rel, "/", { plain = true, trimempty = true })

      if #parts <= 3 then return table.concat(parts, "/") end
      return parts[#parts - 2] .. "/" .. parts[#parts - 1] .. "/" .. parts[#parts]
    end

    opts.options = opts.options or {}
    opts.options.mode = "tabs"
    opts.options.separator_style = "rounded"
    opts.options.show_buffer_close_icons = false
    opts.options.show_close_icon = false
    opts.options.diagnostics = false
    opts.options.truncate_names = false
    opts.options.name_formatter = function(buf) return " " .. three_layer_relpath(buf) .. " " end

    return opts
  end,

  config = function(_, opts)
    vim.opt.termguicolors = true
    vim.opt.showtabline = 2

    require("bufferline").setup(opts)

    local function force_pill()
      -- Selected tab = green pill
      vim.api.nvim_set_hl(0, "BufferLineTabSelected", {
        fg = "#1e1e1e",
        bg = "#99bc80",
        bold = true,
      })

      -- Everything else transparent
      vim.api.nvim_set_hl(0, "BufferLineFill", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "BufferLineBackground", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "BufferLineTab", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "BufferLineTabSeparator", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "BufferLineTabSeparatorSelected", { fg = "#99bc80", bg = "NONE" })
    end

    -- Apply now + after UI settles
    force_pill()
    vim.defer_fn(force_pill, 50)
    vim.defer_fn(force_pill, 200)

    -- Re-apply when theme changes (OneDark toggle triggers ColorScheme)
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        force_pill()
        vim.defer_fn(force_pill, 20)
      end,
    })

    -- Re-apply after LazyVim finishes loading plugins (common override point)
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        force_pill()
        vim.defer_fn(force_pill, 20)
      end,
    })
  end,
}
