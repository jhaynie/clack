#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
clang -O3 -std=c11 -I Sources/ClackAudio/include Sources/ClackAudio/ClackAudio.c scripts/benchmark.c -o .build/clack-benchmark
.build/clack-benchmark
