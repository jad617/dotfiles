---------------------------------------------------------------------------
-- Smooth scroll (pure Lua, replaces yuttie/comfortable-motion.vim)
-- Keymaps: <C-o> scroll up, <C-p> scroll down (normal + insert)
---------------------------------------------------------------------------

local function smooth_scroll(lines)
  local timer    = vim.uv.new_timer()
  local remaining = math.abs(lines)
  local dir      = lines > 0 and 1 or -1
  local interval = 16  -- ~60 fps

  timer:start(0, interval, vim.schedule_wrap(function()
    if remaining <= 0 then
      timer:stop()
      timer:close()
      return
    end
    vim.cmd("normal! " .. dir .. "\x05") -- <C-e> / <C-y>
    remaining = remaining - 1
  end))
end

local opts = { noremap = true, silent = true }

vim.keymap.set("n", "<C-p>", function() smooth_scroll(10)  end, opts)
vim.keymap.set("n", "<C-o>", function() smooth_scroll(-10) end, opts)
vim.keymap.set("i", "<C-p>", function() vim.cmd("stopinsert") smooth_scroll(10)  end, opts)
vim.keymap.set("i", "<C-o>", function() vim.cmd("stopinsert") smooth_scroll(-10) end, opts)

return {}
