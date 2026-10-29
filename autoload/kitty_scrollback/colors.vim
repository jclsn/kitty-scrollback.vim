vim9script

# Terminal colors and the highlight groups of the scrollback's text styles.
#
# A style is a dict with the colors "fg", "bg" and "sp" (underline), the
# "attrs" flags and the "underline" style.  A color is -1 for the default
# color, 0-255 for a palette index or TRUECOLOR + 0xRRGGBB.

export const TRUECOLOR = 0x1000000

# Attribute flags
export const BOLD = 1
export const DIM = 2
export const ITALIC = 4
export const REVERSE = 8
export const HIDDEN = 16
export const STRIKE = 32

export const DEFAULT_STYLE = {fg: -1, bg: -1, sp: -1, attrs: 0, underline: 0}

# Highlight attribute of each underline style
const underlines = ['', 'underline', 'underdouble', 'undercurl', 'underdotted', 'underdashed']

# OSC color numbers of the terminal's answers
const osc_colors = {10: 'fg', 11: 'bg', 17: 'selbg', 19: 'selfg'}

const cache_file = (empty($XDG_CACHE_HOME) ? expand('~/.cache') : $XDG_CACHE_HOME)
  .. '/kitty-scrollback.vim/colors.json'

# Highlight group name -> style
var styles: dict<dict<number>> = {}

# Style key -> highlight group name
var group_names: dict<string> = {}

# Palette indices above 15 that the scrollback uses
var used_indices: dict<bool> = {}

var apply_timer = 0

# Return the default xterm palette
def XtermPalette(): list<string>
  var palette = [
    '#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
    '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff', '#ff00ff', '#00ffff', '#ffffff'
  ]
  # 6x6x6 color cube
  var steps = [0, 95, 135, 175, 215, 255]
  for i in range(216)
    palette->add(printf('#%02x%02x%02x', steps[i / 36], steps[(i / 6) % 6], steps[i % 6]))
  endfor
  # Grayscale ramp
  for i in range(24)
    var level = 8 + 10 * i
    palette->add(printf('#%02x%02x%02x', level, level, level))
  endfor
  return palette
enddef

# Colors of the terminal, updated from its answers to Query()
var term_colors = {
  palette: XtermPalette(),
  fg: synIDattr(hlID('Normal'), 'fg#') ?? '#ffffff',
  bg: synIDattr(hlID('Normal'), 'bg#') ?? '#000000',
  selfg: '',
  selbg: synIDattr(hlID('Visual'), 'bg#'),
}

# The colors of the last time are right until the terminal answers
try
  term_colors->extend(readfile(cache_file)->join()->json_decode())
catch
endtry

# Return kitty's dim_opacity in thousandths
def DimOpacity(): number
  var config_home = empty($XDG_CONFIG_HOME) ? expand('~/.config') : $XDG_CONFIG_HOME
  var config_dir = empty($KITTY_CONFIG_DIRECTORY) ? $'{config_home}/kitty' : $KITTY_CONFIG_DIRECTORY
  var opacity = 400
  try
    for line in readfile($'{config_dir}/kitty.conf')
      if line =~ '^\s*dim_opacity\s'
        opacity = float2nr(line->matchstr('[0-9.]\+')->str2float() * 1000)
      endif
    endfor
  catch
  endtry
  return opacity
enddef

const dim_opacity = DimOpacity()

# Return the "#rrggbb" value of "color", or "default" for the default color
def ColorValue(color: number, default: string): string
  if color < 0
    return default
  elseif color < 256
    return term_colors.palette[color]
  endif
  return printf('#%06x', color - TRUECOLOR)
enddef

# Return "fg" blended over "bg", the way kitty draws dim text
def Blend(fg: string, bg: string): string
  var rgb: list<string> = []
  for i in [1, 3, 5]
    var f = fg[i : i + 1]->str2nr(16)
    var b = bg[i : i + 1]->str2nr(16)
    rgb->add(printf('%02x', (f * dim_opacity + b * (1000 - dim_opacity) + 500) / 1000))
  endfor
  return '#' .. rgb->join('')
enddef

