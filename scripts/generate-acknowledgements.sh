#!/bin/bash
#
# Writes the third-party license notice bundled into Overhear.app.
#
# Invoked by the GenerateAcknowledgements build tool plugin, which decides
# which packages ship and where their license files are; this script only
# concatenates. Running it by hand takes the same arguments the plugin passes:
#
#   generate-acknowledgements.sh <output> <preamble> [<name>TAB<version>TAB<url>TAB<license path>...]
#
set -euo pipefail

out="$1"
preamble="$2"
shift 2

mkdir -p "$(dirname "$out")"

rule() {
    printf '%s\n' "--------------------------------------------------------------------------------"
}

{
    cat "$preamble"

    for spec in "$@"; do
        # Tab-separated because a path can hold anything else. The first three
        # fields are the package; whatever follows is its license and notice
        # files, already ordered by the plugin.
        IFS=$'\t' read -ra fields <<< "$spec"
        name="${fields[0]}"
        version="${fields[1]}"
        url="${fields[2]}"
        files=("${fields[@]:3}")

        rule
        if [ -n "$version" ]; then
            printf '%s %s\n' "$name" "$version"
        else
            printf '%s\n' "$name"
        fi
        [ -n "$url" ] && printf '%s\n' "$url"
        rule
        printf '\n'

        for file in "${files[@]}"; do
            # Named so a reader can tell an Apache NOTICE from the license it
            # accompanies — §4(d) makes the two say different things.
            printf '%s:\n\n' "$(basename "$file")"
            cat "$file"
            printf '\n\n'
        done
    done
} > "$out"
