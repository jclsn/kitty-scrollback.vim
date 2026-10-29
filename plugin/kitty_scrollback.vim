if !has('vim9script') || v:version < 900
  " Needs Vim version 9.0 and above
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
