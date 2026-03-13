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
  yamlls = {
    filetypes = { "yaml", "yaml.ansible" }, -- exclude helm (handled by helm_ls)
  },
  basedpyright = {},
  ruff = {},
  tflint = {
    filetypes = { "terraform" },
    pattern = { "*.tf" },
  }, -- terraform docs
  terraformls = {
    filetypes = { "terraform" },
    pattern = { "*.tf" },
    cmd = { "terraform-ls", "serve", "-log-file", "/dev/null" },
  }, -- terraform
  lua_ls = { -- lua
    settings = {
      -- Lua = {
      --   runtime = {
      --     -- Tell the server to use LuaJIT (the Lua runtime in Neovim)
      --     version = "LuaJIT",
      --     -- Setup your package.path
      --     path = vim.split(package.path, ";"),
      --   },
      --   diagnostics = {
      --     -- Recognize the `vim` global
      --     globals = { "vim", "wezterm" },
      --   },
      --   workspace = {
      --     -- Make the server aware of Neovim runtime files
      --     library = vim.api.nvim_get_runtime_file("", true),
      --     checkThirdParty = false, -- disable prompting about other lua libs
      --   },
      --   telemetry = { enable = false },
      -- },
      Lua = {
        runtime = {
          version = "LuaJIT", -- for Neovim
          path = vim.split(package.path, ";"),
        },
        diagnostics = {
          globals = { "vim", "wezterm" }, -- support both
        },
        workspace = {
          library = (function()
            local lib = vim.api.nvim_get_runtime_file("", true)
            -- Add wezterm-related dirs if they exist
            local uv = vim.uv or vim.loop
            local extra = {
              vim.fn.expand("~/.local/share/wezterm-types"),
              vim.fn.expand("~/.config/wezterm"),
            }
            for _, path in ipairs(extra) do
              if uv.fs_stat(path) then table.insert(lib, path) end
            end
            return lib
          end)(),
          checkThirdParty = false,
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
  "ruff",
  "shfmt",
  "ansible-lint",
  "golangci-lint",
  "proselint",
  "tflint",
  "stylua",
  "yamllint",
  "hadolint",
  "shellcheck",
}

return M
