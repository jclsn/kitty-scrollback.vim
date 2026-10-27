vim9script
# Locating kitty.conf and pointing its scrollback_pager at pager.vim. Also
# imported by pager.vim, so this must not have side effects when sourced.

export const PAGER = fnamemodify(resolve(expand('<script>:p')), ':h:h') .. '/pager.vim'

const MARKER = '# Added by kitty-scrollback.vim'

export def CacheDir(): string
	return (empty($XDG_CACHE_HOME) ? expand('~/.cache') : $XDG_CACHE_HOME) .. '/kitty-scrollback.vim'
enddef

def DeclinedFile(): string
	return CacheDir() .. '/declined'
enddef

# The user's kitty.conf, searched in the same order as kitty does, or '' when
# there is none
export def ConfigFile(): string
	var dirs: list<string> = []
	if !empty($KITTY_CONFIG_DIRECTORY)
		dirs->add($KITTY_CONFIG_DIRECTORY)
	else
		dirs->add((empty($XDG_CONFIG_HOME) ? expand('~/.config') : $XDG_CONFIG_HOME) .. '/kitty')
		if has('mac') || has('macunix')
			dirs->add(expand('~/Library/Preferences/kitty'))
		endif
	endif
	for dir in dirs
		if filereadable(dir .. '/kitty.conf')
			return dir .. '/kitty.conf'
		endif
	endfor
	return ''
enddef

def InKitty(): bool
	return !has('gui_running') && (!empty($KITTY_WINDOW_ID) || $TERM ==# 'xterm-kitty')
enddef

# Returns the value of the scrollback_pager that is in effect, following
# include directives like kitty does
def ActivePager(file: string, depth = 0): string
	var value = ''
	if depth > 8 || !filereadable(file)
		return value
	endif
	for line in readfile(file)
		const m = matchlist(line, '^\s*\(scrollback_pager\|include\|globinclude\)\s\+\(.\{-}\)\s*$')
		if empty(m)
			continue
		elseif m[1] ==# 'scrollback_pager'
			value = m[2]
		else
			var pattern = expand(m[2])
			if pattern !~ '^/'
				pattern = fnamemodify(file, ':h') .. '/' .. pattern
			endif
			for included in glob(pattern, true, true)
				const nested = ActivePager(included, depth + 1)
				if !empty(nested)
					value = nested
				endif
			endfor
		endif
	endfor
	return value
enddef

def IsConfigured(file: string): bool
	const value = ActivePager(file)
	return stridx(value, PAGER) >= 0 || stridx(value, fnamemodify(PAGER, ':~')) >= 0
enddef

def Quote(arg: string): string
	return arg =~ '^[[:alnum:]_./~+-]\+$' ? arg : '"' .. escape(arg, '"\') .. '"'
enddef

export def PagerSetting(): string
	const vim = exepath('vim') ==# v:progpath ? 'vim' : v:progpath
	return $'scrollback_pager {Quote(vim)} -N --not-a-term -u {Quote(fnamemodify(PAGER, ':~'))}'
		.. ' -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -'
enddef

def Configure(file: string)
	const lines = readfile(file)
	const backup = $'{file}.{strftime('%Y%m%d%H%M%S')}.bak'
	if writefile(lines, backup) != 0
		echoerr $'kitty-scrollback.vim: Could not write {backup}'
		return
	endif
	# Previous settings stay around commented out, ours goes last so it wins
	# over any include
	var result = lines->mapnew((_, l) => l =~ '^\s*scrollback_pager\s' ? '# ' .. l : l)
	result += ['', MARKER, PagerSetting()]
	if writefile(result, file) != 0
		echoerr $'kitty-scrollback.vim: Could not write {file}'
		return
	endif
	var msg = $'kitty-scrollback.vim: Configured {fnamemodify(file, ':~')} (backup: {fnamemodify(backup, ':t')})'
	if !empty($KITTY_PID) && executable('kill')
		# kitty reloads its configuration on SIGUSR1
		system($'kill -USR1 {str2nr($KITTY_PID)}')
		msg ..= ', kitty reloaded its config'
	else
		msg ..= ', reload kitty''s config to use it'
	endif
	echomsg msg
enddef

# Offers to set kitty's scrollback_pager to this plugin. Without "forced" this
# is silent unless a prompt is actually needed.
export def Setup(forced: bool)
	if !InKitty()
		if forced
			echomsg 'kitty-scrollback.vim: Not running in kitty'
		endif
		return
	endif
	const file = ConfigFile()
	if empty(file)
		if forced
			echomsg 'kitty-scrollback.vim: No kitty.conf found'
		endif
		return
	endif
	if IsConfigured(file)
		if forced
			echomsg $'kitty-scrollback.vim: {fnamemodify(file, ':~')} already uses it'
		endif
		return
	endif
	if !forced && filereadable(DeclinedFile())
		return
	endif
	const choice = confirm($"kitty-scrollback.vim: Use Vim as kitty's scrollback pager?\n"
		.. $"This sets scrollback_pager in {fnamemodify(file, ':~')}.",
		"&Yes\n&No\nNever &ask again", 1, 'Question')
	if choice == 1
		Configure(file)
		delete(DeclinedFile())
	elseif choice == 3
		mkdir(CacheDir(), 'p')
		writefile([], DeclinedFile())
		echomsg 'kitty-scrollback.vim: Won''t ask again, use :KittyScrollbackSetup to configure it later'
	endif
enddef
