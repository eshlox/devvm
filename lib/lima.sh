#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_lima_instance_exists() {
	local name
	name="$1"
	limactl list --format '{{.Name}}' 2>/dev/null | grep -Fxq "$name"
}

devvm_lima_require_instance() {
	local name
	name="$1"
	devvm_lima_instance_exists "$name" || devvm_die "Lima instance does not exist: $name"
}

devvm_port_forwards_block() {
	local ports port guest host
	ports="${PORTS:-}"
	if [ -z "$ports" ]; then
		printf 'portForwards: []\n'
		return 0
	fi

	printf 'portForwards:\n'
	for port in $ports; do
		guest="${port%%:*}"
		host="${port#*:}"
		if [ "$host" = "$port" ]; then
			host="$guest"
		fi
		case "$guest" in
		'' | *[!0-9]*) devvm_die "invalid guest port '$guest' in PORTS" ;;
		esac
		case "$host" in
		'' | *[!0-9]*) devvm_die "invalid host port '$host' in PORTS" ;;
		esac
		printf '  - guestPort: %s\n' "$guest"
		printf '    hostPort: %s\n' "$host"
		printf '    proto: tcp\n'
	done
}

devvm_port_forwards_json() {
	local ports port guest host first
	ports="${PORTS:-}"
	if [ -z "$ports" ]; then
		printf '[]'
		return 0
	fi

	first="1"
	printf '['
	for port in $ports; do
		guest="${port%%:*}"
		host="${port#*:}"
		if [ "$host" = "$port" ]; then
			host="$guest"
		fi
		case "$guest" in
		'' | *[!0-9]*) devvm_die "invalid guest port '$guest' in PORTS" ;;
		esac
		case "$host" in
		'' | *[!0-9]*) devvm_die "invalid host port '$host' in PORTS" ;;
		esac
		if [ "$first" = "0" ]; then
			printf ','
		fi
		first="0"
		printf '{"guestPort":%s,"hostPort":%s,"proto":"tcp"}' "$guest" "$host"
	done
	printf ']'
}

