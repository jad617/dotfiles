M = {}

M.lsp = {
  -- bashls = {},
  ansiblels = {},
  dockerls = {},
  helm_ls = {
    -- settings = {
    --   ["helm-ls"] = {
    --     yamlls = {
    --       path = "yaml-language-server",
    --     },
    --   },
    -- },
  },
  -- yamlls = {},
  pyright = {},
  tflint = {
    filetypes = { "terraform" },
    pattern = { "*.tf" },
  }, -- terraform docs
  terraformls = {
    filetypes = { "terraform" },
    pattern = { "*.tf" },
  }, -- terraform
  lua_ls = { -- lua
    settings = {
      Lua = {
        runtime = {
          -- Tell the server to use LuaJIT (the Lua runtime in Neovim)
          version = "LuaJIT",
          -- Setup your package.path
          path = vim.split(package.path, ";"),
        },
        diagnostics = {
          -- Recognize the `vim` global
          globals = { "vim" },
        },
        workspace = {
          -- Make the server aware of Neovim runtime files
          library = vim.api.nvim_get_runtime_file("", true),
          checkThirdParty = false, -- disable prompting about other lua libs
        },
        telemetry = { enable = false },
      },
    },
    -- settings = {
    --   Lua = {
    --     diagnostics = {
    --       globals = { "vim" }, -- removes warning: 'Global vim is undefined'
    --     },
    --   },
    -- },
  },
  gopls = {
    settings = {
      gopls = {
        gofumpt = false,
        -- gofumpt = true,
        codelenses = {
          gc_details = false,
          generate = true,
          regenerate_cgo = true,
          run_govulncheck = true,
          test = true,
          tidy = true,
          upgrade_dependency = true,
          vendor = true,
        },
        hints = {
          assignVariableTypes = true,
          compositeLiteralFields = true,
          compositeLiteralTypes = true,
          constantValues = true,
          functionTypeParameters = true,
          parameterNames = true,
          rangeVariableTypes = true,
        },
        analyses = {
          fieldalignment = true,
          nilness = true,
          unusedparams = true,
          unusedwrite = true,
          useany = true,
        },
        usePlaceholders = true,
        completeUnimported = true,
        staticcheck = true,
        directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
        -- semanticTokens = true,
      },
    },
  },
}

M.linter = {
  "gofumpt",
  "goimports",
  "goimports-reviser",
  "markdownlint",
  "black",
  "isort",
  "shfmt",
  "ansible-lint",
  "golangci-lint",
  "pylint",
  "flake8",
  "tflint",
  "stylua",
  "yamllint",
}

return M
