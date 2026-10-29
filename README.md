# kitty-scrollback.vim

Use Vim as [kitty](https://sw.kovidgoyal.net/kitty/)'s scrollback pager, with
the colors, view and cursor of the screen. In
[tmux](https://github.com/tmux/tmux), also behind ssh, the same key shows the
current pane's history.

Requires Vim 9.1.1703 with `+vim9script`, `+textprop` and `v:termosc`, and tmux 3.2
for tmux.

## Setup

```vim
Plug 'jclsn/kitty-scrollback.vim'
```

Run `:KittyScrollbackSetup` (inside tmux to set up tmux too). It adds the
settings from `:help kitty-scrollback` to `kitty.conf` and `tmux.conf`.

## Usage

`ctrl+shift+h` opens the scrollback, `q` or `i` closes it, `y` also copies to
the clipboard.

## Tests

```sh
./test/run_tests.sh                    # all tests
./test/run_tests.sh render_tests.vim   # one file
```

`VIMPRG` selects the Vim to test. The tmux tests need tmux and run against a
tmux server of their own.
