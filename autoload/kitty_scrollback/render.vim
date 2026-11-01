vim9script

# Turn the ANSI escape sequences in the current buffer into text properties

import './colors.vim'

# SGR codes that set attributes
const set_attrs = {
  1: colors.BOLD,
  2: colors.DIM,
  3: colors.ITALIC,
  7: colors.REVERSE,
  8: colors.HIDDEN,
  9: colors.STRIKE,
}

# SGR codes that clear attributes
const clear_attrs = {
  22: colors.BOLD + colors.DIM,
  23: colors.ITALIC,
  27: colors.REVERSE,
  28: colors.HIDDEN,
  29: colors.STRIKE,
}

# Style key of the color that SGR 38/39, 48/49 and 58/59 set, by code / 10
const color_keys = {3: 'fg', 4: 'bg', 5: 'sp'}

# The same few SGR sequences repeat all over the scrollback, so remember the
# group each one leads to: "group sgr" -> group
var transitions: dict<string> = {}

# Parse the color of SGR 38, 48 or 58 at "params[idx]".  The color is in the
# same parameter (38:5:n, 38:2:colorspace:r:g:b) or in the following ones
# (38;5;n, 38;2;r;g;b).  Returns the color and the number of following
# parameters it used.
def ParseColor(params: list<list<string>>, idx: number): list<number>
  var p = params[idx]
  var consumed = 0
  if p->len() == 1
    p = [p[0]] + params[idx + 1 : idx + 4]->mapnew((_, q) => q[0])
    consumed = p->get(1, '') == '5' ? 2 : 4
  elseif p->len() >= 6 && p[1] == '2'
    # Drop the color space
    p = p[0 : 1] + p[3 : 5]
  endif

  var kind = p->get(1, '')
  if kind == '5' && p->len() >= 3 && p[2]->str2nr() < 256
    return [p[2]->str2nr(), consumed]
  elseif kind == '2' && p->len() >= 5
    var rgb = p[2]->str2nr() * 0x10000 + p[3]->str2nr() * 0x100 + p[4]->str2nr()
    return [colors.TRUECOLOR + rgb, consumed]
  endif

  # Where an unknown color ends can't be told, skip the rest
  return [-1, params[idx]->len() == 1 ? params->len() : 0]
enddef

# Apply the SGR parameters "sgr" to "style"
def ApplySgr(style: dict<number>, sgr: string)
  var params = sgr->split(';', true)->mapnew((_, v) => v->split(':', true))
  var i = 0
  while i < params->len()
    var p = params[i]
    var code = p[0]->str2nr()

    if code == 0
      style->extend(colors.DEFAULT_STYLE)
    elseif set_attrs->has_key(code)
      style.attrs = or(style.attrs, set_attrs[code])
    elseif clear_attrs->has_key(code)
      style.attrs = and(style.attrs, invert(clear_attrs[code]))
    elseif code == 4
      # 4:n selects the underline style
      style.underline = p->len() > 1 ? min([p[1]->str2nr(), 5]) : 1
    elseif code == 21
      style.underline = 2
    elseif code == 24
      style.underline = 0
    elseif (code >= 30 && code <= 37) || (code >= 90 && code <= 97)
      style.fg = code % 10 + (code >= 90 ? 8 : 0)
    elseif (code >= 40 && code <= 47) || (code >= 100 && code <= 107)
      style.bg = code % 10 + (code >= 100 ? 8 : 0)
    elseif code == 39 || code == 49 || code == 59
      style[color_keys[code / 10]] = -1
    elseif code == 38 || code == 48 || code == 58
      var [color, consumed] = ParseColor(params, i)
      style[color_keys[code / 10]] = color
      i += consumed
    endif

    i += 1
  endwhile
enddef

# Return the group that SGR parameters "sgr" lead to from "group"
def NextGroup(group: string, sgr: string): string
  var key = $'{group} {sgr}'
  if !transitions->has_key(key)
    var style = colors.GroupStyle(group)
    ApplySgr(style, sgr)
    transitions[key] = colors.GroupFor(style)
  endif
  return transitions[key]
enddef

# Return the length of the CSI sequence at the start of "seq" (the text after
# ESC).  A malformed one is 1, only its "[" is dropped.
def CsiLength(seq: string): number
  # Most are SGR, so try that first
  var sgr_end = seq->stridx('m') + 1
  if sgr_end > 0 && seq[1 : sgr_end - 2] =~ '^[0-9;:]*$'
    return sgr_end
  endif
  var csi_end = seq->matchend('^\[[0-?]*[ -/]*[@-~]')
  return csi_end < 0 ? 1 : csi_end
