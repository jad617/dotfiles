local M = {}

-- Configuration
M.config = {
  display_mode = "vsplit", -- "vsplit" or "float"
  width_ratio = 0.5,       -- vsplit width ratio (0-1)
  float_width_ratio = 0.85,  -- float width ratio (0-1)
  float_height_ratio = 0.85, -- float height ratio (0-1)
}

-- Cache for provider versions
local provider_cache = {}
local cache_dir = nil

local function find_provider_version()
  -- Use cached version if in same directory
  local cwd = vim.fn.getcwd()
  if cache_dir == cwd and next(provider_cache) then
    return provider_cache
  end
  
  cache_dir = cwd
  provider_cache = {}
  
  -- Search for terraform.tf or *.tf files with required_providers block
  local tf_files = vim.fn.glob(cwd .. "/**/*.tf", false, true)
  
  for _, file in ipairs(tf_files) do
    local f = io.open(file, "r")
    if f then
      local content = f:read("*a")
      f:close()
      
      -- Find required_providers block
      local providers_block = content:match("required_providers%s*{(.-)}")
      if providers_block then
        -- Parse each provider
        for provider, source, version in providers_block:gmatch('([%w_]+)%s*=%s*{[^}]*source%s*=%s*"([^"]+)"[^}]*version%s*=%s*"([^"]+)"') do
          provider_cache[provider] = {
            source = source,
            version = version
          }
        end
      end
    end
  end
  
  return provider_cache
end

local function extract_major_version(version_str)
  -- Extract major version from version constraints like "~> 5.40", "~> 5.24.0", ">= 1.8.2"
  if not version_str then return nil end
  local major = version_str:match("(%d+)")
  return major or nil
end

-- Parse a `resource "type"` or `data "type"` declaration on the current line.
-- Returns kind ("resource"|"data"), the full type, provider and name, or nil.
local function parse_block(line)
  local kind, block_type = "resource", line:match('resource%s*"([^"]+)"')
  if not block_type then
    kind, block_type = "data", line:match('^%s*data%s*"([^"]+)"')
  end
  if not block_type then
    vim.notify("Not on a terraform resource or data declaration", vim.log.levels.WARN)
    return nil
  end
  local provider, name = block_type:match("^([^_]+)_(.+)$")
  if not provider or not name then
    vim.notify("Could not parse resource type: " .. block_type, vim.log.levels.WARN)
    return nil
  end
  return kind, block_type, provider, name
end

local function get_provider_github_url(provider, resource, version_constraint, kind)
  -- Docs folders differ for data sources
  local docs_dir = kind == "data" and "data-sources" or "resources"
  local website_dir = kind == "data" and "d" or "r"
  -- Map provider names to their GitHub organization/repo names
  local provider_map = {
    aws = "hashicorp/terraform-provider-aws",
    kubernetes = "hashicorp/terraform-provider-kubernetes",
    cloudflare = "cloudflare/terraform-provider-cloudflare",
    azurerm = "hashicorp/terraform-provider-azurerm",
  }
  
  local repo = provider_map[provider]
  if not repo then
    -- Generic: assume hashicorp by default
    repo = string.format("hashicorp/terraform-provider-%s", provider)
  end
  
  local major = extract_major_version(version_constraint)
  
  -- Build URLs to try
  local urls = {}
  
  -- Try version-specific branch first
  if major then
    if provider == "cloudflare" then
      table.insert(urls, string.format(
        "https://raw.githubusercontent.com/%s/v%s.0/docs/%s/%s.md",
        repo, major, docs_dir, resource
      ))
    else
      table.insert(urls, string.format(
        "https://raw.githubusercontent.com/%s/release/v%s/docs/%s/%s.md",
        repo, major, docs_dir, resource
      ))
    end
  end
  
  -- Try main branch (cloudflare: then the legacy master branch, v4 docs)
  table.insert(urls, string.format(
    "https://raw.githubusercontent.com/%s/main/docs/%s/%s.md",
    repo, docs_dir, resource
  ))
  if provider == "cloudflare" then
    table.insert(urls, string.format(
      "https://raw.githubusercontent.com/%s/master/docs/%s/%s.md",
      repo, docs_dir, resource
    ))
  end
  
  -- Try AWS/Azure website docs
  if provider == "aws" or provider == "azurerm" then
    table.insert(urls, string.format(
      "https://raw.githubusercontent.com/%s/main/website/docs/%s/%s.html.markdown",
      repo, website_dir, resource
    ))
  end
  
  return urls
