#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "${BASH_SOURCE[0]}")"
cd "$ROOT"

if ! [[ -x "$ROOT/.luna/luna" ]]; then
    echo "Cloning luna..."
    if ! [[ -d .luna ]]; then
        git clone --depth 1 --branch v2.1 'https://github.com/ndless-nspire/Luna.git' .luna
    fi

    echo "Building luna..."
    make -C .luna
fi

"$ROOT/.luna/luna" "${1:-bundle.lua}" "${2:-rpn.tns}"