# Define highlight group "name" for "style"
def HighlightStyle(name: string, style: dict<number>)
  var fg = ColorValue(style.fg, term_colors.fg)
  var bg = style.bg < 0 ? 'NONE' : ColorValue(style.bg, term_colors.bg)
  if and(style.attrs, REVERSE) != 0
    [fg, bg] = [bg == 'NONE' ? term_colors.bg : bg, fg]
  endif

  var cell_bg = bg == 'NONE' ? term_colors.bg : bg
  if and(style.attrs, HIDDEN) != 0
    fg = cell_bg
  elseif and(style.attrs, DIM) != 0
    fg = Blend(fg, cell_bg)
  endif

  var sp = style.sp < 0 ? 'NONE' : ColorValue(style.sp, term_colors.fg)

  var attrs: list<string> = []
  if and(style.attrs, BOLD) != 0
    attrs->add('bold')
  endif
  if and(style.attrs, ITALIC) != 0
    attrs->add('italic')
  endif
  if and(style.attrs, STRIKE) != 0
    attrs->add('strikethrough')
  endif
  if style.underline > 0
    attrs->add(underlines[style.underline])
  endif
  var gui = attrs->empty() ? 'NONE' : attrs->join(',')

  exe $'highlight {name} guifg={fg} guibg={bg} guisp={sp} gui={gui} cterm={gui}'
enddef

# Return the style of highlight group "name", or the default style
export def GroupStyle(name: string): dict<number>
  return styles->get(name, DEFAULT_STYLE)->copy()
enddef

# Return the highlight group and text property type for "style", or an empty
# string for the default style
export def GroupFor(style: dict<number>): string
  if style == DEFAULT_STYLE
    return ''
  endif

  var key = printf('%d_%d_%d_%d_%d', style.fg, style.bg, style.sp, style.attrs, style.underline)
  if !group_names->has_key(key)
    var name = $'KittySgr{group_names->len()}'
    group_names[key] = name
    styles[name] = style
    for color in [style.fg, style.bg, style.sp]
      if color >= 16 && color < 256
        used_indices[color] = true
      endif
    endfor
    HighlightStyle(name, style)
    prop_type_add(name, {highlight: name, combine: false})
  endif
  return group_names[key]
enddef

# Set the highlight groups from the terminal colors
export def Apply()
  var bg = term_colors.bg
  var luma = 299 * bg[1 : 2]->str2nr(16) + 587 * bg[3 : 4]->str2nr(16) + 114 * bg[5 : 6]->str2nr(16)
  var background = luma > 127500 ? 'light' : 'dark'
  if &background != background
    # This reloads the colorscheme, so it must come before the overrides
    &background = background
  endif

  exe $'highlight Normal guifg={term_colors.fg} guibg={bg}'
  exe $'highlight EndOfBuffer guifg={bg} guibg={bg}'
  if !empty(term_colors.selbg)
    exe $'highlight Visual guifg={term_colors.selfg ?? 'NONE'} guibg={term_colors.selbg} gui=NONE cterm=NONE'
  endif
  highlight KittyScrollbackLabel guifg=#ffffff guibg=#7a5ccc gui=bold cterm=bold

  for [name, style] in styles->items()
    HighlightStyle(name, style)
  endfor
enddef

# Ask the terminal for its colors, OnOsc() handles the answers
export def Query()
  var query = "\e]10;?\e\\\e]11;?\e\\\e]17;?\e\\\e]19;?\e\\"
  for idx in range(16) + used_indices->keys()->mapnew((_, i) => i->str2nr())
    query ..= $"\e]4;{idx};?\e\\"
  endfor
  echoraw(query)
enddef

# Return the byte value of an X11 color component with 1 to 4 hex digits
def HexToByte(hex: string): number
  var max = float2nr(pow(16, hex->len())) - 1
  return (hex->str2nr(16) * 255 + max / 2) / max
enddef

# Save the terminal colors for the next time
def SaveCache()
  try
    mkdir(cache_file->fnamemodify(':h'), 'p')
    writefile([json_encode(term_colors)], cache_file)
  catch
  endtry
enddef

# Handle the terminal's answer to an OSC color query
export def OnOsc()
  var m = v:termosc->matchlist('\]\(\d\+\);\%(\(\d\+\);\)\=rgb:\(\x\+\)/\(\x\+\)/\(\x\+\)')
  if m->empty() || (m[1] != '4' && !osc_colors->has_key(m[1]))
    return
  endif

  var color = printf('#%02x%02x%02x', HexToByte(m[3]), HexToByte(m[4]), HexToByte(m[5]))
  if m[1] == '4'
    term_colors.palette[m[2]->str2nr()] = color
  else
    term_colors[osc_colors[m[1]]] = color
  endif

  # The answers arrive one by one, apply them all at once
  timer_stop(apply_timer)
  apply_timer = timer_start(20, (_) => {
    Apply()
    SaveCache()
    redraw!
  })
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
