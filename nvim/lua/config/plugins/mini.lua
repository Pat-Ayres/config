return {
  {
    'echasnovski/mini.nvim',
    config = function()
      -- [[
      -- statusline setup
      --
      -- prerequisites
      --
      -- icons
      -- git
      -- diff
      -- ]]

      local icons = require 'mini.icons'
      icons.setup()
      local git = require 'mini.git'
      git.setup()
      vim.keymap.set("n", "<leader>gbl", ":lefta vert Git blame -- %<cr>")
      local diff = require 'mini.diff'
      diff.setup()
      local statusline = require 'mini.statusline'
      statusline.setup { use_icons = true }

      -- [[
      -- comments setup
      --
      -- embed context aware commenting capabilities
      --
      -- ]]
      local comments = require 'mini.comment'
      comments.setup({
        options = {
          custom_commentstring = function()
            return require('ts_context_commentstring').calculate_commentstring() or vim.bo.commentstring
          end
        }
      })
    end
  }
}
