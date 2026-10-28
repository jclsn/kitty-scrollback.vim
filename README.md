# kitty-scrollback.vim

Use Vim as [kitty](https://sw.kovidgoyal.net/kitty/)'s scrollback pager. The
scrollback looks exactly like the screen you were just on. When the kitty
window runs [tmux](https://github.com/tmux/tmux), the same key shows the
history of the current tmux pane instead.

## Requirements

- Vim 9.1 or later with `+vim9script` and `+textprop` (`v:termosc` is needed
  for reading kitty's colors)
- kitty
- tmux 3.2 or later, to see tmux's history

## Installation

With [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'jclsn/kitty-scrollback.vim'
```

## Setup

The next time Vim starts inside kitty, it offers to configure kitty for you.
Choosing **Yes** backs up `kitty.conf`, sets `scrollback_pager`, maps the
scrollback key to the plugin's kitten and makes kitty reload its configuration.
This also works from Vim inside tmux inside kitty. Run `:KittyScrollbackSetup` to do this at any time.

Nothing happens outside kitty or when there is no `kitty.conf`. The file is
found the same way kitty finds it: `$KITTY_CONFIG_DIRECTORY`, then
`~/.config/kitty` (`$XDG_CONFIG_HOME/kitty`), and on macOS also
`~/Library/Preferences/kitty`.

To configure it by hand, add this to `kitty.conf` (the first setting on one
line):

```conf
scrollback_pager vim -N --not-a-term -u ~/.vim/plugged/kitty-scrollback.vim/pager.vim -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -
map kitty_mod+h kitten ~/.vim/plugged/kitty-scrollback.vim/kitty_scrollback.py vim
```

The setup maps whichever keys your config maps to `show_scrollback`, or
`kitty_mod+h` when there are none.

### tmux

kitty only sees tmux's screen, not the history of tmux's panes. When a tmux
client runs directly in the kitty window, the kitten asks tmux for the history
of the active pane and opens the pager in a popup that covers exactly that
pane. Nothing needs to be configured in tmux for that.

When tmux runs on another machine, behind ssh, the kitten can't reach it. For
that, run the setup in Vim inside that tmux as well. It adds this to
`tmux.conf`:

```tmux
set -as terminal-overrides ',*:smcup=\E[?1049h\E]1337;SetUserVar=kitty_scrollback_tmux=MQ==\007:rmcup=\E]1337;SetUserVar=kitty_scrollback_tmux\007\E[?1049l'
set -s user-keys[42] "\e[4242~"
bind -n User42 run-shell -b "~/.vim/plugged/kitty-scrollback.vim/tmux-scrollback.sh #{client_pid} vim"
```

While a client is attached, tmux sets a user variable in kitty, also through
ssh. Then the kitten sends tmux the key bound above instead of showing kitty's
scrollback. The plugin has to be installed on both machines: the kitten on the
one running kitty, the pager on the one running tmux.

### Disabling the check

To stop the check on startup:

```vim
g:kitty_scrollback_check = false
```

## Usage

Open the scrollback with kitty's `show_scrollback` action (`ctrl+shift+h` by
default), also when the window runs tmux. In tmux, when the pane is in copy
mode, the pager starts at copy mode's position. A purple **SCROLLBACK** label in the bottom row shows
that you are in the pager.

| Key    | Action                                                    |
| ------ | --------------------------------------------------------- |
| `q`, `i` | Close the pager                                         |
| `y`    | Yank, also copies to the system clipboard through kitty   |

Copying uses OSC 52, so `clipboard_control` must include `write-clipboard`.
That is kitty's default, and it also works over ssh. In tmux, yanks go to a
tmux buffer, which tmux passes on to the system clipboard when
`set-clipboard` is on.

### Tab title

kitty names the pager window `History`. To show something else in the tab
bar, test for that title in `tab_title_template`:

```conf
tab_title_template "{fmt.fg._b3a1e6 + fmt.bold + 'scrollback' + fmt.nobold + fmt.fg.tab if title == 'History' else title}"
```