enddef

# Add the range of "group" from "start" to "end" to "ranges"
def AddRange(ranges: list<list<any>>, group: string, start: number, end: number)
  if group != '' && end > start
    ranges->add([group, start, end])
  endif
enddef

# Return whether a blank in "group" looks different from the default
# background
def VisibleBlank(group: string): bool
  var style = colors.GroupStyle(group)
  return style.bg >= 0 || style.underline > 0
    || and(style.attrs, colors.REVERSE + colors.STRIKE) != 0
enddef

# Text property type of blanks in the default style, drawn as virtual text
const blank_type = 'KittyScrollbackBlank'
prop_type_add(blank_type, {highlight: 'Normal'})

# Strip the escape sequences from line "lnum" and add the ranges of the text
# styles to "props".  Trailing blanks are dropped, so that "$", selections and
# yanks stop at the end of the text.  Those that are visible, like the
# background of a full screen program, are added to "virtual" as [lnum, col,
# group, width] to be drawn as virtual text.  "group" is the group at the start
# of the line.  Returns the text and the group at the end of the line.
def StripLine(line: string, lnum: number, group: string,
              props: dict<list<list<number>>>, virtual: list<list<any>>): list<string>
  var sequences = line->split("\e", true)
  var text = sequences[0]
  var ranges: list<list<any>> = []
  var cur_group = group
  var group_start = 1
  # An OSC sequence ending in ESC \ spans two items
  var in_osc = false

  for seq in sequences[1 :]
    var rest: string
    if in_osc && seq[0] == '\'
      rest = seq[1 :]
    elseif seq[0] == '['
      var len = CsiLength(seq)
      if seq[len - 1] == 'm'
        var new_group = NextGroup(cur_group, seq[1 : len - 2])
        if new_group != cur_group
          AddRange(ranges, cur_group, group_start, text->len() + 1)
          cur_group = new_group
          group_start = text->len() + 1
        endif
      endif
      rest = seq[len :]
    elseif seq[0] == ']'
      # OSC, like hyperlinks and shell integration marks
      var bel = seq->stridx("\x07")
      rest = bel < 0 ? '' : seq[bel + 1 :]
      in_osc = bel < 0
      text ..= rest
      continue
    else
      # Character set selection and other escapes
      rest = seq[seq =~ '^[()*+#%]' ? 2 : 1 :]
    endif
    in_osc = false
    text ..= rest
  endfor

  AddRange(ranges, cur_group, group_start, text->len() + 1)

  var keep = text->substitute('\s\+$', '', '')->len()
  # The last trailing blank that is visible
  var visible_end = keep
  for [g, _, end] in ranges
    if end - 1 > visible_end && VisibleBlank(g)
      visible_end = end - 1
    endif
  endfor

  # The trailing blanks up to there in their style, and in the default style
  # where no range covers them
  var col = keep + 1
  for [g, start, end] in ranges
    var from = max([start, col])
    var to = min([end - 1, visible_end])
    if from > to
      continue
    endif
    if from > col
      virtual->add([lnum, keep + 1, blank_type, from - col])
    endif
    virtual->add([lnum, keep + 1, VisibleBlank(g) ? g : blank_type, to - from + 1])
    col = to + 1
  endfor

  for [g, start, end] in ranges
    if start <= keep
      props[g] = props->get(g, [])->add([lnum, start, lnum, min([end, keep + 1])])
    endif
  endfor
  return [text->strpart(0, keep), cur_group]
enddef

# Replace the text in the current buffer with its plain text and highlight it
# with text properties
export def Render()
  var lines: list<string> = []
  var props: dict<list<list<number>>> = {}
  var virtual: list<list<any>> = []
  var group = ''

  for [idx, line] in getline(1, '$')->items()
    var [text, end_group] = StripLine(line, idx + 1, group, props, virtual)
    lines->add(text)
    group = end_group
  endfor

  setline(1, lines)
  for [name, ranges] in props->items()
    prop_add_list({type: name}, ranges)
  endfor
  for [lnum, col, name, width] in virtual
    prop_add(lnum, col, {type: name, text: repeat(' ', width)})
  endfor
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
