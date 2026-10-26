---------------------------------------------------------------------------
-- DevOps highlight groups: the single place every DevOps* group is defined.
--
--   vim.g.devops = { ui = {
--     theme = "devops",   -- "devops" (built-in palette) | "auto" (follow the colorscheme)
--     highlights = { DevOpsId = { fg = "#ff0000" }, DevOpsChip = { link = "Visual" } },
--   } }
--
-- Groups are set with `default = true`, so a colorscheme that defines DevOps*
-- groups wins; entries in `ui.highlights` always win. Everything is re-applied
-- on :colorscheme. Diff colours are separate (render.lua diff themes, `T`).
---------------------------------------------------------------------------

local M = {}

-- Built-in palette (Tokyo Night / One Dark mix).
local devops = {
  DevOpsTitle          = { fg = "#99bc80", bold = true },
  DevOpsSection        = { fg = "#7aa2f7", bold = true },
  DevOpsSectionActive  = { fg = "#99bc80", bold = true },
  DevOpsSectionBar     = { fg = "#99bc80", bold = true },
  DevOpsGroup          = { fg = "#565f89", bold = true },
  DevOpsKey            = { fg = "#e0af68" },
  DevOpsDim            = { fg = "#565f89" },
  DevOpsId             = { fg = "#7dcfff", bold = true },
  DevOpsStatusTodo     = { fg = "#9aa5ce" },
  DevOpsStatusProgress = { fg = "#e0af68" },
  DevOpsStatusDone     = { fg = "#9ece6a" },
  DevOpsPrOpen         = { fg = "#9ece6a" },
  DevOpsPrDraft        = { fg = "#565f89" },
  DevOpsLabel          = { fg = "#7aa2f7" },
  DevOpsColumn         = { fg = "#bb9af7", bold = true },
  DevOpsColumnNew      = { fg = "#7dcfff", bold = true },
  DevOpsColumnTodo     = { fg = "#9aa5ce", bold = true },
  DevOpsColumnHold     = { fg = "#ff9e64", bold = true },
  DevOpsColumnProgress = { fg = "#e0af68", bold = true },
  DevOpsColumnReview   = { fg = "#bb9af7", bold = true },
  DevOpsColumnQa       = { fg = "#f7768e", bold = true },
  DevOpsColumnMonitor  = { fg = "#7aa2f7", bold = true },
  DevOpsColumnDone     = { fg = "#9ece6a", bold = true },
  DevOpsCount          = { fg = "#565f89" },
  DevOpsIcon           = { fg = "#7aa2f7" },
  DevOpsBorder         = { fg = "#3b4261" },
  DevOpsBorderActive   = { fg = "#99bc80" },
  DevOpsWinbar         = { fg = "#ff8050", bold = true },
  DevOpsBadge          = { fg = "#ff8050" },
  DevOpsCommentBorder  = { fg = "#7aa2f7" },
  DevOpsReplyBorder    = { fg = "#e0af68" },
  DevOpsReplyLabel     = { fg = "#e0af68", bold = true },
  DevOpsDetailTitle    = { fg = "#c0caf5", bold = true },
  DevOpsSectionHead    = { fg = "#7aa2f7", bold = true },
  DevOpsOk             = { fg = "#9ece6a" },
  DevOpsErr            = { fg = "#f7768e" },
  DevOpsWarn           = { fg = "#e0af68" },
  DevOpsPill           = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
  DevOpsAction         = { fg = "#f7768e" },
  DevOpsMdHeader       = { fg = "#7aa2f7", bold = true },
  DevOpsMdBold         = { bold = true },
  DevOpsMdItalic       = { italic = true },
  DevOpsMdCode         = { fg = "#9ece6a", bg = "#1f2335" },
  DevOpsMdCodeBlock    = { fg = "#9ece6a", bg = "#1f2335" },
  DevOpsMdListBullet   = { fg = "#e0af68", bold = true },
  DevOpsMdQuote        = { fg = "#787c99", italic = true },
  DevOpsThreadText     = { link = "Normal" },
  -- Input / picker / search floats.
  DevOpsInputNormal        = { fg = "#99bc80" },
  DevOpsInputBorder        = { fg = "#ff9e64" },
  DevOpsInputTitle         = { fg = "#c27fd7", bold = true },
  DevOpsInputPreviewBorder = { link = "Comment" },
  DevOpsMention            = { fg = "#e5c07b", bold = true },
  DevOpsPickerNormal       = { fg = "#e06c75", bg = "#242b38" },
  DevOpsPickerBorder       = { fg = "#ff9e64", bg = "#242b38" },
  DevOpsPickerTitle        = { fg = "#c27fd7", bg = "#242b38", bold = true },
  DevOpsPickerCursorLine   = { fg = "#282c34", bg = "#98C379", bold = true },
  DevOpsPickerDim          = { fg = "#565f89", bg = "#242b38" },
  DevOpsSearchBorder       = { fg = "#ff9e64" },
  DevOpsSearchTitle        = { fg = "#c27fd7", bold = true },
  DevOpsSearchNormal       = { bg = "#242b38" },
  -- Chips, pills and detail tabs.
  DevOpsChip           = { fg = "#a9b1d6", bg = "#2a3046" },
  DevOpsChipLabel      = { fg = "#7aa2f7", bg = "#232a3d" },
  DevOpsPillTodo       = { fg = "#1a1b26", bg = "#9aa5ce", bold = true },
  DevOpsPillProgress   = { fg = "#1a1b26", bg = "#e0af68", bold = true },
  DevOpsPillDone       = { fg = "#1a1b26", bg = "#9ece6a", bold = true },
  DevOpsPillMuted      = { fg = "#c0caf5", bg = "#3b4261", bold = true },
  DevOpsTabActive      = { fg = "#1a1b26", bg = "#99bc80", bold = true },
  DevOpsTabInactive    = { fg = "#9aa5ce", bg = "#2a3046" },
  DevOpsDiffBanner     = { fg = "#a9b1d6", bg = "#2a3046" },
  DevOpsDiffBannerHot  = { fg = "#e0af68", bg = "#3b3426" },
  DevOpsDiffBannerTag  = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
  -- Issue types and priorities.
  DevOpsTypeEpic       = { fg = "#bb9af7" },
  DevOpsTypeStory      = { fg = "#9ece6a" },
  DevOpsTypeTask       = { fg = "#7aa2f7" },
  DevOpsTypeBug        = { fg = "#f7768e" },
  DevOpsTypeSubtask    = { fg = "#7dcfff" },
  DevOpsPriorityHigh   = { fg = "#f7768e", bold = true },
  DevOpsPriorityMedium = { fg = "#e0af68" },
  DevOpsPriorityLow    = { fg = "#7aa2f7" },
}

