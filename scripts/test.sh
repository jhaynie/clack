#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
# CLT-only Macs lack XCTest. The realtime C engine can be tested directly.
clang -O1 -g -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I Sources/ClackAudio/include Sources/ClackAudio/ClackAudio.c \
    Tests/ClackAudioTests/mixer_tests.c -o .build/clack-tests
.build/clack-tests
