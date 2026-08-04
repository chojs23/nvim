-- ==============================================================================
-- nvim-tree.lua
-- ==============================================================================

local api = require("nvim-tree.api")

-- Shows "rw-r--r-- 1.2K" right-aligned for each file
local stats_min_width = 38
local home = vim.fs.normalize(assert(vim.uv.os_homedir(), "home directory unavailable"))
local home_git_disabled = false

local function home_git_ignores(path)
  path = vim.fs.normalize(path)
  if path == home or not vim.startswith(path, home .. "/") then
    return false
  end

  local result = vim.system({ "git", "-C", home, "check-ignore", "-q", "--", path }):wait()
  return result.code == 0
end

local function disable_home_git(git_root)
  return home_git_disabled and vim.fs.normalize(git_root) == home
end

local function set_root(path)
  local disable = home_git_ignores(path)
  if disable == home_git_disabled then
    return
  end

  home_git_disabled = disable

  -- nvim-tree caches Git roots. Clear the cache when the requested tree
  -- switches between home-tracked and home-ignored paths.
  require("nvim-tree.git").purge_state()
end

-- Directory arguments are hijacked before the explorer keymaps run, so apply
-- the same Git policy before nvim-tree handles their buffer event.
vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("nvim_tree_root_policy", { clear = true }),
  callback = function(event)
    local path = vim.api.nvim_buf_get_name(event.buf)
    if vim.fn.isdirectory(path) == 1 then
      set_root(path)
    end
  end,
})

local StatDecorator = api.Decorator:extend()

function StatDecorator:new()
  self.enabled = true
  self.highlight_range = "none"
  self.icon_placement = "right_align"

  -- :new() runs once per render, so the width check happens here instead
  -- of per node.
  local winid = api.tree.winid()
  self.enabled = winid ~= nil and vim.api.nvim_win_get_width(winid) >= stats_min_width
end

local function human_size(size)
  if size < 1024 then
    return size .. "B"
  end
  local units = { "K", "M", "G", "T" }
  local i = 0
  repeat
    size = size / 1024
    i = i + 1
  until size < 1024 or i == #units
  return string.format("%.1f%s", size, units[i])
end

