return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/cmp-nvim-lsp",
    { "antosha417/nvim-lsp-file-operations", config = true },
    { "folke/neodev.nvim", opts = {} },
  },
  config = function()
    -- import lspconfig plugin
    local lspconfig = require("lspconfig")

    -- import cmp-nvim-lsp plugin
    local cmp_nvim_lsp = require("cmp_nvim_lsp")

    local keymap = vim.keymap -- for conciseness

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        -- Buffer local mappings.
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        local opts = { buffer = ev.buf, silent = true }

        -- set keybinds
        -- opts.desc = "Show LSP references"
        -- keymap.set("n", "gR", "<cmd>Telescope lsp_references<CR>", opts) -- show definition, references

        -- opts.desc = "Go to declaration"
        -- keymap.set("n", "gD", vim.lsp.buf.declaration, opts) -- go to declaration

        -- opts.desc = "Show LSP definitions"
        -- keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts) -- show lsp definitions

        -- opts.desc = "Show LSP implementations"
        -- keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts) -- show lsp implementations

        -- opts.desc = "Show LSP definitions"
        -- keymap.set("n", "gd", function()
        --   Snacks.picker.lsp_definitions()
        -- end) -- show lsp definitions

        -- opts.desc = "Show LSP implementations"
        -- keymap.set("n", "gi", function()
        --   Snacks.picker.lsp_implementations()
        -- end) -- show lsp implementations

        -- opts.desc = "Show LSP type definitions"
        -- keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts) -- show lsp type definitions

        -- opts.desc = "Disable Diagnostic warnings"
        -- keymap.set("n", "<leader>di", "<cmd>lua vim.diagnostic.config({ virtual_text = false })<CR>", opts) -- show lsp implementations
        -- opts.desc = "Enable Diagnostic warnings"
        -- keymap.set("n", "<leader>de", "<cmd>lua vim.diagnostic.config({ virtual_text = true })<CR>", opts) -- show lsp implementations

        opts.desc = "See available code actions"
        keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts) -- see available code actions, in visual mode will apply to selection

        opts.desc = "Smart rename"
        keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts) -- smart rename

        opts.desc = "Show buffer diagnostics"
        keymap.set("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts) -- show  diagnostics for file

        opts.desc = "Show line diagnostics"
        keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts) -- show diagnostics for line

        opts.desc = "Go to previous diagnostic"
        keymap.set("n", "[d", vim.diagnostic.goto_prev, opts) -- jump to previous diagnostic in buffer

        opts.desc = "Go to next diagnostic"
        keymap.set("n", "]d", vim.diagnostic.goto_next, opts) -- jump to next diagnostic in buffer

        opts.desc = "Show documentation for what is under cursor"
        keymap.set("n", "K", vim.lsp.buf.hover, opts) -- show documentation for what is under cursor

        opts.desc = "Restart LSP"
        keymap.set("n", "<leader>rs", ":LspRestart<CR>", opts) -- mapping to restart lsp if necessary
      end,
    })

    -- used to enable autocompletion (assign to every lsp server config)
    local capabilities = cmp_nvim_lsp.default_capabilities()

    -- Change the Diagnostic symbols in the sign column (gutter)
    -- (not in youtube nvim video)
    local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    end

    -- Loop on M.lsp in vars.lua
    -- initialize all LSPs with their config
    local lsp = require("config.vars").lsp
    for lsp_name, lsp_config in pairs(lsp) do
      lspconfig[lsp_name].setup({
        capabilities = capabilities,
        settings = lsp_config.settings,
      })
    end
  end,
}
