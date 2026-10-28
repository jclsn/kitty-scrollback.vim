# kitty-scrollback.vim - kitty's show_scrollback, or tmux's when tmux runs in
# the window
#
# kitty only sees tmux's screen, so when a tmux client is the foreground
# process of the window, this shows the history of tmux's active pane with
# tmux-scrollback.sh instead. A tmux running elsewhere, behind ssh, can't be
# reached from here. When it is set up for this plugin, it sets the user
# variable kitty_scrollback_tmux while a client is attached, and this sends it
# the key that tmux binds to tmux-scrollback.sh.
#
# kitty.conf (:KittyScrollbackSetup writes this):
#   map kitty_mod+h kitten ~/.vim/plugged/kitty-scrollback.vim/kitty_scrollback.py vim

import os
from typing import Any

from kittens.runner import path_to_custom_kitten
from kittens.tui.handler import result_handler
from kitty.constants import config_dir

# Must match TMUX_KEY in autoload/kitty_scrollback.vim
TMUX_KEY = '\x1b[4242~'


def main(args: list[str]) -> None:
    pass


def socket_args(cmdline: list[str]) -> list[str]:
    # The -L or -S the client was started with, following tmux's getopt string
    with_arg = 'cfLST'
    i = 1
    ans: list[str] = []
    while i < len(cmdline):
        arg = cmdline[i]
        if arg == '--' or not arg.startswith('-') or arg == '-':
            break
        j = 1
        while j < len(arg):
            flag = arg[j]
            if flag in with_arg:
                value = arg[j + 1:]
                if not value:
                    i += 1
                    value = cmdline[i] if i < len(cmdline) else ''
                if flag in 'LS':
                    ans = [f'-{flag}', value]
                break
            j += 1
        i += 1
    return ans


def foreground_pids(window: Any) -> list[int]:
    # kitty's own foreground_processes splits /proc/PID/stat at spaces, which
    # breaks on "tmux: client", the name tmux gives its client process. The
    # name is in parentheses and the fields after it are state, ppid and pgrp.
    if not os.path.isdir('/proc'):
        return [p['pid'] for p in window.child.foreground_processes]
    try:
        pgrp = os.tcgetpgrp(window.child.child_fd)
    except Exception:
        return []
    pids = []
    for x in os.listdir('/proc'):
        if not x.isdigit():
            continue
        try:
            with open(f'/proc/{x}/stat', 'rb') as f:
                stat = f.read().decode('utf-8', 'replace')
            if int(stat[stat.rfind(')') + 2:].split()[2]) == pgrp:
                pids.append(int(x))
        except Exception:
            continue
    return pids


def tmux_client(window: Any) -> dict[str, Any] | None:
    from kitty.child import cmdline_of_pid
    for pid in foreground_pids(window):
        try:
            cmdline = cmdline_of_pid(pid)
        except Exception:
            continue
        if cmdline and os.path.basename(cmdline[0]) == 'tmux':
            return {'pid': pid, 'cmdline': cmdline}
    return None


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: Any, target_window_id: int, boss: Any) -> None:
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    client = tmux_client(window)
    if client is None:
        # tmux leaves the alternate screen when it detaches, so a variable
        # that was never unset, after ssh died, can't fool this
        if window.user_vars.get('kitty_scrollback_tmux') and not window.screen.is_main_linebuf():
            window.write_to_child(TMUX_KEY)
        else:
            window.show_scrollback()
        return
    from kitty.child import environ_of_process
    env: dict[str, str] = {}
    try:
        # For TMUX_TMPDIR and PATH
        env = environ_of_process(client['pid'])
    except Exception:
        pass
    env.pop('TMUX', None)
    # kitty runs this without __file__, args[0] is the path from kitty.conf
    script = os.path.join(os.path.dirname(os.path.realpath(path_to_custom_kitten(config_dir, args[0]))), 'tmux-scrollback.sh')
    vim = args[1] if len(args) > 1 else 'vim'
    boss.run_background_process(
        [script, str(client['pid']), vim] + socket_args(client['cmdline']), env=env)
