#!/usr/bin/env bash

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

RED=$(tput setaf 1)
RESET=$(tput sgr0)

fatal() {
	if test -t 1; then
		echo "${RED}fatal:$RESET $*" 1>&2
	else
		echo "fatal: $*" 1>&2
	fi
}

check_root_uid() {
    [ $UID -eq 0 ] || {
        fatal "$(basename "$0") needs to be run as root (uid=0) only"
        exit 1
    }
}

check_args() {
    [ -n "$usage" ] || {
        fatal "\"usage\" variable must be set"
        exit 1
    }

    for arg in "$@"; do
        [ -n "${!arg}" ] || {
            echo "$usage"
            fatal "$arg is required"
            exit 1
        }
    done
}

check_stream() {
    local stream=$1
    local repo_root=$2

    local output=

    output="$(python3 "$__dir"/../stream.py "$stream" "$repo_root" 2>&1)" || {
        fatal "$output"
        exit 1
    }
}

export_stream() {
    local stream=$1
    local repo_root=$2
    local mode=${3:-bare}

    output="$(python3 "$__dir"/../stream.py "$stream" "$repo_root" --mode "$mode" 2>&1)" || {
        fatal "$output"
        exit 1
    }

    eval "$output"
}

handle_options() {
    [ -n "$usage" ] || {
        fatal "\"usage\" variable must be set"
        exit 1
    }

    [ -n "$need_api" ] || {
        fatal "\"need_api\" variable must be set"
        exit 1
    }

    # shellcheck disable=SC2154
    valid_args=$(getopt -o 'ah' --long 'api,help' --name "$__name" -- "$@")
    eval set -- "$valid_args"

    while true ; do
        case "$1" in
            -a|--api)
                need_api=1
                shift
                break;;
            -h|--help)
                echo "$usage"
                exit;;
            --)
                shift
                break;;
        esac
    done
}

get_apt_repo_namespace() {
    local branch=$1
    local ns=alt
    if [ "$branch" != sisyphus ]; then
        ns="$branch"
    fi
    echo "$ns"
}

get_apt_repo_branch() {
    local branch=$1
    local repo_branch=Sisyphus

    if [ "$branch" != sisyphus ]; then
        repo_branch="$branch/branch"
    fi
    echo "$repo_branch"
}

get_apt_repo_arch() {
    local arch=$1
    case "$arch" in
        x86_64)
            echo 64;;
        -)
            fatal "Architecture \"$arch\" not allowed."
            exit 1
    esac
}

# Split passwd file (/etc/passwd) into
# /usr/etc/passwd - home users password file (uid >= 500)
# /lib/passwd - system users password file (uid < 500)
split_passwd() {
    local from_pass=$1
    local sys_pass=$2
    local user_pass=$3

    touch "$sys_pass"
    touch "$user_pass"

    set -f

    local ifs=$IFS

    exec < "$from_pass"
    while read -r line
    do
        IFS=:
		# shellcheck disable=SC2086
		set -- $line
		IFS=$ifs

        user=$1
        uid=$3

        if [[ $uid -ge 500 || $user = "root" || $user = "systemd-network" ]]
        then
            echo "$line" >> "$user_pass"
        else
            echo "$line" >> "$sys_pass"
        fi
    done
}

# Split group file (/etc/group) into
# /usr/etc/group - home users group file (uid >= 500)
# /lib/group - system users group file (uid < 500)
split_group() {
    local from_group=$1
    local sys_group=$2
    local user_group=$3

    touch "$sys_group"
    touch "$user_group"

    set -f

    local ifs=$IFS

    exec < "$from_group"
    while read -r line
    do
        IFS=:
		# shellcheck disable=SC2086
		set -- $line
		IFS="$ifs"

        user=$1
        uid=$3
        if [[ $uid -ge 500 ||
              $user = "root" ||
              $user = "adm" ||
              $user = "wheel" ||
              $user = "systemd-network" ||
              $user = "systemd-journal" ||
              $user = "docker" ]]
        then
            echo "$line" >> "$user_group"
        else
            echo "$line" >> "$sys_group"
        fi
    done
}

get_ostree_dir() {
	local stream=$1
	local repo_root=$2
	local mode=$3

	(
		eval "$(export_stream "$stream" "$repo_root")"
		ostree_dir="$OSTREE_BARE_DIR"
		if [ "$mode" = "archive" ]; then
			ostree_dir="$OSTREE_ARCHIVE_DIR"
		fi
		echo "$ostree_dir"
	)
}

is_base_stream() {
	local name=$1

	if [ "$name" == "base" ]; then
		echo "yes"
		return
	fi
	echo "no"
}

get_commit() {
	local stream=$1
	local repo_root=$2
	local mode=$3
	local commit=$4

	(
		export_stream "$stream" "$repo_root" "$mode"

		if [ "$commit" = "latest" ]; then
            set +e
			python3 "$__dir"/../stream.py \
				"$stream" \
				"$repo_root" \
				--mode "$mode" \
				commit 2>/dev/null
            set -e
		else
			echo "$commit"
		fi
	)
}

check_artifact() {
	local platform=$1
	local format=$2

	python3 -c "from altcos import *; ALLOWED_BUILDS[\"$platform\"][\"$format\"]" 2>/dev/null || {
		fatal "unallowed artifact :: platform: \"$platform\", format: \"$format\""
        exit 1
    }
}

get_artifact_dir() {
	local stream=$1
	local repo_root=$2
	local version=$3
	local platform=$4
	local format=$5
	local storage=$6

	check_artifact "$platform" "$format"

	(
		eval "$(export_stream "$stream" "$repo_root")"

		# shellcheck disable=2153
		echo "$storage"/"$BRANCH"/"$ARCH"/"$NAME"/"$version"/"$platform"/"$format"
	)
}

prepare_apt_dirs() {
	local root_dir=$1

	sudo mkdir -p \
		"$root_dir"/var/lib/apt/lists/partial \
		"$root_dir"/var/cache/apt/archives/partial \
		"$root_dir"/var/cache/apt/gensrclist \
		"$root_dir"/var/cache/apt/genpkglist

	sudo chmod -R 770 "$root_dir"/var/cache/apt
	sudo chmod -R g+s "$root_dir"/var/cache/apt
	sudo chown root:rpm "$root_dir"/var/cache/apt
}

require_envs() {
    local failed=false
    for env in "$@"
    do
        if [ -z "${!env}" ]
        then
            fatal "Environment variable \"$env\" is not set."
            failed=true
        fi
    done

    if $failed; then exit 1; fi
}

# with_password() {
#     shopt -s expand_aliases
#     require_envs PASSWORD
#     # shellcheck disable=SC2139
#     alias sudo="sudo -S <<< $PASSWORD 2>/dev/null"
# }
