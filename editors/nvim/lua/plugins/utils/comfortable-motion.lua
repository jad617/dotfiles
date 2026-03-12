---------------------------------------------------------------------------
-- Smooth scroll (pure Lua, replaces yuttie/comfortable-motion.vim)
-- Keymaps: <C-o> scroll up, <C-p> scroll down (normal + insert)
---------------------------------------------------------------------------

local function smooth_scroll(lines)
  local timer     = vim.uv.new_timer()
  local remaining = math.abs(lines)
  local key       = lines > 0 and "j" or "k"

  timer:start(0, 16, vim.schedule_wrap(function()
    if remaining <= 0 then
      timer:stop()
      timer:close()
      return
    end
    vim.api.nvim_feedkeys(key, "n", false)
    remaining = remaining - 1
  end))
end

local opts = { noremap = true, silent = true }

vim.keymap.set("n", "<C-p>", function() smooth_scroll(10)  end, opts)
vim.keymap.set("n", "<C-o>", function() smooth_scroll(-10) end, opts)
vim.keymap.set("i", "<C-p>", function() vim.cmd("stopinsert") smooth_scroll(10)  end, opts)
vim.keymap.set("i", "<C-o>", function() vim.cmd("stopinsert") smooth_scroll(-10) end, opts)

return {}
