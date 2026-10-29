vim9script

# Configure kitty and tmux to use pager.vim as the scrollback pager.
#
# While a tmux client is attached, tmux sets a user variable in kitty.  kitty
# then sends tmux the User42 key instead of showing its own scrollback, and
# tmux opens the pager in a popup over the pane.

const root_dir = expand('<script>:p')->resolve()->fnamemodify(':h:h:h')

# kitty user variable that is set while a tmux client is attached
const user_var = 'kitty_scrollback_tmux'

# Key sequence (after ESC) that kitty sends to tmux, tmux's User42 key
const user_key = '[4242~'

# Display an info message
def InfoMsg(msg: string)
  :echohl Question
  :echomsg $'kitty-scrollback.vim: {msg}'
  :echohl None
enddef

# Return the command that starts Vim with the pager vimrc
def PagerCmd(): string
  var vim = exepath('vim') ==# v:progpath ? 'vim' : v:progpath
  var vimrc = fnamemodify($'{root_dir}/pager.vim', ':~')
  return $'{vim} -N --not-a-term -u {vimrc}'
enddef

# Back up "fname", comment out the lines matching "old_pattern" and append
# "settings"
def AddSettings(fname: string, old_pattern: string, settings: list<string>)
  var lines = readfile(fname)
  writefile(lines, $'{fname}.bak')

  lines->map((_, l) => l =~ old_pattern ? $'# {l}' : l)
  writefile(lines + ['', '# Added by kitty-scrollback.vim'] + settings, fname)
  InfoMsg($'Configured {fname->fnamemodify(':~')}')
enddef

# Return the path of kitty.conf
def KittyConfFile(): string
  var config_home = empty($XDG_CONFIG_HOME) ? expand('~/.config') : $XDG_CONFIG_HOME
  var config_dir = empty($KITTY_CONFIG_DIRECTORY) ? $'{config_home}/kitty' : $KITTY_CONFIG_DIRECTORY
  return $'{config_dir}/kitty.conf'
enddef

# Set the pager in kitty.conf and make the scrollback keys send tmux's key
# while in tmux
def SetupKitty()
  var fname = KittyConfFile()
  if !filereadable(fname)
    return
  endif

  var lines = readfile(fname)
  if lines->match('^\s*scrollback_pager\s.*pager\.vim') != -1
    InfoMsg('kitty already uses it')
    return
  endif

  var keys = lines->copy()
    ->filter((_, l) => l =~ '^\s*map\s\+\S\+\s\+show_scrollback\s*$')
    ->map((_, l) => l->split()[1])
  if keys->empty()
    keys = ['kitty_mod+h']
  endif

  var settings = [
    $'scrollback_pager {PagerCmd()} -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -'
  ]
  for key in keys
    settings->add($'map --when-focus-on var:{user_var} {key} send_text all \x1b{user_key}')
  endfor
  AddSettings(fname, $'^\s*\(scrollback_pager\s\|map\s.*{user_var}\)', settings)

  # kitty reloads its configuration on SIGUSR1
  if empty($TMUX) && !empty($KITTY_PID)
    system($'kill -USR1 {$KITTY_PID}')
  else
    InfoMsg('Reload kitty''s config to use it')
  endif
enddef

# Return the tmux.conf of the running tmux server, or an empty string
def TmuxConfFile(): string
  return system('tmux display -p "#{config_files}"')->trim()->split(',')
    ->filter((_, f) => f !~ '^/etc/' && filewritable(f) == 1)
    ->get(0, '')
enddef

# Return the tmux settings that open the pager on tmux's User42 key
def TmuxSettings(): list<string>
  # tmux is in the alternate screen while a client is attached, so set the
  # user variable when entering it and unset it when leaving
  var overrides = $'smcup=\E[?1049h\E]1337;SetUserVar={user_var}=MQ==\007'
    .. $':rmcup=\E]1337;SetUserVar={user_var}\007\E[?1049l'

  # "run -C" expands the formats of the popup size
  var pager = escape($'{PagerCmd()} -c ''TmuxScrollback #{{pane_id}}''', '"\')
  var popup = 'display-popup -B -E -x P -y P -w #{pane_width} -h #{pane_height}'
    .. $' -d ''#{{pane_current_path}}'' \"{pager}\"'

  return [
    $'set -as terminal-overrides '',*:{overrides}''',
    $'set -s user-keys[42] "\e{user_key}"',
    $'bind -n User42 run -C "{popup}"',
  ]
enddef

# Add the key binding to tmux.conf and load it into the running server
def SetupTmux()
  if system('tmux list-keys -T root User42')->stridx('pager.vim') != -1
    InfoMsg('tmux already uses it')
    return
  endif

  var fname = TmuxConfFile()
  if fname->empty()
    InfoMsg('No tmux.conf found')
    return
  endif

  var settings = TmuxSettings()
  AddSettings(fname, $'^\s*[^ \t#].*\({user_var}\|4242\|pager\.vim\)', settings)

  var tmpfile = tempname()
  writefile(settings, tmpfile)
  system($'tmux source-file {shellescape(tmpfile)}')
  delete(tmpfile)

  # Clients that are already attached don't get the new terminal overrides
  for tty in systemlist('tmux list-clients -F "#{client_tty}"')
    try
      writefile(str2blob([$"\e]1337;SetUserVar={user_var}=MQ==\x07"]), tty)
    catch
    endtry
  endfor
enddef

# Configure kitty, and tmux when Vim runs in tmux
export def Setup()
  SetupKitty()
  if !empty($TMUX)
    SetupTmux()
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
