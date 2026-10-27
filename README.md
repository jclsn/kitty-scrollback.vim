# kitty-scrollback.vim

Use Vim as [kitty](https://sw.kovidgoyal.net/kitty/)'s scrollback pager. The
scrollback looks exactly like the screen you were just on.

## Requirements

- Vim 9.1 or later with `+vim9script` and `+textprop` (`v:termosc` is needed
  for reading kitty's colors)
- kitty

## Installation

With [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'jclsn/kitty-scrollback.vim'
```

## Setup

The next time Vim starts inside kitty, it offers to configure kitty for you.
Choosing **Yes** backs up `kitty.conf`, sets `scrollback_pager` and makes kitty
reload its configuration. Run `:KittyScrollbackSetup` to do this at any time.

Nothing happens outside kitty or when there is no `kitty.conf`. The file is
found the same way kitty finds it: `$KITTY_CONFIG_DIRECTORY`, then
`~/.config/kitty` (`$XDG_CONFIG_HOME/kitty`), and on macOS also
`~/Library/Preferences/kitty`.

To configure it by hand, add this to `kitty.conf` (on one line):

```conf
scrollback_pager vim -N --not-a-term -u ~/.vim/plugged/kitty-scrollback.vim/pager.vim -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -
```

To stop the check on startup:

```vim
g:kitty_scrollback_check = false
```

## Usage

Open the scrollback with kitty's `show_scrollback` action (`ctrl+shift+h` by
default). A purple **SCROLLBACK** label in the bottom row shows that you are in
the pager.

| Key    | Action                                                    |
| ------ | --------------------------------------------------------- |
| `q`, `i` | Close the pager                                         |
| `y`    | Yank, also copies to the system clipboard through kitty   |

Copying uses OSC 52, so `clipboard_control` must include `write-clipboard`.
That is kitty's default, and it also works over ssh.

### Tab title

kitty names the pager window `History`. To show something else in the tab
bar, test for that title in `tab_title_template`:

```conf
tab_title_template "{fmt.fg._b3a1e6 + fmt.bold + 'scrollback' + fmt.nobold + fmt.fg.tab if title == 'History' else title}"
```
