-- ==============================================================================
-- nvim-treesitter and nvim-treesitter-context
-- ==============================================================================

local M = {}

M.languages = {
  "bash",
  "dockerfile",
  "go",
  "gomod",
  "gosum",
  "gowork",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "regex",
  "tsx",
  "typescript",
  "vim",
  "yaml",
}

local treesitter = require("nvim-treesitter")

local function missing_languages()
  local installed = {}
  for _, language in ipairs(treesitter.get_installed()) do
    installed[language] = true
  end

  return vim.tbl_filter(function(language)
    return not installed[language]
  end, M.languages)
end

function M.install_missing()
  local missing = missing_languages()
  if #missing == 0 then
    return nil
  end

  return treesitter.install(missing, { summary = true })
end

M.install_task = M.install_missing()

-- Sticky header showing the current function/scope at the top of the window.
require("treesitter-context").setup({
  mode = "cursor",
  max_lines = 3,
})

vim.keymap.set("n", "<leader>ut", "<cmd>TSContext toggle<cr>", { desc = "Toggle treesitter context" })

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("treesitter", { clear = true }),
  callback = function(event)
    local filetype = vim.bo[event.buf].filetype
    local language = vim.treesitter.language.get_lang(filetype) or filetype
    if not vim.treesitter.language.add(language) then
      return
    end

    if not pcall(vim.treesitter.start, event.buf, language) then
      return
    end

    for _, window in ipairs(vim.fn.win_findbuf(event.buf)) do
      vim.wo[window].foldmethod = "expr"
      vim.wo[window].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    end
  end,
})

-- ==============================================================================
-- aerial.nvim
-- ==============================================================================

require("aerial").setup({
  attach_mode = "global",
  backends = { "lsp", "treesitter", "markdown", "man" },
  layout = {
    resize_to_content = false,
  },
  show_guides = true,
})

vim.keymap.set("n", "<leader>cs", "<cmd>AerialToggle<cr>", { desc = "Aerial symbols" })

-- ==============================================================================
-- mason.nvim
-- ==============================================================================

require("mason").setup({
  ui = {
    border = "rounded",
  },
})

-- ==============================================================================
-- blink.cmp
-- ==============================================================================

-- Loading the module itself is cheap, so the LSP setup below can get capabilities eagerly.
vim.schedule(function()
  require("blink.cmp").setup({
    keymap = { preset = "enter" },
    completion = {
      menu = {
        border = "rounded",
        -- winhighlight = "Normal:Normal,FloatBorder:Normal,CursorLine:BlinkCmpMenuSelection,Search:None",
        draw = {
          -- Highlight completion labels with treesitter, like code.
          treesitter = { "lsp" },
        },
      },
      documentation = {
        auto_show = true,
        window = {
          border = "rounded",
          -- winhighlight = "Normal:Normal,FloatBorder:Normal,CursorLine:Visual,Search:None",
        },
      },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
    },
    -- Falls back to the Lua matcher if the prebuilt Rust binary is unavailable.
    fuzzy = { implementation = "prefer_rust_with_warning" },
    signature = {
      enabled = true,
      window = {
        border = "rounded",
        -- winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    },
  })
end)

-- ==============================================================================
-- copilot.lua
-- ==============================================================================

-- Start Copilot only once a real file is opened, so it never runs on an empty
-- session and never adds its node process to startup.
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("copilot_lazy", { clear = true }),
  once = true,
  callback = function()
    require("copilot").setup({
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<C-y>",
          accept_word = false,
          accept_line = false,
          next = "<C-n>",
          prev = "<C-p>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
      },
    })
  end,
})

-- ==============================================================================
-- nvim-lspconfig and mason-lspconfig.nvim
-- ==============================================================================

local diagnostic_icons = {
  [vim.diagnostic.severity.ERROR] = " ",
  [vim.diagnostic.severity.WARN] = " ",
  [vim.diagnostic.severity.INFO] = " ",
  [vim.diagnostic.severity.HINT] = " ",
}

vim.diagnostic.config({
  underline = true,
  update_in_insert = false,
  virtual_text = {
    spacing = 4,
    prefix = function(diagnostic)
      return diagnostic_icons[diagnostic.severity] or "● "
    end,
  },
  severity_sort = true,
  float = {
    border = "rounded",
    source = true,
  },
})

local servers = {
  bashls = {},
  dockerls = {},
  gopls = {
    settings = {
      gopls = {
        analyses = {
          nilness = true,
          unusedparams = true,
          unusedwrite = true,
          useany = true,
        },
        completeUnimported = true,
        gofumpt = true,
        staticcheck = true,
        usePlaceholders = true,
      },
    },
  },
  jsonls = {},
  lua_ls = {
    settings = {
      Lua = {
        codeLens = { enable = true },
        completion = { callSnippet = "Replace" },
        hint = {
          enable = true,
          arrayIndex = "Disable",
          paramName = "Disable",
          semicolon = "Disable",
        },
        runtime = { version = "LuaJIT" },
        workspace = {
          checkThirdParty = false,
          library = { vim.env.VIMRUNTIME },
        },
      },
    },
  },
  marksman = {},
  pyright = {},
  ruff = {},
  tsgo = {},
  eslint = {},
  yamlls = {},
}

vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  vim.lsp.enable(name)
end

-- Rustaceanvim owns the rust-analyzer client, while Mason only provides its executable.
local mason_servers = vim.list_extend(vim.tbl_keys(servers), {})
table.sort(mason_servers)
require("mason-lspconfig").setup({
  ensure_installed = mason_servers,
  automatic_enable = false,
})

local function map(buffer, lhs, rhs, description)
  vim.keymap.set("n", lhs, rhs, { buffer = buffer, silent = true, desc = description })
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_keymaps", { clear = true }),
  callback = function(event)
    map(event.buf, "gd", function()
      require("plugins.navigation").ensure()
      require("telescope.builtin").lsp_definitions({ reuse_win = true })
    end, "Go to definition")
    map(event.buf, "gr", function()
      require("plugins.navigation").ensure()
      require("telescope.builtin").lsp_references()
    end, "References")
    map(event.buf, "gI", function()
      require("plugins.navigation").ensure()
      require("telescope.builtin").lsp_implementations({ reuse_win = true })
    end, "Go to implementation")
    map(event.buf, "gy", function()
      require("plugins.navigation").ensure()
      require("telescope.builtin").lsp_type_definitions({ reuse_win = true })
    end, "Go to type definition")
    map(event.buf, "gD", vim.lsp.buf.declaration, "Go to declaration")
    map(event.buf, "K", vim.lsp.buf.hover, "Hover")
    map(event.buf, "gK", vim.lsp.buf.signature_help, "Signature help")
    map(event.buf, "<leader>ca", vim.lsp.buf.code_action, "Code action")
    map(event.buf, "<leader>cr", vim.lsp.buf.rename, "Rename")
  end,
})

local function diagnostic_jump(count, severity)
  return function()
    vim.diagnostic.jump({ count = count * vim.v.count1, severity = severity, float = true })
  end
end

vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })
vim.keymap.set("n", "]d", diagnostic_jump(1), { desc = "Next diagnostic" })
vim.keymap.set("n", "[d", diagnostic_jump(-1), { desc = "Previous diagnostic" })
vim.keymap.set("n", "]e", diagnostic_jump(1, vim.diagnostic.severity.ERROR), { desc = "Next error" })
vim.keymap.set("n", "[e", diagnostic_jump(-1, vim.diagnostic.severity.ERROR), { desc = "Previous error" })
vim.keymap.set("n", "]w", diagnostic_jump(1, vim.diagnostic.severity.WARN), { desc = "Next warning" })
vim.keymap.set("n", "[w", diagnostic_jump(-1, vim.diagnostic.severity.WARN), { desc = "Previous warning" })

-- ==============================================================================
-- rustaceanvim
-- ==============================================================================

vim.g.rustaceanvim = {
  tools = {
    float_win_config = {
      border = "rounded",
    },
  },
}

-- ==============================================================================
-- crates.nvim
-- ==============================================================================

vim.api.nvim_create_autocmd("BufRead", {
  group = vim.api.nvim_create_augroup("crates_nvim", { clear = true }),
  pattern = "Cargo.toml",
  once = true,
  callback = function()
    require("crates").setup({
      max_parallel_requests = 12,
      completion = {
        crates = {
          enabled = true,
        },
      },
      lsp = {
        enabled = true,
        actions = true,
        completion = true,
        hover = true,
      },
    })
  end,
})

-- ==============================================================================
-- conform.nvim
-- ==============================================================================

local conform = require("conform")

local function autoformat_enabled(buffer)
  local buffer_setting = vim.b[buffer].autoformat
  if buffer_setting ~= nil then
    return buffer_setting
  end

  return vim.g.autoformat ~= false
end

conform.setup({
  default_format_opts = {
    timeout_ms = 3000,
    async = false,
    quiet = false,
    lsp_format = "fallback",
  },
  formatters_by_ft = {
    lua = { "stylua" },
    fish = { "fish_indent" },
    sh = { "shfmt" },
    javascript = { "prettierd", "prettier", stop_after_first = true },
    typescript = { "prettierd", "prettier", stop_after_first = true },
    css = { "prettierd", "prettier", stop_after_first = true },
    yaml = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
    markdown = { "prettierd", "prettier", stop_after_first = true },
    html = { "prettierd", "prettier", stop_after_first = true },
    toml = { "taplo" },
  },
  format_on_save = function(buffer)
    if autoformat_enabled(buffer) then
      return {}
    end
  end,
})

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

vim.keymap.set({ "n", "x" }, "<leader>cf", function()
  conform.format()
end, { desc = "Format" })

vim.keymap.set("n", "<leader>uf", function()
  local enabled = vim.g.autoformat == false
  vim.g.autoformat = enabled
  vim.b.autoformat = nil
  vim.notify("Global auto format " .. (enabled and "enabled" or "disabled"))
end, { desc = "Toggle auto format (global)" })

vim.keymap.set("n", "<leader>uF", function()
  local enabled = not autoformat_enabled(0)
  vim.b.autoformat = enabled
  vim.notify("Buffer auto format " .. (enabled and "enabled" or "disabled"))
end, { desc = "Toggle auto format (buffer)" })
