#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir=${BUILD_DIR:-.build-app}
[[ "$build_dir" == /* ]] || build_dir="$PWD/$build_dir"
./scripts/build.sh --helper-only
mkdir -p "$build_dir/Checks"
xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 \
  -module-cache-path "$build_dir/ModuleCache" \
  App/Shared/MonitorSupport.swift App/Shared/DDCSequence.swift \
  App/Tests/MonitorSupportChecks.swift -o "$build_dir/Checks/MonitorSupportChecks"
"$build_dir/Checks/MonitorSupportChecks"
xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 \
  -module-cache-path "$build_dir/ModuleCache" \
  App/Shared/CycleRunner.swift App/Tests/CycleRunnerChecks.swift \
  -o "$build_dir/Checks/CycleRunnerChecks"
"$build_dir/Checks/CycleRunnerChecks"
echo "Software checks passed; no monitor commands were sent."
