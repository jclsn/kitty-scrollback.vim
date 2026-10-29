if !has('vim9script') || !has('patch-9.1.1703')
  " Needs Vim 9.1.1703 and above, for TermResponseAll on OSC responses
  finish
endif

vim9script noclear

# Vim as kitty's and tmux's scrollback pager

if get(g:, 'loaded_kitty_scrollback', false)
  finish
endif
g:loaded_kitty_scrollback = true

import autoload '../autoload/kitty_scrollback/setup.vim'

command -bar KittyScrollbackSetup setup.Setup()

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
