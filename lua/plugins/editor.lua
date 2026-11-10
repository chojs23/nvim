local function project_root()
  local markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }
  return vim.fs.root(0, { markers }) or vim.uv.cwd()
end

local function toggle_tree(path)
  local api = require("nvim-tree.api")
  local winid = api.tree.winid()
  if winid then
    api.tree.resize({ absolute = vim.api.nvim_win_get_width(winid) })
  else
    require("plugins.navigation").set_root(path)
  end
  api.tree.toggle({ path = path, find_file = true })
end

vim.keymap.set("n", "<leader>e", function()
  toggle_tree(project_root())
end, { desc = "Explorer root directory" })
vim.keymap.set("n", "<leader>E", function()
  toggle_tree(vim.uv.cwd())
end, { desc = "Explorer cwd" })

require("flash").setup({
  mode = "fuzzy",
  modes = {
    search = { enabled = false },
    char = { keys = { "f", "F" } },
  },
})

vim.keymap.set({ "n", "x", "o" }, "s", function()
  require("flash").jump()
end, { desc = "Flash" })

vim.o.timeout = true
vim.o.timeoutlen = 300
require("which-key").setup({
  win = { border = "single" },
  spec = {
    { "<leader>f", group = "file/find" },
    { "<leader>g", group = "git" },
    { "<leader>gh", group = "hunks" },
    { "<leader>s", group = "search" },
    { "<leader>sn", group = "Noice" },
    { "<leader>u", group = "toggle" },
  },
})

vim.keymap.set("n", "<leader>t", "<cmd>UndotreeToggle<cr>", { desc = "Undotree" })

require("hlslens").setup({ calm_down = false })
vim.api.nvim_set_hl(0, "HlSearchLens", { link = "Search" })

local search_keys = {
  n = [[<cmd>execute('normal! ' . v:count1 . 'n')<cr><cmd>lua require("hlslens").start()<cr>]],
  N = [[<cmd>execute('normal! ' . v:count1 . 'N')<cr><cmd>lua require("hlslens").start()<cr>]],
  ["*"] = [[*<cmd>lua require("hlslens").start()<cr>]],
  ["#"] = [[#<cmd>lua require("hlslens").start()<cr>]],
  ["g*"] = [[g*<cmd>lua require("hlslens").start()<cr>]],
  ["g#"] = [[g#<cmd>lua require("hlslens").start()<cr>]],
}
for key, command in pairs(search_keys) do
  vim.keymap.set("n", key, command, { silent = true })
end

require("scrollbar").setup({
  marks = {
    -- Lower values win overlaps, so Git marks (7) take precedence over the cursor.
    Cursor = { priority = 8 },
  },
  providers = {
    cursor = true,
    diagnostic = true,
    search = true,
    -- The provider picks up Gitsigns when it loads on the first file.
    gitsigns = true,
    marks = false,
  },
})
