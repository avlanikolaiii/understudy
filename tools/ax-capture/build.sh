#!/bin/sh
# Build the capture experiment tool.
set -e
cd "$(dirname "$0")"
swiftc -O -framework AppKit -framework ApplicationServices main.swift -o ax-capture
echo "Built tools/ax-capture/ax-capture"
