return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ft = { "markdown" },
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  config = function()
    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local cmd = vim.cmd -- cmd
    local map = vim.api.nvim_set_keymap -- set keys
    local options = { noremap = true }

    ------------------------------------------------------------
    -- [[ Config ]]
    ------------------------------------------------------------
    -- cmd([[let g:mkdp_browser = 'chrome']])

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    -- [[ Linux ]]
    map("n", "<A-m>", ":MarkdownPreview<CR>", options)

    -- [[ MacOs ]]
    map("n", "µ", ":MarkdownPreview<CR>", { noremap = true, desc = "Alt + m" })
  end,
}