local function rwx(mode)
  local chars = { "r", "w", "x" }
  local out = {}
  for shift = 8, 0, -1 do
    local on = math.floor(mode / 2 ^ shift) % 2 == 1
    out[#out + 1] = on and chars[(8 - shift) % 3 + 1] or "-"
  end
  return table.concat(out)
end

function StatDecorator:icons(node)
  if node.type ~= "file" then
    return nil
  end
  -- Nodes carry the stat the explorer already collected. Stat again only
  -- when it is missing, to avoid syscalls for every node on each render.
  local stat = node.fs_stat or vim.uv.fs_stat(node.absolute_path)
  if not stat then
    return nil
  end
  return {
    { str = rwx(stat.mode) .. " " .. human_size(stat.size), hl = { "Comment" } },
  }
end

-- The decorator only runs on render, so the tree must be redrawn when
-- its window is resized across the threshold. Redraw only on that
-- crossing, and with the renderer alone: api.tree.reload() rescans the
-- filesystem and git status, which made incremental resizing
-- (option+left/right) stutter.
local stats_shown = nil

vim.api.nvim_create_autocmd("WinResized", {
  group = vim.api.nvim_create_augroup("nvim_tree_stats_resize", { clear = true }),
  callback = function()
    local winid = api.tree.winid()
    if not winid or not vim.tbl_contains(vim.v.event.windows or {}, winid) then
      return
    end

    local show = vim.api.nvim_win_get_width(winid) >= stats_min_width
    if show == stats_shown then
      return
    end
    stats_shown = show

    -- Internal but draw-only API. Falls back to the heavy reload if a
    -- future nvim-tree update removes it.
    local ok, explorer = pcall(function()
      return require("nvim-tree.core").get_explorer()
    end)
    if ok and explorer and explorer.renderer then
      explorer.renderer:draw()
    else
      api.tree.reload()
    end
  end,
})

require("nvim-tree").setup({
  reload_on_bufenter = true,
  filesystem_watchers = {
    enable = true,
  },
  view = {
    width = 25,
  },
  renderer = {
    special_files = {},
    group_empty = true,
    highlight_git = true,
    icons = {
      show = {
        git = true,
      },
    },
    decorators = {
      "Git",
      "Open",
      "Hidden",
      "Modified",
      "Bookmark",
      "Diagnostics",
      "Copied",
      StatDecorator,
      "Cut",
    },
  },
  git = {
    enable = true,
    disable_for_dirs = disable_home_git,
    show_on_dirs = true,
  },
  filters = {
    dotfiles = false,
    git_ignored = false,
  },
})

-- ==============================================================================
-- telescope.nvim
-- ==============================================================================

local function project_root()
  return vim.fs.root(0, { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }) or vim.uv.cwd()
end

local function visual_selection()
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  return table.concat(lines, " ")
end

local function flash(prompt_buffer)
  require("flash").jump({
    pattern = "^",
    label = { after = { 0, 0 } },
    search = {
      mode = "search",
      exclude = {
        function(window)
          return vim.bo[vim.api.nvim_win_get_buf(window)].filetype ~= "TelescopeResults"
        end,
      },
    },
    action = function(match)
      local picker = require("telescope.actions.state").get_current_picker(prompt_buffer)
      picker:set_selection(match.pos[1] - 1)
    end,
  })
end

local function find_command()
  if vim.fn.executable("rg") == 1 then
    return { "rg", "--files", "--color", "never", "-g", "!.git" }
  end
  if vim.fn.executable("fd") == 1 then
    return { "fd", "--type", "f", "--color", "never", "-E", ".git" }
  end
end

-- Telescope is required and configured lazily on the first picker use, so it
-- stays off the startup path. Every keymap below and the LSP pickers in code.lua
-- go through ensure() first.
local configured = false
local function ensure()
  if configured then
    return
  end
  configured = true

  local actions = require("telescope.actions")
  local builtin = require("telescope.builtin")

  require("telescope").setup({
    defaults = {
      prompt_prefix = "> ",
      selection_caret = "> ",
      get_selection_window = function()
        local windows = vim.api.nvim_list_wins()
        table.insert(windows, 1, vim.api.nvim_get_current_win())
        for _, window in ipairs(windows) do
          local buffer = vim.api.nvim_win_get_buf(window)
          if vim.bo[buffer].buftype == "" then
            return window
          end
        end
        return 0
      end,
      mappings = {
        i = {
          ["<A-i>"] = function()
            local line = require("telescope.actions.state").get_current_line()
            builtin.find_files({ no_ignore = true, default_text = line })
          end,
          ["<A-h>"] = function()
            local line = require("telescope.actions.state").get_current_line()
            builtin.find_files({ hidden = true, default_text = line })
          end,
          ["<C-Down>"] = actions.cycle_history_next,
          ["<C-Up>"] = actions.cycle_history_prev,
          ["<C-f>"] = actions.preview_scrolling_down,
          ["<C-b>"] = actions.preview_scrolling_up,
          ["<C-s>"] = flash,
        },
        n = {
          q = actions.close,
          s = flash,
        },
      },
    },
    pickers = {
      find_files = {
        find_command = find_command(),
        hidden = true,
      },
    },
  })
end

local function find_files(options)
  ensure()
  options = options or {}
  local cwd = options.cwd or project_root()
  local builtin = require("telescope.builtin")
  if vim.uv.fs_stat(cwd .. "/.git") then
    builtin.git_files({ cwd = cwd, show_untracked = true })
  else
    builtin.find_files({ cwd = cwd, hidden = true })
  end
end

-- Wrap a telescope.builtin picker so telescope is configured on first use.
local function pick(name, opts)
  return function()
    ensure()
    require("telescope.builtin")[name](opts)
  end
end

local map = vim.keymap.set
local root = project_root

map("n", "<leader>,", pick("buffers", { sort_mru = true, sort_lastused = true }), { desc = "Switch buffer" })
map("n", "<leader>/", function()
  ensure()
  require("telescope.builtin").live_grep({ cwd = root() })
end, { desc = "Grep root directory" })
map("n", "<leader>:", pick("command_history"), { desc = "Command history" })
map("n", "<leader><space>", find_files, { desc = "Find files in root directory" })

map("n", "<leader>fb", pick("buffers", { sort_mru = true, sort_lastused = true, ignore_current_buffer = true }),
  { desc = "Buffers" })
map("n", "<leader>fB", pick("buffers"), { desc = "All buffers" })
map("n", "<leader>fc", function()
  ensure()
  require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config"), hidden = true })
end, { desc = "Find config file" })
map("n", "<leader>ff", find_files, { desc = "Find files in root directory" })
map("n", "<leader>fF", function()
  find_files({ cwd = vim.uv.cwd() })
end, { desc = "Find files in cwd" })
map("n", "<leader>fg", pick("git_files"), { desc = "Find Git files" })
map("n", "<leader>fr", pick("oldfiles"), { desc = "Recent files" })
map("n", "<leader>fR", function()
  ensure()
  require("telescope.builtin").oldfiles({ cwd = vim.uv.cwd() })
end, { desc = "Recent files in cwd" })

map("n", "<leader>gc", pick("git_commits"), { desc = "Git commits" })
map("n", "<leader>gf", pick("git_bcommits"), { desc = "Git current file history" })
map("n", "<leader>gl", pick("git_commits"), { desc = "Git commits" })
map("n", "<leader>gs", pick("git_status"), { desc = "Git status" })
map("n", "<leader>gS", pick("git_stash"), { desc = "Git stash" })

map("n", '<leader>s"', pick("registers"), { desc = "Registers" })
map("n", "<leader>s/", pick("search_history"), { desc = "Search history" })
map("n", "<leader>sa", pick("autocommands"), { desc = "Autocommands" })
map("n", "<leader>sb", pick("current_buffer_fuzzy_find"), { desc = "Buffer lines" })
map("n", "<leader>sc", pick("command_history"), { desc = "Command history" })
map("n", "<leader>sC", pick("commands"), { desc = "Commands" })
map("n", "<leader>sd", pick("diagnostics"), { desc = "Diagnostics" })
map("n", "<leader>sD", pick("diagnostics", { bufnr = 0 }), { desc = "Buffer diagnostics" })
map("n", "<leader>sg", function()
  ensure()
  require("telescope.builtin").live_grep({ cwd = root() })
end, { desc = "Grep root directory" })
map("n", "<leader>sG", pick("live_grep"), { desc = "Grep cwd" })
map("n", "<leader>sh", pick("help_tags"), { desc = "Help pages" })
map("n", "<leader>sH", pick("highlights"), { desc = "Highlight groups" })
map("n", "<leader>sj", pick("jumplist"), { desc = "Jumplist" })
map("n", "<leader>sk", pick("keymaps"), { desc = "Keymaps" })
map("n", "<leader>sl", pick("loclist"), { desc = "Location list" })
map("n", "<leader>sM", pick("man_pages"), { desc = "Man pages" })
map("n", "<leader>sm", pick("marks"), { desc = "Marks" })
map("n", "<leader>so", pick("vim_options"), { desc = "Options" })
map("n", "<leader>sR", pick("resume"), { desc = "Resume" })
map("n", "<leader>sq", pick("quickfix"), { desc = "Quickfix list" })
map("n", "<leader>sw", function()
  ensure()
  require("telescope.builtin").grep_string({ cwd = root(), word_match = "-w" })
end, { desc = "Word in root directory" })
map("n", "<leader>sW", function()
  ensure()
  require("telescope.builtin").grep_string({ word_match = "-w" })
end, { desc = "Word in cwd" })
map("x", "<leader>sw", function()
  ensure()
  require("telescope.builtin").grep_string({ cwd = root(), search = visual_selection() })
end, { desc = "Selection in root directory" })
map("x", "<leader>sW", function()
  ensure()
  require("telescope.builtin").grep_string({ search = visual_selection() })
end, { desc = "Selection in cwd" })
map("n", "<leader>uC", pick("colorscheme"), { desc = "Colorscheme preview" })
map("n", "<leader>ss", pick("lsp_document_symbols"), { desc = "Document symbols" })
map("n", "<leader>sS", pick("lsp_dynamic_workspace_symbols"), { desc = "Workspace symbols" })

-- ==============================================================================
-- smart-splits.nvim
-- ==============================================================================

local smart_splits = require("smart-splits")
smart_splits.setup({})

local map = vim.keymap.set

local function resize_and_remember_tree_width(resize)
  return function()
    resize()

    local api = require("nvim-tree.api")
    local winid = api.tree.winid()
    if not winid then
      return
    end

    for _, other_winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local is_tiled_neighbor = other_winid ~= winid
          and vim.api.nvim_win_get_config(other_winid).relative == ""
      if is_tiled_neighbor then
        api.tree.resize({ absolute = vim.api.nvim_win_get_width(winid) })
        return
      end
    end
  end
end

map("n", "<C-h>", smart_splits.move_cursor_left, { desc = "Move cursor left" })
map("n", "<C-j>", smart_splits.move_cursor_down, { desc = "Move cursor down" })
map("n", "<C-k>", smart_splits.move_cursor_up, { desc = "Move cursor up" })
map("n", "<C-l>", smart_splits.move_cursor_right, { desc = "Move cursor right" })
map("n", "<A-h>", resize_and_remember_tree_width(smart_splits.resize_left), { desc = "Resize left" })
map("n", "<A-j>", smart_splits.resize_down, { desc = "Resize down" })
map("n", "<A-k>", smart_splits.resize_up, { desc = "Resize up" })
map("n", "<A-l>", resize_and_remember_tree_width(smart_splits.resize_right), { desc = "Resize right" })

return {
  ensure = ensure,
  set_root = set_root,
}
