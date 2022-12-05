-- [[ local vars ]]
local cmd = vim.cmd                 -- cmd

-- [[ Config ]]
cmd [[  let g:better_whitespace_enabled=1]]                -- Show whitespace --> Shows white spaces as red blocks
cmd [[  let g:strip_whitespace_on_save=1]]                 -- Automatically deletes white spaces when you save
cmd [[  let g:strip_whitespace_confirm=0]]                 -- Do not confirm, delete white spaces automatically
cmd [[  let g:strip_whitelines_at_eof=1]]                  -- Removes whitelines at the end of your file when you save
cmd [[  let g:better_whitespace_skip_empty_lines=1]]       -- Do not consider empty lines between code as whitespace
cmd [[  let g:strip_max_file_size = 99999]]                -- Allow big files to be handled by the plugin
