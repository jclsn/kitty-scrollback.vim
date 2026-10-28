vim9script
# kitty-scrollback.vim - Vim as kitty's scrollback pager
# The pager itself is pager.vim, which kitty starts with -u. This only offers
# to configure kitty for it, also from inside tmux.

if exists('g:loaded_kitty_scrollback')
	finish
endif
g:loaded_kitty_scrollback = 1

import autoload 'kitty_scrollback.vim'

command -bar KittyScrollbackSetup kitty_scrollback.Setup(true)

def Check()
	# Only ask in an interactive Vim
	if get(g:, 'kitty_scrollback_check', true) && has('ttyin') && has('ttyout')
		kitty_scrollback.Setup(false)
	endif
enddef

# After startup, so the prompt doesn't get in the way of the first screen
autocmd VimEnter * ++once timer_start(0, (_) => Check())
