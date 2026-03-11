-- Global
local M = {}

function M.FileNotTooBig()
  local fsize = vim.fn.getfsize(vim.fn.expand("%:p:f"))
  return fsize <= 1000000 -- Adjust the threshold as needed
  -- return fsize <= 0.1 -- Adjust the threshold as needed
end

return M
