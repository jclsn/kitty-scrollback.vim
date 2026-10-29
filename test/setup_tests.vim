vim9script

# Tests for :KittyScrollbackSetup configuring kitty

import './common.vim'

source ../plugin/kitty_scrollback.vim

const pager_pattern = '^scrollback_pager \S\+ -N --not-a-term -u \S*/pager\.vim'
  .. ' -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -$'

# Create a kitty.conf with "lines" in a new config directory and return its
# path
def KittyConf(lines: list<string>): string
  $KITTY_CONFIG_DIRECTORY = common.TempDir()
  var fname = $'{$KITTY_CONFIG_DIRECTORY}/kitty.conf'
  writefile(lines, fname)
  return fname
enddef

# Return the map of "key" to tmux's key
def TmuxMap(key: string): string
  return $'map --when-focus-on var:kitty_scrollback_tmux {key} send_text all \x1b[4242~'
enddef

# Test for configuring kitty
def g:Test_Setup_Kitty()
  var lines = [
    'map kitty_mod+h show_scrollback',
    'map f1 show_scrollback',
    'scrollback_pager less',
    '# scrollback_pager more',
  ]
  var fname = KittyConf(lines)
  :KittyScrollbackSetup

  var result = readfile(fname)
  assert_equal(lines[0 : 1] + ['# scrollback_pager less', '# scrollback_pager more', '',
    '# Added by kitty-scrollback.vim'], result[: 5])
  assert_match(pager_pattern, result[6])
  assert_equal([TmuxMap('kitty_mod+h'), TmuxMap('f1')], result[7 :])

  # The original is backed up
  assert_equal(lines, readfile($'{fname}.bak'))
  assert_match('Reload kitty''s config', execute('messages'))
enddef

# Test for the default scrollback key
def g:Test_Setup_Kitty_DefaultKey()
  var fname = KittyConf(['font_size 12'])
  :KittyScrollbackSetup
  assert_equal(TmuxMap('kitty_mod+h'), readfile(fname)[-1])
enddef

# Test for commenting out the maps of an earlier setup
def g:Test_Setup_Kitty_OldMaps()
  var fname = KittyConf([TmuxMap('f2')])
  :KittyScrollbackSetup
  assert_equal('# ' .. TmuxMap('f2'), readfile(fname)[0])
enddef

# Test for running the setup again
def g:Test_Setup_Kitty_AlreadyConfigured()
  var fname = KittyConf(['map f1 show_scrollback'])
  :KittyScrollbackSetup
  var lines = readfile(fname)
  :messages clear
  :KittyScrollbackSetup
  assert_equal(lines, readfile(fname))
  assert_match('kitty already uses it', execute('messages'))
enddef

# Test for no kitty.conf
def g:Test_Setup_Kitty_NoConfig()
  $KITTY_CONFIG_DIRECTORY = common.TempDir()
  :KittyScrollbackSetup
  assert_equal([], readdir($KITTY_CONFIG_DIRECTORY))
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
