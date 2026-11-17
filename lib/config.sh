# shellcheck shell=bash
# config: blocked countries and the names of the VPN containers, in /etc/geokordon/config as
# key=value lines. Parsed, never sourced; without the file the defaults apply.

CONFIG_FILE=$ETC_DIR/config
COUNTRIES=ru
CONTAINERS='^amnezia'

# config_get KEY DEFAULT: the last value of KEY, or DEFAULT.
config_get() {
	local value
	value="$(sed -n "s/^$1=//p" "$CONFIG_FILE" 2>/dev/null | tail -n 1)"
	echo "${value:-$2}"
}

# config_load: the settings; a hand-edited value that would not pass config_check falls back
# to the default with a warning, so a typo never empties the geoblock.
config_load() {
	COUNTRIES="$(config_get countries ru)"
	CONTAINERS="$(config_get containers '^amnezia')"
	if ! (config_check countries "$COUNTRIES") 2>/dev/null; then
		echo "bad countries=$COUNTRIES in $CONFIG_FILE, using ru" >&2
		COUNTRIES=ru
	fi
	if ! (config_check containers "$CONTAINERS") 2>/dev/null; then
		echo "bad containers=$CONTAINERS in $CONFIG_FILE, using ^amnezia" >&2
		CONTAINERS='^amnezia'
	fi
}

# config_check KEY VALUE: exit unless VALUE suits KEY.
config_check() {
	local status=0
	case "$1" in
	countries)
		[[ "$2" =~ ^[a-z]{2}(,[a-z]{2})*$ ]] || die "Countries are two-letter codes separated by commas: ru,by"
		;;
	containers)
		[[ -n "$2" && "$2" != *$'\n'* && "$2" != -* ]] || die "The container pattern is one line and does not start with -"
		# grep -E exits 2 on a broken pattern, 1 on no match.
		grep -E -- "$2" </dev/null || status=$?
		[ "$status" -le 1 ] || die "Not an extended regular expression: $2"
		;;
	esac
}

# config_set KEY VALUE: replace or add the line of KEY.
config_set() {
	mkdir -p "$ETC_DIR"
	{
		grep -v "^$1=" "$CONFIG_FILE" 2>/dev/null || true
		echo "$1=$2"
	} >"$CONFIG_FILE.new"
	mv "$CONFIG_FILE.new" "$CONFIG_FILE"
}

# config_containers_match RE: exit when Docker has containers and none matches RE: a typo
# would close the VPN ports at once.
config_containers_match() {
	local names name
	command -v docker >/dev/null || return 0
	names="$(docker ps -a --format '{{.Names}}')" || die "Docker does not answer"
	[ -n "$names" ] || return 0
	for name in $names; do
		if [[ "$name" =~ $1 ]]; then return 0; fi
	done
	die "No container matches $1; containers here: $(echo "$names" | paste -sd ' ' -)"
}

config_print() {
	echo "countries=$COUNTRIES"
	echo "containers=$CONTAINERS"
}

cmd_config() {
	if [ $# = 0 ]; then
		config_print
		return
	fi
	need_installed
	config_check "$1" "$2"
	if [ "$1" = containers ]; then config_containers_match "$2"; fi
	# If the update fails, the config goes back as it was, like the direct list.
	touch "$CONFIG_FILE"
	cp -p "$CONFIG_FILE" "$CONFIG_FILE.old"
	trap 'mv -f "$CONFIG_FILE.old" "$CONFIG_FILE"; echo "config left as it was" >&2' EXIT
	config_set "$1" "$2"
	config_load
	update_apply
	trap - EXIT
	rm -f "$CONFIG_FILE.old"
	config_print
}
