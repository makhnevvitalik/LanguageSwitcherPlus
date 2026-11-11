#!/bin/bash
# SPDX-FileCopyrightText: 2026 Vitalik Makhnev
# SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
products="${1:?Pass the Xcode build products directory}"
fixture="$(mktemp -d "${TMPDIR:-/private/tmp}/lang-shortcut-editor-tests.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
cat "$project_root/App/Windows/TextShortcutEditorSheetController.swift" \
    "$project_root/Tests/ShortcutEditorKeyboardTests.swift" > "$fixture/ShortcutEditorKeyboardTests.swift"
swiftc "$project_root/App/Presentation/AppStyle.swift" \
    "$project_root/App/Presentation/TextActionPresentation.swift" \
    "$project_root/App/Windows/TextShortcutSettingsWindowController.swift" \
    "$fixture/ShortcutEditorKeyboardTests.swift" "$products"/*.o \
    -I "$products" -module-cache-path "$project_root/.build/editor-tests-module-cache" \
    -o "$fixture/tests" -framework AppKit -framework Carbon -framework IOKit -framework ServiceManagement
"$fixture/tests"
