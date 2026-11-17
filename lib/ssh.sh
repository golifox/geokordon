# shellcheck shell=bash
# SSH side of geokordon: prompts, login by password or key, upload and run of remote/ as root.

ssh_prompt() {
	read -r -p "Server IP: " server
	[ -n "$server" ] || {
		echo "Server IP is required" >&2
		exit 1
	}
	read -r -p "SSH port [22]: " ssh_port
	ssh_port="${ssh_port:-22}"
	[[ "$ssh_port" =~ ^[0-9]+$ ]] || {
		echo "SSH port must be a number" >&2
		exit 1
	}
	read -r -p "SSH user [root]: " ssh_user
	ssh_user="${ssh_user:-root}"
	read -r -s -p "Password (empty for SSH keys): " password
	if [ -t 0 ]; then echo; fi
	target="$ssh_user@$server"
	ssh_opts=(-p "$ssh_port" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
}

# Password mode feeds the password to ssh through SSH_ASKPASS; key mode checks the login
# and passwordless sudo up front, so a failure explains its fix. The helper lives in
# WORK_DIR, which the caller removes on exit.
ssh_prepare() {
	if [ -n "$password" ]; then
		askpass="$WORK_DIR/askpass"
		# shellcheck disable=SC2016 # $GEOKORDON_PASSWORD expands when ssh runs the helper.
		printf '#!/bin/sh\nprintf "%%s\\n" "$GEOKORDON_PASSWORD"\n' >"$askpass"
		chmod 700 "$askpass"
		export GEOKORDON_PASSWORD="$password" SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
		return
	fi

	local check="true" status=0
	[ "$ssh_user" = root ] || check="sudo -n true"
	# shellcheck disable=SC2029 # The check command is built locally on purpose.
	ssh -n -o BatchMode=yes "${ssh_opts[@]}" "$target" "$check" 2>/dev/null || status=$?
	if [ "$status" = 255 ]; then
		cat >&2 <<EOF
Cannot log in to $target (port $ssh_port) with an SSH key.
Fix one of:
  - run again and enter the password;
  - add your key to the server: ssh-copy-id -p $ssh_port $target
EOF
		exit 1
	elif [ "$status" != 0 ]; then
		cat >&2 <<EOF
$ssh_user cannot run sudo without a password on $server.
Fix one of:
  - run again and enter the password of $ssh_user;
  - run again with SSH user root;
  - allow passwordless sudo, on the server:
      echo '$ssh_user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$ssh_user && sudo chmod 440 /etc/sudoers.d/$ssh_user
EOF
		exit 1
	fi
}

# ssh_run_remote DIR ARGS...: copy DIR to a temporary directory on the server and run its
# run.sh as root with the SSH port and ARGS. The copy goes first, so stdin of the second
# connection stays free for the sudo password.
ssh_run_remote() {
	local dir="$1" remote_dir run
	shift
	remote_dir="$(COPYFILE_DISABLE=1 tar -C "$dir" -czf - . |
		ssh "${ssh_opts[@]}" "$target" \
			'd=$(mktemp -d) && tar --warning=no-unknown-keyword -xzf - -C "$d" && echo "$d"')"
	run="bash $remote_dir/run.sh $ssh_port $*"

	# shellcheck disable=SC2029 # The command is built locally on purpose.
	if [ "$ssh_user" = root ]; then
		ssh -n "${ssh_opts[@]}" "$target" "$run"
	elif [ -n "$password" ]; then
		printf '%s\n' "$password" | ssh "${ssh_opts[@]}" "$target" "sudo -S -p '' $run"
	else
		ssh -n "${ssh_opts[@]}" "$target" "sudo -n $run"
	fi
}
