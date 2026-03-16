return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",

  opts = function(_, opts)
    local tab_name_fg = "#98C379"
    local fallback_normal_bg = "#282c34"
    local fallback_fill_bg = "#242b38"

    local function get_normal_bg_hex()
      local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
      if not ok or type(normal) ~= "table" or type(normal.bg) ~= "number" then return fallback_normal_bg end
      return string.format("#%06x", normal.bg)
    end

    local function darken_hex(hex, ratio)
      local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
      if not r then return fallback_fill_bg end

      local function darken_channel(channel_hex)
        local channel = tonumber(channel_hex, 16)
        return math.max(0, math.floor(channel * (1 - ratio) + 0.5))
      end

      return string.format("#%02x%02x%02x", darken_channel(r), darken_channel(g), darken_channel(b))
    end

    local tabline_fill_bg = darken_hex(get_normal_bg_hex(), 0.08)

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
      fill = { bg = tabline_fill_bg },
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
