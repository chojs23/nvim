local map = vim.keymap.set

map("v", "J", ":move '>+1<CR>gv=gv", { silent = true })
map("v", "K", ":move '<-2<CR>gv=gv", { silent = true })

map("n", "j", "gj")
map("n", "k", "gk")
map("n", "<F1>", "<Nop>")
map("i", "<F1>", "<Nop>")
map("n", "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Escape and clear search highlight" })
map("i", "<Esc>", "<Esc>l")
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>write<cr><esc>", { desc = "Save file" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })
