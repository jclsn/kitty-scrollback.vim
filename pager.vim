vim9script

# kitty-scrollback.vim: the vimrc of the scrollback pager.
#
# kitty starts it as its scrollback_pager with the scrollback on stdin and
# runs ":KittyScrollback", tmux starts it in a popup over the pane and runs
# ":TmuxScrollback" (see :help kitty-scrollback).  Vim must be started with
# -N, as Vim9 script resets 'cpoptions' after sourcing.

set encoding=utf-8

import './autoload/kitty_scrollback/colors.vim'
import './autoload/kitty_scrollback/render.vim'

const in_tmux = !empty($TMUX)

# Plugins could only paint over the terminal's colors
set noloadplugins
set termguicolors
set background=dark

# Look like the terminal screen
set nonumber
set norelativenumber
set nolist
set nocursorline
set nowrap
set noshowmode
set noshowcmd
set laststatus=0
set showtabline=0
set signcolumn=no
set colorcolumn=
set scrolloff=0
set sidescrolloff=0
set virtualedit=all
set tabstop=8
set shortmess+=IF
&fillchars = 'eob: '

# The command line row shows where we are
set ruler
&rulerformat = '%30(%=%#KittyScrollbackLabel# SCROLLBACK %* %l/%L%)'

# Underline styles, underline color and strikethrough as kitty draws them
&t_Cs = "\e[4:3m"
&t_Ce = "\e[4:0m"
&t_Us = "\e[4:2m"
&t_ds = "\e[4:4m"
&t_Ds = "\e[4:5m"
&t_Ts = "\e[9m"
&t_Te = "\e[29m"
&t_8u = "\e[58:2::%lu:%lu:%lum"
if in_tmux
  # Vim only knows these by itself for xterm-like terminals
  &t_8f = "\e[38;2;%lu;%lu;%lum"
  &t_8b = "\e[48;2;%lu;%lu;%lum"
endif

nnoremap q <Cmd>quitall!<CR>
nnoremap i <Cmd>quitall!<CR>

# Restores the view once Vim knows the window size
var PendingView: func()

# Show buffer line "top" at the top of the window and put the cursor on line
# "lnum", column "col".  "lnum" is 0 when the terminal's cursor was scrolled
# out of view.
def RestoreView(top: number, lnum: number, col: number)
  var last = line('$')
  var topline = max([1, min([top, last])])
  if lnum <= 0
    winrestview({topline: topline, lnum: min([topline + winheight(0) - 1, last]), col: 0})
    return
  endif

  # Vim keeps the last row for the command line, only scroll when the cursor
  # would end up there
  var cursor_lnum = max([1, min([lnum, last])])
  topline = max([topline, cursor_lnum - winheight(0) + 1])
  winrestview({topline: topline, lnum: cursor_lnum, col: 0})
  exe $'normal! {max([1, col])}|'
enddef

# Restore the view and ask the terminal for its colors
def OnVimEnter()
  if PendingView == null_function
    return
  endif
  PendingView()
  colors.Query()
  redraw!
enddef

# Render the buffer and restore the view with "Restore"
def Start(Restore: func())
  render.Render()
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nomodified
  setlocal nomodifiable
  colors.Apply()

  PendingView = Restore
  if v:vim_did_enter
    OnVimEnter()
  endif
enddef

# Show kitty's scrollback, which is in the buffer.  "input_line" is the buffer
# line of the first line on kitty's screen, "cursor_line" and "cursor_col" are
# the screen position of the cursor, or 0 when it was scrolled out of view.
def KittyScrollback(input_line: string, cursor_line: string, cursor_col: string)
  Start(() => {
    # The pager has the size of kitty's screen, whose last row is the last
    # buffer line
    var lnum = cursor_line->str2nr() <= 0 ? 0 : line('$') - &lines + cursor_line->str2nr()
    RestoreView(input_line->str2nr(), lnum, cursor_col->str2nr())
  })
enddef

# Show the history and screen of tmux pane "pane".  The popup has the pane's
# size, in copy mode the view and cursor are those of copy mode.
def TmuxScrollback(pane: string)
  setline(1, systemlist($'tmux capture-pane -p -e -S - -t {shellescape(pane)}'))

  var format = '#{history_size} #{?#{==:#{pane_mode},copy-mode},'
    .. '#{scroll_position} #{copy_cursor_x} #{copy_cursor_y},'
    .. '0 #{cursor_x} #{cursor_y}}'
  var values = systemlist($'tmux display -p -t {shellescape(pane)} {shellescape(format)}')
    ->join()->split()->map((_, n) => n->str2nr())
  var [history_size, scrolled, x, y] = (values + [0, 0, 0, 0])[: 3]

  var top = history_size + 1 - scrolled
  Start(() => {
    RestoreView(top, top + y, x + 1)
  })
enddef

# Copy yanked text to the system clipboard, through a tmux buffer in tmux and
# OSC 52 in kitty
def CopyToClipboard()
  if v:event.operator != 'y'
    return
  endif

  var text = v:event.regcontents + (v:event.regtype == 'V' ? [''] : [])
  if in_tmux
    system('tmux load-buffer -w -', text->join("\n"))
  else
    echoraw($"\e]52;c;{base64_encode(str2blob(text))}\e\\")
  endif
enddef

augroup KittyScrollback
  au!
  autocmd VimEnter * ++once OnVimEnter()
  autocmd TextYankPost * CopyToClipboard()
  autocmd TermResponseAll osc colors.OnOsc()
augroup END

command -bar -nargs=+ KittyScrollback KittyScrollback(<f-args>)
command -bar -nargs=1 TmuxScrollback TmuxScrollback(<f-args>)

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
