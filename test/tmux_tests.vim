vim9script

# Tests for the tmux integration, against a tmux server of their own

import './common.vim'
import '../autoload/kitty_scrollback/colors.vim'

const tmp_dir = common.TempDir()
const socket = $'{tmp_dir}/tmux.sock'
const tmux_conf = $'{tmp_dir}/tmux.conf'

# Run tmux "args" and return its output
def Tmux(args: string): string
  return system($'tmux -S {shellescape(socket)} {args}')->trim()
enddef

# Start the server and make it the one of $TMUX, before the pager checks it
writefile(['set -g status off'], tmux_conf)
Tmux($'-f {shellescape(tmux_conf)} new-session -d -s test -x 40 -y 5 sh')
$TMUX = $'{socket},{Tmux("display -p ''#{pid}''")},0'

source ../pager.vim
source ../plugin/kitty_scrollback.vim

const Style = common.Style

# Return a new pane that runs "commands", once it has printed "last_line"
def NewPane(commands: list<string>, last_line: string): string
  var script = tempname()
  writefile(commands + ['exec sleep 60'], script)
  var pane = Tmux($'new-window -P -F "#{{pane_id}}" -t test "sh {script}"')
  common.WaitForAssert(() => assert_match(last_line, Tmux($'capture-pane -p -t {pane}')))
  return pane
enddef

# Return a new pane that shows colored text
def ColoredPane(): string
  return NewPane(["printf '\\033[31mred\\033[0m\\nplain\\n'"], 'plain')
enddef

# Test for showing the history of a pane
def g:Test_TmuxScrollback()
  var pane = ColoredPane()
  exe $'TmuxScrollback {pane}'
  assert_equal(['red', 'plain'], getline(1, 2))
  assert_equal([Style({fg: 1})], prop_list(1)->mapnew((_, p) => colors.GroupStyle(p.type)))
  assert_equal(3, line('.'))
  assert_equal(1, col('.'))
  assert_false(&modifiable)
enddef

# Test for a pane with history, the view follows the screen
def g:Test_TmuxScrollback_History()
  # 20 lines and the prompt line in a pane with 5 rows, 16 lines are history
  var pane = NewPane(['seq 1 20'], '20')
  exe $'TmuxScrollback {pane}'
  assert_equal('1', getline(1))
  assert_equal(17, line('w0'))
  assert_equal(21, line('.'))
enddef

# Test for the view and cursor of copy mode
def g:Test_TmuxScrollback_CopyMode()
  var pane = NewPane(['seq 1 20'], '20')
  Tmux($'copy-mode -t {pane}')
  Tmux($'send-keys -t {pane} -X history-top')
  Tmux($'send-keys -t {pane} -X cursor-down')
  exe $'TmuxScrollback {pane}'
  assert_equal(1, line('w0'))
  assert_equal(2, line('.'))
  assert_equal('2', getline('.'))
enddef

# Test for yanks going to a tmux buffer
def g:Test_Yank()
  var pane = ColoredPane()
  exe $'TmuxScrollback {pane}'
  :1yank
  common.WaitForAssert(() => assert_equal("red\n", system($'tmux -S {shellescape(socket)} show-buffer')))
enddef

# Test for configuring tmux
def g:Test_Setup_Tmux()
  $KITTY_CONFIG_DIRECTORY = common.TempDir()
  var lines = readfile(tmux_conf)
  :KittyScrollbackSetup

  var result = readfile(tmux_conf)
  assert_equal(lines + ['', '# Added by kitty-scrollback.vim'], result[: -4])
  assert_match('^set -as terminal-overrides '',\*:smcup=.*SetUserVar=kitty_scrollback_tmux=MQ==', result[-3])
  assert_equal('set -s user-keys[42] "\e[4242~"', result[-2])
  assert_match('^bind -n User42 run -C "display-popup .*pager\.vim .*TmuxScrollback #{pane_id}', result[-1])
  assert_equal(lines, readfile($'{tmux_conf}.bak'))

  # The settings are loaded into the running server
  assert_match('TmuxScrollback', Tmux('list-keys -T root User42'))
  assert_match('4242', Tmux('show -s user-keys'))
  assert_match('kitty_scrollback_tmux', Tmux('show -s terminal-overrides'))

  # Running it again changes nothing
  :KittyScrollbackSetup
  assert_equal(result, readfile(tmux_conf))
  assert_match('tmux already uses it', execute('messages'))
enddef

# Stop the tmux server
def g:TestCleanup()
  Tmux('kill-server')
  delete(tmp_dir, 'rf')
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
