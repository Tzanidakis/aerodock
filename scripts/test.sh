#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/behavior-tests
swiftc -module-cache-path .build/clang-cache Sources/AeroDock/Visibility.swift Sources/AeroDock/RecordingFiles.swift Sources/AeroDock/Presentation.swift Sources/AeroDock/Artwork.swift Tests/AeroDockTests/BehaviorTests.swift -o .build/behavior-tests/run
.build/behavior-tests/run
