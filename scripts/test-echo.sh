#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

# shellcheck disable=SC2034
usage="Usage: $__name [options] <hello>
Prepare smth for smth

Arguments:
    hello - smth cool (e.g. \"blah\")
    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$hello"
    exit
fi

hello=$1

check_args hello

echo "$hello"