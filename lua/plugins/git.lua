-- ==============================================================================
-- gitsigns.nvim
-- ==============================================================================

-- gitsigns loads on the first real file so it stays off the startup path.
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("gitsigns_lazy", { clear = true }),
  once = true,
  callback = function()
    vim.pack.add({ "https://github.com/lewis6991/gitsigns.nvim" }, { load = true, confirm = false })
    require("gitsigns").setup({
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      signs_staged = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
      current_line_blame = true,
      current_line_blame_formatter = "<abbrev_sha> - <author>, <author_time:%Y-%m-%d> - <summary>",
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 500,
        ignore_whitespace = false,
      },
      on_attach = function(buffer)
        local gs = require("gitsigns")

        local function map(mode, lhs, rhs, description)
          vim.keymap.set(mode, lhs, rhs, { buffer = buffer, silent = true, desc = description })
        end

        map("n", "]h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next Hunk")
        map("n", "[h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Previous Hunk")
        map("n", "]H", function()
          gs.nav_hunk("last")
        end, "Last Hunk")
        map("n", "[H", function()
          gs.nav_hunk("first")
        end, "First Hunk")
        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
        map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
        map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
        map("n", "<leader>ghb", function()
          gs.blame_line({ full = true })
        end, "Blame Line")
        map("n", "<leader>ghB", gs.blame, "Blame Buffer")
        map("n", "<leader>ghd", gs.diffthis, "Diff This")
        map("n", "<leader>ghD", function()
          gs.diffthis("~")
        end, "Diff This Against ~")
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select Hunk")
      end,
    })

    -- Now that gitsigns is loaded, wire its hunks into the scrollbar.
    require("scrollbar.handlers.gitsigns").setup()
    require("scrollbar.utils").set_highlights()
  end,
})

-- ==============================================================================
-- lazygit
-- ==============================================================================

local state = { window = nil }

local function project_root()
  return vim.fs.root(0, { ".git" }) or vim.uv.cwd()
end

local function close()
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
  end
  state.window = nil
end

local function open(cwd)
  if vim.fn.executable("lazygit") ~= 1 then
    vim.notify("lazygit executable was not found", vim.log.levels.ERROR)
    return
  end

  if state.window and vim.api.nvim_win_is_valid(state.window) then
    close()
    return
  end

  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.9)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"

  state.window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
  })

  vim.fn.jobstart({ "lazygit" }, {
    cwd = cwd,
    term = true,
    on_exit = function()
      vim.schedule(close)
    end,
  })

  vim.keymap.set("t", "<C-q>", close, { buffer = buffer, desc = "Close LazyGit" })
  vim.cmd.startinsert()
end

vim.api.nvim_create_user_command("LazyGit", function(options)
  open(options.bang and vim.uv.cwd() or project_root())
end, { bang = true })

vim.keymap.set("n", "<leader>gg", function()
  open(project_root())
end, { desc = "LazyGit root directory" })

vim.keymap.set("n", "<leader>gG", function()
  open(vim.uv.cwd())
end, { desc = "LazyGit cwd" })
