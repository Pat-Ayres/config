-- [[
--
-- SECTION: BOOTSTRAP LAZY
--
-- check if lazy exists already and pull it down if not
-- inject the lazy path into the runtimepath
--
-- ]]
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out,                            "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- [[
--
-- SECTION: OPTS
--
-- ]]

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.hidden = true
vim.opt.signcolumn = "auto:2"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.undofile = true
vim.opt.title = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.wildmode = "longest:full,full"
vim.opt.wrap = false
vim.opt.list = true
vim.opt.listchars = "eol:¬,tab:▸\\ ,lead:·,leadmultispace:-+,trail:~,precedes:<,extends:>"
vim.opt.mouse = "a"
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.sidescroll = 5
vim.opt.joinspaces = false
vim.opt.splitright = true
vim.opt.clipboard = "unnamedplus"
vim.opt.confirm = true
vim.opt.backup = true
vim.opt.backupdir = vim.fs.normalize("~/.local/share/nvim/backup//")
vim.opt.updatetime = 300
vim.opt.redrawtime = 10000

-- [[
--
-- SECTION: KEYBINDINGS
--
-- ]]

vim.keymap.set("n", "<leader>Q", ":bufdo bdelete<cr>")
vim.keymap.set("n", "<leader>k", ":nohlsearch<cr>")

-- allow gf to open non-existent files
vim.keymap.set("n", "gf", ":edit <cfile><cr>")

-- Reselect visual selection after indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

vim.keymap.set("v", "y", "myy`y")
vim.keymap.set("v", "Y", "myY`y")

vim.api.nvim_set_keymap("n", "n", "nzzzv", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "N", "Nzzzv", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "J", "mzJ`z", { noremap = true, silent = true })

vim.keymap.set("i", "jj", "<esc>")

vim.keymap.set("n", "<leader>vf", ":%! column -t -ts ','<cr>")

-- [[
--
-- SECTION: SETUP LAZY.NVIM
--
-- Run setup for lazy.nvim
-- enable colorscheme and import plugins from config dir
--
-- ]]
require("lazy").setup({
  spec = {
    { "folke/tokyonight.nvim",  config = function() vim.cmd.colorscheme "tokyonight" end },
    { import = "config.plugins" },
  },
  install = { colorscheme = { "tokyonight" } },
  change_detection = {
    -- automatically check for config file changes and reload the ui
    enabled = false,
    notify = false, -- get a notification when changes are found
  }
  -- automatically check for plugin updates
  -- checker = { enabled = true },
})
