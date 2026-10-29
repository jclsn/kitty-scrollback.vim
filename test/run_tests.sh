#!/bin/bash

# Run the tests in the given files, or all of them

cd "$(dirname "$0")" || exit 1

# Use the environment VIMPRG or find it in PATH
VIMPRG="${VIMPRG:-$(command -v vim)}"
if [[ ! -x "$VIMPRG" ]]; then
  echo "ERROR: vim ($VIMPRG) not found or not executable."
  exit 1
fi

VIM_CMD="$VIMPRG -u NONE -U NONE -i NONE --noplugin -N --not-a-term"

# Keep the tests away from the user's kitty, tmux and caches
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
export XDG_CACHE_HOME="$TEST_HOME/cache"
export XDG_CONFIG_HOME="$TEST_HOME/config"
export KITTY_CONFIG_DIRECTORY="$TEST_HOME/kitty"
unset TMUX KITTY_PID KITTY_WINDOW_ID
mkdir -p "$KITTY_CONFIG_DIRECTORY"
echo "dim_opacity 0.5" > "$KITTY_CONFIG_DIRECTORY/kitty.conf"

ALL_TESTS=(
  "render_tests.vim"
  "colors_tests.vim"
  "pager_tests.vim"
  "setup_tests.vim"
  "tmux_tests.vim"
)
TESTS_TO_RUN=("${@:-${ALL_TESTS[@]}}")

# Colors on a terminal and in CI logs
GREEN=""
RED=""
RESET=""
if [[ -t 1 || -n "${CI:-}" ]]; then
  GREEN=$'\e[32m'
  RED=$'\e[31m'
  RESET=$'\e[0m'
fi

# Print the results file "$1" with [PASS] in green and [FAIL] in red
Colorize() {
  sed -e "s/\[PASS\]/${GREEN}[PASS]${RESET}/" -e "s/\[FAIL\]/${RED}[FAIL]${RESET}/" "$1"
}

# Align the results of all the files after the longest test name
NAME_WIDTH=$(grep -ho 'def g:Test_\w*' "${TESTS_TO_RUN[@]}" 2> /dev/null \
  | awk '{ print length($2) - 2 }' | sort -n | tail -n 1)

failed=0
for testfile in "${TESTS_TO_RUN[@]}"; do
  echo "===> Running: $testfile"

  if [[ $testfile == tmux_tests.vim ]] && ! command -v tmux > /dev/null; then
    echo "SKIPPED: tmux not found"
    continue
  fi

  # Vim exits on end of input before it is done starting, so give it an
  # input that stays open
  rm -f results.txt
  timeout 120 $VIM_CMD -c "let g:TestName='$testfile'" \
    -c "let g:TestNameWidth=${NAME_WIDTH:-0}" -S runner.vim \
    < <(exec sleep 130 2> /dev/null) > /dev/null 2>&1
  kill $! 2> /dev/null

  if [[ ! -f results.txt ]]; then
    echo "${RED}[FAIL]${RESET} Test results file 'results.txt' not found."
    failed=1
    continue
  fi
  Colorize results.txt
  if grep -q "\[FAIL\]" results.txt; then
    failed=1
  fi
  rm -f results.txt
done

if [[ $failed -ne 0 ]]; then
  echo "${RED}RESULT: Some tests FAILED.${RESET}"
  exit 1
fi
echo "${GREEN}RESULT: All tests passed.${RESET}"