-- "auto": link to standard groups so any colorscheme looks native. Specs that
-- are functions are derived from the live colorscheme (pills/tabs need a bg).
local function get(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and type(hl) == "table" and hl or {}
end
local function fg_of(name, fallback)
  local h = get(name)
  return h.fg or h.foreground or get(fallback or "Normal").fg
end
-- Text in Normal's background over `name`'s foreground (a filled pill).
local function pill(name)
  return function()
    return { fg = get("Normal").bg or (vim.o.background == "light" and 0xffffff or 0x1a1b26),
      bg = fg_of(name, "Normal"), bold = true }
  end
end

local auto = {
  DevOpsTitle = "Title", DevOpsSection = "Function", DevOpsSectionActive = "Title",
  DevOpsSectionBar = "Title", DevOpsGroup = "Comment", DevOpsKey = "Special",
  DevOpsDim = "Comment", DevOpsId = "Identifier", DevOpsStatusTodo = "Comment",
  DevOpsStatusProgress = "DiagnosticWarn", DevOpsStatusDone = "DiagnosticOk",
  DevOpsPrOpen = "DiagnosticOk", DevOpsPrDraft = "Comment", DevOpsLabel = "Constant",
  DevOpsColumn = "Statement", DevOpsColumnNew = "Identifier", DevOpsColumnTodo = "Comment",
  DevOpsColumnHold = "WarningMsg", DevOpsColumnProgress = "DiagnosticWarn",
  DevOpsColumnReview = "Statement", DevOpsColumnQa = "DiagnosticError",
  DevOpsColumnMonitor = "Function", DevOpsColumnDone = "DiagnosticOk",
  DevOpsCount = "Comment", DevOpsIcon = "Function", DevOpsBorder = "FloatBorder",
  DevOpsBorderActive = "Title", DevOpsWinbar = "Title", DevOpsBadge = "WarningMsg",
  DevOpsCommentBorder = "Function", DevOpsReplyBorder = "DiagnosticWarn",
  DevOpsReplyLabel = "DiagnosticWarn", DevOpsDetailTitle = "Title",
  DevOpsSectionHead = "Function", DevOpsOk = "DiagnosticOk", DevOpsErr = "DiagnosticError",
  DevOpsWarn = "DiagnosticWarn", DevOpsPill = "PmenuSel", DevOpsAction = "Statement",
  DevOpsMdHeader = "Title", DevOpsMdBold = { bold = true }, DevOpsMdItalic = { italic = true },
  DevOpsMdCode = "String", DevOpsMdCodeBlock = "String", DevOpsMdListBullet = "Special",
  DevOpsMdQuote = "Comment", DevOpsThreadText = "Normal",
  DevOpsInputNormal = "NormalFloat", DevOpsInputBorder = "FloatBorder",
  DevOpsInputTitle = "FloatTitle", DevOpsInputPreviewBorder = "Comment",
  DevOpsMention = "Special", DevOpsPickerNormal = "NormalFloat",
  DevOpsPickerBorder = "FloatBorder", DevOpsPickerTitle = "FloatTitle",
  DevOpsPickerCursorLine = "PmenuSel", DevOpsPickerDim = "Comment",
  DevOpsSearchBorder = "FloatBorder", DevOpsSearchTitle = "FloatTitle",
  DevOpsSearchNormal = "NormalFloat",
  DevOpsChip = "Pmenu", DevOpsChipLabel = "Pmenu",
  DevOpsPillTodo = pill("Comment"), DevOpsPillProgress = pill("DiagnosticWarn"),
  DevOpsPillDone = pill("DiagnosticOk"), DevOpsPillMuted = "PmenuSel",
  DevOpsTabActive = "TabLineSel", DevOpsTabInactive = "TabLine",
  DevOpsDiffBanner = "StatusLine", DevOpsDiffBannerHot = "StatusLine",
  DevOpsDiffBannerTag = pill("Function"),
  DevOpsTypeEpic = "Statement", DevOpsTypeStory = "String", DevOpsTypeTask = "Function",
  DevOpsTypeBug = "DiagnosticError", DevOpsTypeSubtask = "Identifier",
  DevOpsPriorityHigh = "DiagnosticError", DevOpsPriorityMedium = "DiagnosticWarn",
  DevOpsPriorityLow = "DiagnosticInfo",
}

M.palettes = { devops = devops, auto = auto }

local function ui_opts()
  local ok, config = pcall(require, "plugins.utils.devops.config")
  return ok and config.options and config.options.ui or {}
end

--- Resolve a palette to { group = hl-spec } (links/derived specs expanded).
function M.resolve(name)
  local palette = M.palettes[name] or devops
  local out = {}
  for group, spec in pairs(devops) do -- every group exists in every palette
    local s = palette[group]
    if s == nil then s = spec end
    if type(s) == "string" then s = { link = s } end
    if type(s) == "function" then s = s() end
    out[group] = s
  end
  return out
end

function M.apply()
  local opts = ui_opts()
  for group, spec in pairs(M.resolve(opts.theme or "devops")) do
    pcall(vim.api.nvim_set_hl, 0, group, vim.tbl_extend("force", spec, { default = true }))
  end
  for group, spec in pairs(opts.highlights or {}) do
    pcall(vim.api.nvim_set_hl, 0, group, spec)
  end
end

return M
