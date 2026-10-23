#!/bin/sh
set -eu
# Xcode's input/output paths grant access when script sandboxing is enabled.
source_file="$SCRIPT_INPUT_FILE_1"
output_file="$SCRIPT_OUTPUT_FILE_0"
if [ ! -s "$source_file" ]; then
    echo 'error: Personal connection is missing. Run node scripts/ios/setup-personal-connection.mjs in the repository root, then build again.' >&2
    exit 1
fi
if ! /usr/bin/plutil -lint -s "$source_file" >/dev/null 2>&1; then
    echo 'error: Personal connection configuration is invalid. Run the personal setup again.' >&2
    exit 1
fi
umask 077
mkdir -p "$(dirname "$output_file")"
cp "$source_file" "$output_file"
