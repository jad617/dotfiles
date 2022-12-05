vim.api.nvim_create_user_command(
  'Format',
  function ()
    vim.lsp.buf.formatting()
  end,
  {}
)

vim.api.nvim_create_user_command(
  'JsonFormat',
  '%!jq .',
  {}
)