devvm_validate_mount_spec() {
	local spec host guest access extra
	spec="$1"
	IFS=: read -r host guest access extra <<EOF
$spec
EOF

	[ -z "${extra:-}" ] || devvm_die "invalid mount spec '$spec'; use host:guest[:ro|rw]"
	[ -n "$host" ] || devvm_die "invalid mount spec '$spec'; missing host path"
	[ -n "$guest" ] || devvm_die "invalid mount spec '$spec'; missing guest path"

	case "$host" in
	/*) ;;
	*) devvm_die "mount host path must be absolute: $host" ;;
	esac

	case "$guest" in
	/*) ;;
	*) devvm_die "mount guest path must be absolute: $guest" ;;
	esac

	case "${access:-rw}" in
	ro | rw) ;;
	*) devvm_die "mount access must be ro or rw in spec '$spec'" ;;
	esac

	case "$host" in
	/ | "$HOME" | "$HOME/" | "$HOME/." | "$HOME/.." | "$HOME"/..)
		devvm_die "refusing to mount broad host path: $host"
		;;
	esac

	case "$guest" in
	/ | /code | /code/* | "$DEVVM_GUEST_HOME" | "$DEVVM_GUEST_HOME"/* | /home | /home/* | /root | /etc | /usr | /var | /bin | /sbin | /lib | /lib64)
		devvm_die "refusing to mount over protected guest path: $guest"
		;;
	esac
}

devvm_mounts_block() {
	local spec host guest access writable
	if [ -z "${EFFECTIVE_MOUNTS:-}" ]; then
		printf 'mounts: []\n'
		return 0
	fi

	printf 'mounts:\n'
	for spec in $EFFECTIVE_MOUNTS; do
		devvm_validate_mount_spec "$spec"
		IFS=: read -r host guest access <<EOF
$spec
EOF
		devvm_ensure_dir "$host"
		writable="true"
		if [ "${access:-rw}" = "ro" ]; then
			writable="false"
		fi
		printf '  - location: %s\n' "$(devvm_json_string "$host")"
		printf '    mountPoint: %s\n' "$(devvm_json_string "$guest")"
		printf '    writable: %s\n' "$writable"
	done
}

devvm_mounts_json() {
	local spec host guest access writable first
	if [ -z "${EFFECTIVE_MOUNTS:-}" ]; then
		printf '[]'
		return 0
	fi

	first="1"
	printf '['
	for spec in $EFFECTIVE_MOUNTS; do
		devvm_validate_mount_spec "$spec"
		IFS=: read -r host guest access <<EOF
$spec
EOF
		devvm_ensure_dir "$host"
		writable="true"
		if [ "${access:-rw}" = "ro" ]; then
			writable="false"
		fi
		if [ "$first" = "0" ]; then
			printf ','
		fi
		first="0"
		printf '{"location":%s,"mountPoint":%s,"writable":%s}' \
			"$(devvm_json_string "$host")" \
			"$(devvm_json_string "$guest")" \
			"$writable"
	done
	printf ']'
}

devvm_lima_create_instance() {
	local mounts ports
	local -a cmd
	mounts="$(devvm_mounts_json)"
	ports="$(devvm_port_forwards_json)"

	cmd=(
		limactl create
		--name "$VM_NAME"
		--tty=false
		--set ".vmType=\"vz\""
		--set ".arch=$(devvm_json_string "$LIMA_ARCH")"
		--set ".cpus=$CPUS"
		--set ".memory=$(devvm_json_string "$MEMORY")"
		--set ".disk=$(devvm_json_string "$DISK")"
		--set ".user.name=$(devvm_json_string "$DEVVM_GUEST_USER")"
		--set ".user.home=$(devvm_json_string "$DEVVM_GUEST_HOME")"
		--set ".mountType=\"virtiofs\""
		--set ".mounts=$mounts"
		--set ".networks=[{\"vzNAT\":true}]"
		--set ".portForwards=$ports"
		--set ".containerd.system=false | .containerd.user=false"
		"$LIMA_TEMPLATE"
	)

	"${cmd[@]}"
}

devvm_render_lima_template() {
	local template output line mounts_block ports_block
	template="$1"
	output="$2"
	mounts_block="$(devvm_mounts_block)"
	ports_block="$(devvm_port_forwards_block)"

	devvm_ensure_dir "$(dirname "$output")"
	: >"$output"

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		*'{{ MOUNTS_BLOCK }}'*)
			printf '%s\n' "$mounts_block" >>"$output"
			continue
			;;
		*'{{ PORT_FORWARDS_BLOCK }}'*)
			printf '%s\n' "$ports_block" >>"$output"
			continue
			;;
		esac

		line="${line//\{\{ LIMA_TEMPLATE \}\}/$LIMA_TEMPLATE}"
		line="${line//\{\{ LIMA_ARCH \}\}/$LIMA_ARCH}"
		line="${line//\{\{ CPUS \}\}/$CPUS}"
		line="${line//\{\{ MEMORY \}\}/$MEMORY}"
		line="${line//\{\{ DISK \}\}/$DISK}"
		line="${line//\{\{ VM_NAME \}\}/$VM_NAME}"
		line="${line//\{\{ DEVVM_GUEST_USER \}\}/$DEVVM_GUEST_USER}"
		line="${line//\{\{ DEVVM_GUEST_HOME \}\}/$DEVVM_GUEST_HOME}"
		printf '%s\n' "$line" >>"$output"
	done <"$template"
}

devvm_render_project_yaml() {
	local output
	output="$DEVVM_GENERATED/$VM_NAME.yaml"
	devvm_render_lima_template "$DEVVM_CORE/templates/fedora-vm.yaml.tpl" "$output"
	printf '%s\n' "$output"
}

devvm_status() {
	devvm_require_command limactl
	limactl list "$@"
}

devvm_lima_version_major() {
	local version major
	version="$(limactl --version 2>/dev/null | sed -n 's/.*version[[:space:]]*//p' | awk '{print $1}')"
	major="${version%%.*}"
	case "$major" in
	'' | *[!0-9]*) return 1 ;;
	*) printf '%s\n' "$major" ;;
	esac
}
