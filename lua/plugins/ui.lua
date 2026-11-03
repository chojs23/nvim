-- ==============================================================================
-- base16-nvim
-- ==============================================================================

local group = vim.api.nvim_create_augroup("colorscheme", { clear = true })

local function apply_overrides()
  -- Preserve text colors while letting the terminal background show through.
  for _, name in ipairs({
    "Normal",
    "NormalNC",
    "NormalFloat",
    "FloatBorder",
    "SignColumn",
    "LineNr",
    "CursorLineNr",
    "EndOfBuffer",
  }) do
    local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
    highlight.bg = nil
    highlight.ctermbg = nil
    vim.api.nvim_set_hl(0, name, highlight)
  end

  vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#7d8299", bg = "#262626" })
  vim.api.nvim_set_hl(0, "SnacksPickerGitStatusModified", { fg = "#FF8800" })
  vim.api.nvim_set_hl(0, "SnacksPickerGitStatusUntracked", { fg = "#6BB8FF" })

  -- nvim-tree git status: same palette as the Snacks picker groups above
  local nvim_tree_git = {
    Dirty = "#FF8800",
    New = "#6BB8FF",
  }
  for status, color in pairs(nvim_tree_git) do
    vim.api.nvim_set_hl(0, "NvimTreeGit" .. status .. "Icon", { fg = color })
    vim.api.nvim_set_hl(0, "NvimTreeGitFile" .. status .. "HL", { fg = color })
    vim.api.nvim_set_hl(0, "NvimTreeGitFolder" .. status .. "HL", { fg = color })
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = apply_overrides,
})

vim.cmd.colorscheme("base16-da-one-black")
apply_overrides()

-- ==============================================================================
-- noice.nvim
-- ==============================================================================

require("noice").setup({
  cmdline = {
    enabled = true,
    view = "cmdline",
  },
  lsp = {
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
      ["vim.lsp.util.stylize_markdown"] = true,
    },
    hover = {
      silent = false,
    },
    signature = {
      auto_open = {
        enabled = false,
      },
    },
  },
  messages = {
    enabled = true,
    view = "notify",
    view_error = "notify",
    view_warn = "notify",
    view_history = "messages",
    view_search = "virtualtext",
  },
  routes = {
    {
      filter = {
        event = "msg_show",
        any = {
          { find = "%d+L, %d+B" },
          { find = "; after #%d+" },
          { find = "; before #%d+" },
        },
      },
      view = "mini",
    },
  },
  presets = {
    bottom_search = true,
    command_palette = false,
    long_message_to_split = true,
    inc_rename = false,
    lsp_doc_border = true,
  },
  views = {
    notify = {
      replace = true,
    },
    mini = {
      position = {
        row = -1,
        col = 0,
      },
    },
  },
})

vim.keymap.set("c", "<S-Enter>", function()
  require("noice").redirect(vim.fn.getcmdline())
end, { desc = "Redirect Cmdline" })

vim.keymap.set("n", "<leader>snl", function()
  require("noice").cmd("last")
end, { desc = "Noice last message" })

vim.keymap.set("n", "<leader>snh", function()
  require("noice").cmd("history")
end, { desc = "Noice history" })

vim.keymap.set("n", "<leader>sna", function()
  require("noice").cmd("all")
end, { desc = "Noice all messages" })

vim.keymap.set("n", "<leader>snd", function()
  require("noice").cmd("dismiss")
end, { desc = "Dismiss all messages" })

vim.keymap.set("n", "<leader>snt", function()
  require("noice").cmd("pick")
end, { desc = "Noice history picker" })

vim.keymap.set({ "i", "n", "s" }, "<C-f>", function()
  if not require("noice.lsp").scroll(4) then
    return "<C-f>"
  end
end, { silent = true, expr = true, desc = "Scroll forward" })

vim.keymap.set({ "i", "n", "s" }, "<C-b>", function()
  if not require("noice.lsp").scroll(-4) then
    return "<C-b>"
  end
end, { silent = true, expr = true, desc = "Scroll backward" })

-- ==============================================================================
-- lualine.nvim
-- ==============================================================================

local colors = {
  green = "#98be65",
  orange = "#FF8800",
  white = "#ffffff",
}

local noice_status = require("noice").api.status

local function active_lsp()
  local filetype = vim.bo.filetype
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name ~= "copilot" then
      local filetypes = client.config.filetypes
      if not filetypes or vim.tbl_contains(filetypes, filetype) then
        return client.name
      end
    end
  end
  return "LSP: x"
end

local function active_formatters()
  local formatters, use_lsp = require("conform").list_formatters_to_run(0)
  local names = vim.tbl_map(function(formatter)
    return formatter.name
  end, formatters)

  if use_lsp then
    table.insert(names, "LSP")
  end

  return #names > 0 and table.concat(names, ", ") or "FMT: x"
end

require("lualine").setup({
  options = {
    theme = "auto",
    globalstatus = true,
    disabled_filetypes = {
      statusline = { "dashboard", "ministarter" },
    },
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch" },
    lualine_c = {
      {
        "diagnostics",
        symbols = { error = " ", warn = " ", info = " ", hint = " " },
      },
      { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
      { "filename", path = 1 },
    },
    lualine_x = {
      {
        noice_status.command.get,
        cond = noice_status.command.has,
        color = { fg = colors.orange },
      },
      {
        noice_status.mode.get,
        cond = noice_status.mode.has,
        color = { fg = colors.orange },
      },
      { active_lsp, color = { fg = colors.white, gui = "bold" } },
      { active_formatters, color = { fg = colors.white, gui = "bold" } },
      {
        "encoding",
        fmt = string.upper,
        cond = function()
          return vim.fn.winwidth(0) > 80
        end,
        color = { fg = colors.green, gui = "bold" },
      },
      {
        "fileformat",
        fmt = string.upper,
        icons_enabled = false,
        color = { fg = colors.green, gui = "bold" },
      },
    },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
})
