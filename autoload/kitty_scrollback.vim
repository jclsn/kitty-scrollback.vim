vim9script
# Locating kitty.conf, pointing its scrollback_pager at pager.vim and mapping
# the scrollback key to kitty_scrollback.py, which shows tmux's scrollback
# when tmux runs in the window. In tmux, tmux.conf gets a key for the kitten to
# send, which is what makes it work with tmux behind ssh. Also imported by
# pager.vim, so this must not have side effects when sourced.

const ROOT = fnamemodify(resolve(expand('<script>:p')), ':h:h')
export const PAGER = ROOT .. '/pager.vim'
const KITTEN = ROOT .. '/kitty_scrollback.py'
const TMUX_SCRIPT = ROOT .. '/tmux-scrollback.sh'

const MARKER = '# Added by kitty-scrollback.vim'

# What kitty_scrollback.py sends to tmux, and tmux's User key for it
const TMUX_KEY = '\e[4242~'
const TMUX_USER_KEY = 42
# kitty's user variable telling the kitten that a tmux client is attached
const SET_VAR = '\E]1337;SetUserVar=kitty_scrollback_tmux=MQ==\007'
const UNSET_VAR = '\E]1337;SetUserVar=kitty_scrollback_tmux\007'

export def CacheDir(): string
	return (empty($XDG_CACHE_HOME) ? expand('~/.cache') : $XDG_CACHE_HOME) .. '/kitty-scrollback.vim'
enddef

def DeclinedFile(what: string): string
	return CacheDir() .. (what == 'tmux' ? '/declined-tmux' : '/declined')
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

def InTmux(): bool
	return !empty($TMUX) && executable('tmux')
enddef

def InKitty(): bool
	if has('gui_running')
		return false
	elseif InTmux()
		# The environment is the one of whatever started the tmux server. The
		# client's TERM is often not xterm-kitty, but tmux knows the terminal
		# from its answer to XTVERSION.
		const client = trim(system('tmux display -p "#{client_termname} #{client_termtype}"'))
		return client =~# '^xterm-kitty\>\|\<kitty('
	endif
	return !empty($KITTY_WINDOW_ID) || $TERM ==# 'xterm-kitty'
enddef

# The pid of the kitty that Vim runs in, or 0. In tmux that's the kitty
# running the tmux client, $KITTY_PID may be from another kitty.
def KittyPid(): number
	if !InTmux()
		return str2nr($KITTY_PID)
	endif
	var pid = str2nr(trim(system('tmux display -p "#{client_pid}"')))
	for _ in range(10)
		if pid <= 1 || v:shell_error != 0
			break
		endif
		const out = split(trim(system($'ps -o ppid= -o comm= -p {pid}')))
		if len(out) < 2
			break
		elseif fnamemodify(out[1], ':t') =~# '^kitty'
			return pid
		endif
		pid = str2nr(out[0])
	endfor
	return 0
enddef

# Returns the scrollback_pager that is in effect and the actions of all
# unconditional maps, following include directives like kitty does
def ActiveSettings(file: string, settings = {pager: '', maps: {}}, depth = 0): dict<any>
	if depth > 8 || !filereadable(file)
		return settings
	endif
	for line in readfile(file)
		const m = matchlist(line, '^\s*\(scrollback_pager\|map\|include\|globinclude\)\s\+\(.\{-}\)\s*$')
		if empty(m)
			continue
		elseif m[1] ==# 'scrollback_pager'
			settings.pager = m[2]
		elseif m[1] ==# 'map'
			const km = matchlist(m[2], '^\(\S\+\)\s*\(.*\)$')
			if !empty(km) && km[1] !~ '^--'
				settings.maps[tolower(km[1])] = km[2]
			endif
		else
			var pattern = expand(m[2])
			if pattern !~ '^/'
				pattern = fnamemodify(file, ':h') .. '/' .. pattern
			endif
			for included in glob(pattern, true, true)
				ActiveSettings(included, settings, depth + 1)
			endfor
		endif
	endfor
	return settings
enddef

def Mentions(value: string, path: string): bool
	return stridx(value, path) >= 0 || stridx(value, fnamemodify(path, ':~')) >= 0
enddef

def IsConfigured(file: string): bool
	const settings = ActiveSettings(file)
	return Mentions(settings.pager, PAGER)
		&& !settings.maps->values()->filter((_, a) => Mentions(a, KITTEN))->empty()
