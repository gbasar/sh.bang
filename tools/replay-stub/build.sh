#!/usr/bin/env bash
# Compile ReplayStub.java into replay-stub.jar
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

javac ReplayStub.java
jar cfe replay-stub.jar ReplayStub ReplayStub.class
rm -f ReplayStub.class
echo "Built: $DIR/replay-stub.jar"
