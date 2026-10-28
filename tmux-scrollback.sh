#!/bin/sh
# kitty-scrollback.vim - Vim as tmux's scrollback pager
#
# Opens the history of a tmux client's active pane in pager.vim, in a
# borderless popup that covers exactly that pane. kitty_scrollback.py runs
# this when the kitty window runs tmux.
#
# Usage: tmux-scrollback.sh CLIENT_PID VIM [-L SOCKET_NAME | -S SOCKET_PATH]

client_pid=$1
vim=$2
socket_flag=$3
socket=$4
pager=$(cd "$(dirname "$0")" && pwd -P)/pager.vim

t() {
	if [ -n "$socket_flag" ]; then
		tmux "$socket_flag" "$socket" "$@"
	else
		tmux "$@"
	fi
}

# Quotes an argument for the shell that runs the popup command
q() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

client=$(t list-clients -F '#{client_pid} #{client_name}' |
	awk -v pid="$client_pid" '$1 == pid { print $2; exit }')
[ -n "$client" ] || exit
pane=$(t display -c "$client" -p '#{pane_id}') || exit

# The popup size isn't format expanded, so look it up here
size=$(t display -p -t "$pane" '#{pane_width} #{pane_height}') || exit
set -- $size

# Inside the popup $TMUX points to the right server again
t display-popup -c "$client" -t "$pane" -B -E \
	-x '#{popup_pane_left}' -y '#{popup_pane_bottom}' -w "$1" -h "$2" \
	-d '#{pane_current_path}' \
	"$(q "$vim") -N --not-a-term -u $(q "$pager") -c $(q "TmuxScrollback $pane")"
