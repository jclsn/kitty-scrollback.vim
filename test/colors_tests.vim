vim9script

# Tests for the terminal colors and the highlight groups of the styles.
# run_tests.sh sets dim_opacity to 0.5 in kitty.conf.  The tests run in
# alphabetical order, the Test_Osc_* ones change the terminal colors.

import './common.vim'
import '../autoload/kitty_scrollback/colors.vim'

const Style = common.Style

# Return the highlight attributes of the group for "style"
def Highlight(style: dict<number>): dict<any>
  return hlget(colors.GroupFor(style))[0]
enddef

# Test for the default style having no group
def g:Test_GroupFor_Default()
  assert_equal('', colors.GroupFor(Style({})))
enddef

# Test for reusing the group of a style
def g:Test_GroupFor_Reuse()
  var group = colors.GroupFor(Style({fg: 3}))
  assert_match('^KittySgr\d\+$', group)
  assert_equal(group, colors.GroupFor(Style({fg: 3})))
  assert_notequal(group, colors.GroupFor(Style({fg: 4})))
  assert_equal(Style({fg: 3}), colors.GroupStyle(group))
  assert_equal(Style({}), colors.GroupStyle(''))
  assert_true(prop_type_get(group)->has_key('highlight'))
enddef

# Test for the colors of the xterm palette
def g:Test_Highlight_Palette()
  assert_equal('#cd0000', Highlight(Style({fg: 1})).guifg)
  assert_equal('#ff0000', Highlight(Style({fg: 196})).guifg)
  assert_equal('#080808', Highlight(Style({fg: 232})).guifg)
  assert_equal('#5c5cff', Highlight(Style({bg: 12})).guibg)
enddef

# Test for true colors
def g:Test_Highlight_TrueColor()
  var hl = Highlight(Style({fg: colors.TRUECOLOR + 0x102030, bg: colors.TRUECOLOR + 0xa0b0c0}))
  assert_equal('#102030', hl.guifg)
  assert_equal('#a0b0c0', hl.guibg)
enddef

# Test for the attributes and underline styles
def g:Test_Highlight_Attributes()
  var attrs = colors.BOLD + colors.ITALIC + colors.STRIKE
  var hl = Highlight(Style({attrs: attrs, underline: 3, sp: 2}))
  var expected = {bold: true, italic: true, strikethrough: true, undercurl: true}
  assert_equal(expected, hl.gui)
  assert_equal(expected, hl.cterm)
  assert_equal('#00cd00', hl.guisp)

  assert_equal({underdouble: true}, Highlight(Style({underline: 2})).gui)
  assert_equal({underdashed: true}, Highlight(Style({underline: 5})).gui)
enddef

# Test for reverse video with the default colors
def g:Test_Highlight_Reverse()
  var hl = Highlight(Style({attrs: colors.REVERSE}))
  assert_equal('#000000', hl.guifg)
  assert_equal('#ffffff', hl.guibg)
enddef

# Test for hidden text having the background color
def g:Test_Highlight_Hidden()
  var hl = Highlight(Style({bg: 4, attrs: colors.HIDDEN}))
  assert_equal('#0000ee', hl.guifg)
  assert_equal('#0000ee', hl.guibg)
enddef

# Test for dim text, blended with kitty's dim_opacity
def g:Test_Highlight_Dim()
  assert_equal('#808080', Highlight(Style({fg: 15, attrs: colors.DIM})).guifg)
  assert_equal('#bfbfbf', Highlight(Style({fg: 15, bg: 8, attrs: colors.DIM})).guifg)
enddef

# Test for the terminal's answer to a palette color query
def g:Test_Osc_Palette()
  var group = colors.GroupFor(Style({fg: 1}))
  colors.HandleOsc("\e]4;1;rgb:aa/bb/cc\e\\")
  common.WaitForAssert(() => assert_equal('#aabbcc', hlget(group)[0].guifg))
enddef

# Test for the background color, with four hex digits per component
def g:Test_Osc_Background()
  colors.HandleOsc("\e]11;rgb:1234/5678/9abc\e\\")
  common.WaitForAssert(() => assert_equal('#12569a', hlget('Normal')[0]->get('guibg', '')))
  assert_equal('dark', &background)

  # The colors are cached for the next time
  var cache = $'{$XDG_CACHE_HOME}/kitty-scrollback.vim/colors.json'
  common.WaitForAssert(() => assert_true(filereadable(cache)))
  assert_equal('#12569a', readfile(cache)->join()->json_decode().bg)
enddef

# Test for a light background setting 'background'
def g:Test_Osc_LightBackground()
  colors.HandleOsc("\e]11;rgb:ffff/ffff/f0f0\e\\")
  common.WaitForAssert(() => assert_equal('light', &background))
  assert_equal('#fffff0', hlget('Normal')[0]->get('guibg', ''))
enddef

# Test for the selection colors
def g:Test_Osc_Selection()
  colors.HandleOsc("\e]17;rgb:11/22/33\e\\")
  colors.HandleOsc("\e]19;rgb:44/55/66\e\\")
  common.WaitForAssert(() => assert_equal('#112233', hlget('Visual')[0]->get('guibg', '')))
  assert_equal('#445566', hlget('Visual')[0]->get('guifg', ''))
enddef

# Test for ignoring other OSC sequences
def g:Test_Osc_Ignored()
  var bg = hlget('Normal')[0]->get('guibg', '')
  colors.HandleOsc("\e]12;rgb:00/00/00\e\\")
  colors.HandleOsc("\e]8;;https://example.com\e\\")
  sleep 50m
  assert_equal(bg, hlget('Normal')[0]->get('guibg', ''))
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