end

local function fetch_terraform_docs()
  -- e.g. "aws_ssm_parameter" -> provider="aws", resource="ssm_parameter"
  local kind, resource_type, provider, resource = parse_block(vim.api.nvim_get_current_line())
  if not kind then return end

  vim.notify("Fetching docs for " .. resource_type .. "...")

  -- Find provider version from terraform config
  local providers = find_provider_version()
  local version_constraint = providers[provider] and providers[provider].version or nil
  
  -- Get URLs to try based on provider version
  local urls = get_provider_github_url(provider, resource, version_constraint, kind)

  local found = false
  local current_url_index = 0

  local function try_url(url_index)
    if found or url_index > #urls then
      if not found and url_index > #urls then
        vim.notify("Documentation not found for " .. resource_type, vim.log.levels.WARN)
      end
      return
    end

    local url = urls[url_index]
    current_url_index = url_index
    
    -- vim.net.request uses `curl --fail`, so HTTP errors (404) arrive as `err`.
    vim.net.request(url, { retry = 1 }, function(err, res)
      vim.schedule(function()
        if found then return end
        local markdown = not err and res and res.body or ""
        if markdown ~= "" and not markdown:match("^%s*<") then
          found = true
          M.display_terraform_docs(markdown, resource_type)
        else
          try_url(url_index + 1)
        end
      end)
    end)
  end

  try_url(1)
end

function M.display_terraform_docs(markdown, resource_type)
  -- Add breathing room to markdown for better readability
  local lines = {}
  local prev_was_blank = false
  
  for line in markdown:gmatch("[^\n]+") do
    -- Add extra spacing before headings
    if line:match("^#") and #lines > 0 and not prev_was_blank then
      table.insert(lines, "")
    end
    
    -- Add extra spacing after code blocks
    if line:match("^```") then
      table.insert(lines, line)
      table.insert(lines, "")
      prev_was_blank = true
    else
      table.insert(lines, line)
      prev_was_blank = line:match("^%s*$") ~= nil
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "wrap", true)
  vim.api.nvim_buf_set_option(buf, "linebreak", true)

  local title = " " .. resource_type .. " Docs "

  if M.config.display_mode == "vsplit" then
    M.display_vsplit(buf, title)
  else
    M.display_float(buf, title)
  end

  -- Enable render-markdown for this buffer
  vim.schedule(function()
    vim.cmd("RenderMarkdown enable")
  end)

  -- Keymaps
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, noremap = true })
  vim.keymap.set("n", "<ESC>", "<cmd>close<cr>", { buffer = buf, noremap = true })
end

function M.display_vsplit(buf, title)
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf)

  -- Set buffer-local options
  vim.api.nvim_buf_set_option(buf, "bufhidden", "delete")
  vim.api.nvim_buf_set_option(buf, "buflisted", false)
end

function M.display_float(buf, title)
  local width = math.floor(vim.o.columns * M.config.float_width_ratio)
  local height = math.floor(vim.o.lines * M.config.float_height_ratio)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = title,
  })

  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
end

-- Setup command and keybinds
function M.setup()
  vim.api.nvim_create_user_command("TfDocs", fetch_terraform_docs, {})
  vim.api.nvim_create_user_command("TfDocsFloat", function()
    M.config.display_mode = "float"
    fetch_terraform_docs()
    M.config.display_mode = "vsplit"
  end, {})
  vim.api.nvim_create_user_command("TfDocsVsplit", function()
    M.config.display_mode = "vsplit"
    fetch_terraform_docs()
  end, {})
  vim.api.nvim_create_user_command("TfDocsOpen", function()
    local kind, resource_type, provider, resource = parse_block(vim.api.nvim_get_current_line())
    if not kind then return end
    local url = string.format(
      "https://registry.terraform.io/providers/%s/%s/latest/docs/%s/%s",
      provider == "cloudflare" and "cloudflare" or "hashicorp",
      provider,
      kind == "data" and "data-sources" or "resources",
      resource
    )
    os.execute(string.format("open '%s'", url))
    vim.notify("Opening in browser: " .. resource_type)
  end, {})
end

return M
