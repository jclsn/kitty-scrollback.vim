vim9script

# Tests for turning ANSI escape sequences into text properties

import './common.vim'
import '../autoload/kitty_scrollback/colors.vim'
import '../autoload/kitty_scrollback/render.vim'

const Style = common.Style

# Render "lines" in a new buffer and return the plain text
def Render(lines: list<string>): list<string>
  :enew!
  setline(1, lines)
  render.Render()
  return getline(1, '$')
enddef

# Return [col, length, style] of each text property in line "lnum"
def Props(lnum: number): list<list<any>>
  return prop_list(lnum)->mapnew((_, p) => [p.col, p.length, colors.GroupStyle(p.type)])
enddef

# Test for text without escape sequences
def g:Test_Render_PlainText()
  assert_equal(['hello', '', 'world'], Render(['hello', '', 'world']))
  assert_equal([], Props(1))
  assert_equal([], Props(3))
enddef

# Test for the basic attributes and colors
def g:Test_Render_BasicSgr()
  assert_equal(['red bold'], Render(["\e[1;31mred bold\e[0m"]))
  assert_equal([[1, 8, Style({fg: 1, attrs: colors.BOLD})]], Props(1))

  Render(["\e[2;3;7;8;9mx"])
  var attrs = colors.DIM + colors.ITALIC + colors.REVERSE + colors.HIDDEN + colors.STRIKE
  assert_equal([[1, 1, Style({attrs: attrs})]], Props(1))

  Render(["\e[95ma\e[104mb\e[39mc"])
  assert_equal([
    [1, 1, Style({fg: 13})],
    [2, 1, Style({fg: 13, bg: 12})],
    [3, 1, Style({bg: 12})],
  ], Props(1))
enddef

# Test for "ESC [ m" and SGR 0 resetting the style
def g:Test_Render_Reset()
  assert_equal(['abc'], Render(["\e[31ma\e[mb\e[32;0mc"]))
  assert_equal([[1, 1, Style({fg: 1})]], Props(1))
enddef

# Test for clearing attributes
def g:Test_Render_ClearAttributes()
  Render(["\e[1;3ma\e[22mb\e[23mc"])
  assert_equal([
    [1, 1, Style({attrs: colors.BOLD + colors.ITALIC})],
    [2, 1, Style({attrs: colors.ITALIC})],
  ], Props(1))
enddef

# Test for 256 colors with semicolons and colons
def g:Test_Render_256Colors()
  Render(["\e[38;5;196ma\e[48:5:21mb"])
  assert_equal([
    [1, 1, Style({fg: 196})],
    [2, 1, Style({fg: 196, bg: 21})],
  ], Props(1))
enddef

# Test for true colors with semicolons, colons and a color space
def g:Test_Render_TrueColors()
  Render(["\e[38;2;1;2;3ma\e[38:2:4:5:6mb\e[38:2::7:8:9mc"])
  assert_equal([
    [1, 1, Style({fg: colors.TRUECOLOR + 0x010203})],
    [2, 1, Style({fg: colors.TRUECOLOR + 0x040506})],
    [3, 1, Style({fg: colors.TRUECOLOR + 0x070809})],
  ], Props(1))
enddef

# Test for parameters following a color in the same sequence
def g:Test_Render_ParamsAfterColor()
  Render(["\e[38;5;196;1;48;2;10;20;30;4mx"])
  var style = Style({fg: 196, bg: colors.TRUECOLOR + 0x0a141e, attrs: colors.BOLD, underline: 1})
  assert_equal([[1, 1, style]], Props(1))
enddef

# Test for the underline styles and the underline color
def g:Test_Render_Underline()
  Render(["\e[4ma\e[4:3mb\e[21mc\e[58;5;1md\e[59me\e[24mf"])
  assert_equal([
    [1, 1, Style({underline: 1})],
    [2, 1, Style({underline: 3})],
    [3, 1, Style({underline: 2})],
    [4, 1, Style({underline: 2, sp: 1})],
    [5, 1, Style({underline: 2})],
  ], Props(1))
enddef

# Test for a style that continues on the next lines
def g:Test_Render_StyleAcrossLines()
  assert_equal(['a', 'b', 'c'], Render(["\e[31ma", 'b', "c\e[0m"]))
  for lnum in [1, 2, 3]
    assert_equal([[1, 1, Style({fg: 1})]], Props(lnum))
  endfor
enddef

# Test for removing OSC sequences, ended by BEL or ESC \
def g:Test_Render_Osc()
  var link = "\e]8;;https://example.com\e\\link\e]8;;\e\\"
  assert_equal(['a link b c'], Render([$"a {link} b\e]133;A\x07 c"]))
enddef

# Test for removing other CSI sequences and escapes
def g:Test_Render_OtherEscapes()
  assert_equal(['abcdef'], Render(["a\e[2Kb\e[?25hc\e(Bd\e=e\e[1;31Hf"]))
  assert_equal([], Props(1))
enddef

# Test for an escape sequence that is cut off
def g:Test_Render_Malformed()
  assert_equal(['a', 'b'], Render(["a\e[", "b\e]8;;"]))
enddef

# Test for multi-byte characters, text property columns are in bytes
def g:Test_Render_MultiByte()
  assert_equal(['äöü x'], Render(["äöü \e[31mx"]))
  assert_equal([[8, 1, Style({fg: 1})]], Props(1))
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
