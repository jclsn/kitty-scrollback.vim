vim9script

# Common routines used by the tests

# Wait up to "timeout" milliseconds for "Assert" to pass.  "Assert" must be a
# lambda containing one assert function.  Returns zero for success, one for
# failure (like the assert functions).
export def WaitForAssert(Assert: func(): number, timeout = 2000): number
  var start = reltime()
  while true
    var errors_len = v:errors->len()
    if Assert() == 0
      return 0
    endif
    if start->reltime()->reltimefloat() * 1000 > timeout
      return 1
    endif
    # Retry without the error of this attempt
    v:errors->remove(errors_len, -1)
    sleep 10m
  endwhile
  return 1
enddef

# Create a new temporary directory and return its path
export def TempDir(): string
  var dir = tempname()
  mkdir(dir, 'p')
  return dir
enddef

# Return the style "overrides" applied to the default style
export def Style(overrides: dict<number>): dict<number>
  return {fg: -1, bg: -1, sp: -1, attrs: 0, underline: 0}->extend(overrides)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
