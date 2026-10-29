vim9script

# Tests for showing kitty's scrollback in the pager

import './common.vim'

source ../pager.vim

const Style = common.Style

# Fill a new buffer with "count" numbered lines
def FillBuffer(count: number)
  :enew!
  setline(1, range(1, count)->mapnew((_, n) => $'line {n}'))
enddef

# Test for the scrollback buffer
def g:Test_KittyScrollback_Buffer()
  :enew!
  setline(1, ["\e[31mred\e[0m plain", "\e]8;;https://example.com\e\\link\e]8;;\e\\"])
  :KittyScrollback 1 1 1
  assert_equal(['red plain', 'link'], getline(1, '$'))
  assert_equal(1, prop_list(1)->len())
  assert_equal('nofile', &buftype)
  assert_false(&modifiable)
  assert_false(&modified)
  assert_false(&swapfile)
enddef

# Test for the cursor on the screen's cursor cell
def g:Test_KittyScrollback_Cursor()
  FillBuffer(&lines)
  :KittyScrollback 1 2 3
  assert_equal(1, line('w0'))
  assert_equal(2, line('.'))
  assert_equal(3, col('.'))
enddef

# Test for kitty being scrolled back, with the cursor out of view
def g:Test_KittyScrollback_ScrolledBack()
  FillBuffer(100)
  :KittyScrollback 10 0 0
  assert_equal(10, line('w0'))
  assert_equal(10 + winheight(0) - 1, line('.'))
enddef

# Test for the cursor on the last row, which Vim keeps for the command line
def g:Test_KittyScrollback_CursorOnLastRow()
  FillBuffer(100)
  exe $'KittyScrollback {100 - &lines + 1} {&lines} 5'
  assert_equal(100, line('.'))
  assert_equal(100 - winheight(0) + 1, line('w0'))
  assert_equal(5, col('.'))
enddef

# Test for the cursor in empty space, beyond the end of the line
def g:Test_KittyScrollback_CursorBeyondText()
  FillBuffer(&lines)
  :KittyScrollback 1 1 40
  assert_equal(1, line('.'))
  assert_equal(40, virtcol('.'))
enddef

# Test for the mappings that close the pager
def g:Test_Pager_Mappings()
  assert_match('quitall!', maparg('q', 'n'))
  assert_match('quitall!', maparg('i', 'n'))
enddef

# Test for the pager's options
def g:Test_Pager_Options()
  assert_true(&termguicolors)
  assert_true(&ruler)
  assert_equal(0, &laststatus)
  assert_equal('all', &virtualedit)
  assert_match('SCROLLBACK', &rulerformat)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
