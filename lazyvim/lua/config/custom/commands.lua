------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local linters = require("config.custom.vars").linter
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

------------------------------------------------------------
-- [[ MasonLinterInstall ]]
------------------------------------------------------------
local linter_list = {}

-- Add linters.formatting to linter_list
for _, linter in ipairs(linters.formatting) do
  table.insert(linter_list, linter)
end

-- Add linters.diagnostics to linter_list
for _, linter in ipairs(linters.diagnostics) do
  -- Loop inside linter_list
  for index, value in ipairs(linter_list) do
    -- If linter.diagnostics has the same value as linter_list
    -- remove this value
    if linter == value then
      table.remove(linter_list, index)
    end
  end
  table.insert(linter_list, linter)
end

local list_to_install = table.concat(linter_list, " ")
local mansonLinterInstall = "MasonInstall " .. list_to_install

vim.api.nvim_create_user_command("MasonLinterInstall", mansonLinterInstall, {})