enddef

# The keys to map to the kitten: the ones that show the scrollback now
def ScrollbackKeys(file: string): list<string>
	const maps = ActiveSettings(file).maps
	var keys = maps->keys()->filter((_, k) => maps[k] =~# '^show_scrollback\s*$')
	return empty(keys) ? ['kitty_mod+h'] : sort(keys)
enddef

def Quote(arg: string): string
	return arg =~ '^[[:alnum:]_./~+-]\+$' ? arg : '"' .. escape(arg, '"\') .. '"'
enddef

def VimCommand(): string
	return exepath('vim') ==# v:progpath ? 'vim' : v:progpath
enddef

export def PagerSetting(): string
	return $'scrollback_pager {Quote(VimCommand())} -N --not-a-term -u {Quote(fnamemodify(PAGER, ':~'))}'
		.. ' -c "KittyScrollback INPUT_LINE_NUMBER CURSOR_LINE CURSOR_COLUMN" -'
enddef

export def MapSetting(key: string): string
	return $'map {key} kitten {Quote(fnamemodify(KITTEN, ':~'))} {Quote(VimCommand())}'
enddef

def Configure(file: string)
	const lines = readfile(file)
	const backup = $'{file}.{strftime('%Y%m%d%H%M%S')}.bak'
	if writefile(lines, backup) != 0
		echoerr $'kitty-scrollback.vim: Could not write {backup}'
		return
	endif
	const keys = ScrollbackKeys(file)
	# Previous settings stay around commented out, ours go last so they win
	# over any include
	var result = lines->mapnew((_, l) => l =~ '^\s*scrollback_pager\s' ? '# ' .. l : l)
	result += ['', MARKER, PagerSetting()] + keys->mapnew((_, k) => MapSetting(k))
	if writefile(result, file) != 0
		echoerr $'kitty-scrollback.vim: Could not write {file}'
		return
	endif
	var msg = $'kitty-scrollback.vim: Configured {fnamemodify(file, ':~')} (backup: {fnamemodify(backup, ':t')})'
	const pid = KittyPid()
	if pid > 0 && executable('kill')
		# kitty reloads its configuration on SIGUSR1
		system($'kill -USR1 {pid}')
		msg ..= ', kitty reloaded its config'
	else
		msg ..= ', reload kitty''s config to use it'
	endif
	echomsg msg
enddef

# The tmux.conf lines. tmux enters the alternate screen when a client attaches
# and leaves it when it detaches or exits, so that's where it sets and unsets
# the user variable in kitty, also through ssh.
export def TmuxSettings(): list<string>
	const script = fnamemodify(TMUX_SCRIPT, ':~') =~ '^[[:alnum:]_./~+-]\+$'
		? fnamemodify(TMUX_SCRIPT, ':~') : shellescape(TMUX_SCRIPT)
	const vim = VimCommand() =~ '^[[:alnum:]_./~+-]\+$' ? VimCommand() : shellescape(VimCommand())
	return [
		$'set -as terminal-overrides '',*:smcup=\E[?1049h{SET_VAR}:rmcup={UNSET_VAR}\E[?1049l''',
		$'set -s user-keys[{TMUX_USER_KEY}] "{TMUX_KEY}"',
		$'bind -n User{TMUX_USER_KEY} run-shell -b "{script} #{{client_pid}} {vim}"',
	]
enddef

# tmux's own config file, the first one tmux loaded that isn't the system one
def TmuxConfigFile(): string
	const loaded = system('tmux display -p "#{config_files}"')
	if v:shell_error == 0
		for file in split(trim(loaded), ',')
			if file !~ '^/etc/' && filewritable(file) == 1
				return file
			endif
		endfor
	endif
	return ''
enddef

# Whether the running tmux server runs tmux-scrollback.sh on the key
def IsTmuxConfigured(): bool
	const keys = system($'tmux list-keys -T root User{TMUX_USER_KEY}')
	return v:shell_error == 0 && Mentions(keys, TMUX_SCRIPT)
enddef

# Keys that earlier versions bound to tmux-scrollback.sh, whose arguments
# have changed since
def OldTmuxKeys(): list<string>
	var keys: list<string> = []
	for line in systemlist('tmux list-keys -T root')
		const m = matchlist(line, '^bind-key\s\+\%(-r\s\+\)\=-T\s\+root\s\+\(\S\+\)\s')
		if !empty(m) && m[1] !=# $'User{TMUX_USER_KEY}' && Mentions(line, TMUX_SCRIPT)
			keys->add(m[1])
		endif
	endfor
	return keys
enddef

def ConfigureTmux(file: string)
	const lines = readfile(file)
	const backup = $'{file}.{strftime('%Y%m%d%H%M%S')}.bak'
	if writefile(lines, backup) != 0
		echoerr $'kitty-scrollback.vim: Could not write {backup}'
		return
	endif
	const settings = TmuxSettings()
	# Settings of earlier versions stay around commented out
	const result = lines->mapnew((_, l) => l !~ '^\s*#' && Mentions(l, TMUX_SCRIPT) ? '# ' .. l : l)
	if writefile(result + ['', MARKER] + settings, file) != 0
		echoerr $'kitty-scrollback.vim: Could not write {file}'
		return
	endif
	# Only load these into the running server instead of sourcing everything
	# again
	const tmp = tempname()
	writefile(OldTmuxKeys()->mapnew((_, k) => $'unbind -n {k}') + settings, tmp)
	system($'tmux source-file {shellescape(tmp)}')
	const ok = v:shell_error == 0
	delete(tmp)
	if ok
		# The terminal overrides only apply when a client attaches, so tell
		# kitty about the clients that already are
		for tty in systemlist('tmux list-clients -F "#{client_tty}"')
			try
				writefile(str2blob(["\e]1337;SetUserVar=kitty_scrollback_tmux=MQ==\x07"]), tty)
			catch
			endtry
		endfor
	endif
	echomsg $'kitty-scrollback.vim: Configured {fnamemodify(file, ':~')} (backup: {fnamemodify(backup, ':t')})'
		.. (ok ? ', tmux loaded it' : ', reload tmux''s config to use it')
enddef

# Offers to add the key that kitty_scrollback.py sends to tmux.conf
def SetupTmux(forced: bool)
	if IsTmuxConfigured()
		if forced
			echomsg 'kitty-scrollback.vim: tmux already uses it'
		endif
		return
	endif
	const file = TmuxConfigFile()
	if empty(file)
		if forced
			echomsg 'kitty-scrollback.vim: No tmux.conf found'
		endif
		return
	endif
	if !forced && filereadable(DeclinedFile('tmux'))
		return
	endif
	const choice = confirm($"kitty-scrollback.vim: Show tmux's scrollback with kitty's scrollback key?\n"
		.. $"This adds a key binding to {fnamemodify(file, ':~')}.",
		"&Yes\n&No\nNever &ask again", 1, 'Question')
	if choice == 1
		ConfigureTmux(file)
		delete(DeclinedFile('tmux'))
	elseif choice == 3
		mkdir(CacheDir(), 'p')
		writefile([], DeclinedFile('tmux'))
		echomsg 'kitty-scrollback.vim: Won''t ask again, use :KittyScrollbackSetup to configure it later'
	endif
enddef

# Offers to configure tmux when running in it, and to set kitty's
# scrollback_pager to this plugin and map the scrollback key to the kitten.
# Without "forced" this is silent unless a prompt is actually needed.
export def Setup(forced: bool)
	if !InKitty()
		if forced
			echomsg 'kitty-scrollback.vim: Not running in kitty'
		endif
		return
	endif
	if InTmux()
		SetupTmux(forced)
		if KittyPid() == 0
			# The client's terminal is kitty, but not one on this machine
			if forced
				echomsg 'kitty-scrollback.vim: kitty runs on another machine, run :KittyScrollbackSetup there too'
			endif
			return
		endif
	endif
	SetupKitty(forced)
enddef

def SetupKitty(forced: bool)
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
	if !forced && filereadable(DeclinedFile('kitty'))
		return
	endif
	const choice = confirm($"kitty-scrollback.vim: Use Vim as kitty's (and tmux's) scrollback pager?\n"
		.. $"This sets scrollback_pager and maps {ScrollbackKeys(file)->join(', ')} in {fnamemodify(file, ':~')}.",
		"&Yes\n&No\nNever &ask again", 1, 'Question')
	if choice == 1
		Configure(file)
		delete(DeclinedFile('kitty'))
	elseif choice == 3
		mkdir(CacheDir(), 'p')
		writefile([], DeclinedFile('kitty'))
		echomsg 'kitty-scrollback.vim: Won''t ask again, use :KittyScrollbackSetup to configure it later'
	endif
enddef
