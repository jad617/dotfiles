return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    local function two_layer_relpath(buf)
      -- Prefer full path if available
      local full = buf.path or buf.name or ""
      if full == "" then
        return "[No Name]"
      end

      -- Make it relative to cwd when possible
      local rel = vim.fn.fnamemodify(full, ":.")
      -- If still absolute (different drive/root), keep as-is but still truncate
      local parts = vim.split(rel, "/", { plain = true, trimempty = true })

      -- If it's just a filename or 1 dir + file, return it
      if #parts <= 2 then
        return table.concat(parts, "/")
      end

      -- Return last 2 path components (dir/file)
      return parts[#parts - 1] .. "/" .. parts[#parts]
    end

    require("bufferline").setup({
      options = {
        mode = "tabs",
        separator_style = "thin",
        show_buffer_close_icons = false,
        show_close_icon = false,
        diagnostics = false,

        -- 👇 show relative path (2 layers)
        name_formatter = function(buf)
          return two_layer_relpath(buf)
        end,
      },
    })

    local function fix_bufferline_bg()
      local groups = {
        "BufferLineFill",
        "BufferLineBackground",
        "BufferLineTab",
        "BufferLineTabSelected",
        "BufferLineTabSeparator",
        "BufferLineTabSeparatorSelected",
        "BufferLineSeparator",
        "BufferLineSeparatorSelected",
        "BufferLineOffsetSeparator",
      }

      for _, g in ipairs(groups) do
        vim.api.nvim_set_hl(0, g, { bg = "NONE" })
      end
    end

    fix_bufferline_bg()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = fix_bufferline_bg })
  end,
}
