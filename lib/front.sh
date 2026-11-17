# shellcheck shell=bash
# Front: run this program on a remote server over one ssh connection. Runs on the
# operator's machine, so it keeps to bash 3.2 (macOS).

# sh_quote ARG: ARG in single quotes for a POSIX shell.
sh_quote() {
	local q="'\\''"
	printf "'%s'" "${1//\'/$q}"
}

# front_script ARGS...: the remote sh script. The program travels gzipped in base64 inside
# the command, so one connection carries everything and asks each password once; the
# temporary directory goes with the shell. For allow push FILE the list travels the same way.
front_script() {
	local payload list="" args="" arg sudo="sudo"
	payload="$(self_bundle | gzip -9 | base64 | tr -d '\n')" || exit 1
	if [ "$1" = allow ] && [ "${2:-}" = push ]; then
		[ -f "$3" ] || die "No such file: $3"
		list="$(base64 <"$3" | tr -d '\n')"
		[ ${#list} -le 24576 ] || die "List too large to send: $3 (keep it under 18 KB)"
		set -- allow push
		args=" allow push \"\$d/allow\""
	fi
	if [ -z "$list" ]; then
		for arg in "$@"; do args="$args $(sh_quote "$arg")"; done
	fi
	if [ ! -t 0 ]; then
		sudo='sudo -n true 2>/dev/null || { echo "sudo asks for a password: run from a terminal, or allow NOPASSWD sudo for $(id -un)" >&2; exit 1; }
  sudo -n'
	fi

	# shellcheck disable=SC2016 # These lines expand on the server.
	printf '%s\n' \
		'd=$(mktemp -d) || exit 1' \
		'trap '\''rm -rf "$d"'\'' EXIT' \
		'trap '\''exit 1'\'' HUP INT TERM' \
		"echo $payload | base64 -d | gunzip >\"\$d/geokordon\" || exit 1"
	if [ -n "$list" ]; then
		printf '%s\n' "echo $list | base64 -d >\"\$d/allow\" || exit 1"
	fi
	# shellcheck disable=SC2016 # These lines expand on the server.
	printf '%s\n' \
		'if [ "$(id -u)" = 0 ]; then' \
		"  bash \"\$d/geokordon\"$args" \
		'else' \
		"  $sudo bash \"\$d/geokordon\"$args" \
		'fi'
}

# front_run TARGET PORT ARGS...: TARGET goes to ssh as is, so aliases from ~/.ssh/config work.
front_run() {
	local target="$1" port="$2" ssh_args=() script
	shift 2
	# Built first: an empty command would open a login shell on the server.
	script="$(front_script "$@")" || exit 1
	[ -n "$script" ] || exit 1
	# A terminal lets sudo ask for its password; without one sudo -n fails with its own message.
	if [ -t 0 ]; then ssh_args+=(-t); else ssh_args+=(-T); fi
	if [ -n "$port" ]; then ssh_args+=(-p "$port"); fi
	# shellcheck disable=SC2029 # The script is built here on purpose.
	ssh "${ssh_args[@]}" "$target" "$script"
}
