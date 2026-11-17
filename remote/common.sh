# shellcheck shell=bash
# Helpers shared by the server-side commands.

# need_packages PACKAGE...: install the missing Debian/Ubuntu packages.
need_packages() {
	local missing=() package
	for package in "$@"; do
		dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y -qq "${missing[@]}" >/dev/null
	fi
}
