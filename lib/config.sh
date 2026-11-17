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

config_load() {
	COUNTRIES="$(config_get countries ru)"
	CONTAINERS="$(config_get containers '^amnezia')"
}

# config_check KEY VALUE: exit unless VALUE suits KEY.
config_check() {
	local status=0
	case "$1" in
	countries)
		[[ "$2" =~ ^[a-z]{2}(,[a-z]{2})*$ ]] || die "Countries are two-letter codes separated by commas: ru,by"
		;;
	containers)
		[[ -n "$2" && "$2" != *$'\n'* ]] || die "The container pattern is one line"
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
