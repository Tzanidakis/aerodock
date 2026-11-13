#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/behavior-tests
swiftc -module-cache-path .build/clang-cache Sources/AeroDock/Visibility.swift Tests/AeroDockTests/BehaviorTests.swift -o .build/behavior-tests/run
.build/behavior-tests/run
