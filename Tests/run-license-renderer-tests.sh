#!/bin/bash
# SPDX-FileCopyrightText: 2026 Vitalik Makhnev
# SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/private/tmp}/lang-license-renderer-tests.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
swiftc "$project_root/App/Presentation/AppStyle.swift" \
    "$project_root/App/Presentation/LicenseDocumentRenderer.swift" \
    "$project_root/Tests/LicenseDocumentRendererTests.swift" \
    -module-cache-path "$fixture/module-cache" -o "$fixture/tests" -framework AppKit
"$fixture/tests" "$project_root"
