return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",

  opts = function(_, opts)
    local tab_name_fg = "#98C379"

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
    opts.highlights = vim.tbl_deep_extend("force", opts.highlights or {}, {
      tab = { fg = tab_name_fg },
      tab_selected = { fg = tab_name_fg, bold = true },
      tab_separator = { fg = tab_name_fg },
      tab_separator_selected = { fg = tab_name_fg },
      tab_close = { fg = tab_name_fg },
      background = { fg = tab_name_fg },
      buffer = { fg = tab_name_fg },
      buffer_visible = { fg = tab_name_fg },
      buffer_selected = { fg = tab_name_fg, bold = true },
      numbers = { fg = tab_name_fg },
      numbers_visible = { fg = tab_name_fg },
      numbers_selected = { fg = tab_name_fg },
      close_button = { fg = tab_name_fg },
      close_button_visible = { fg = tab_name_fg },
      close_button_selected = { fg = tab_name_fg },
    })

    return opts
  end,

  config = function(_, opts)
    vim.opt.termguicolors = true
    vim.opt.showtabline = 2

    require("bufferline").setup(opts)
  end,
}
