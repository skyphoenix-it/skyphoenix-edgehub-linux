#!/usr/bin/env fish
# Build the Xeneon Edge Linux project
cd (dirname (status -f))/..
mkdir -p build
cd build
cmake ..; and make -j(nproc)
echo ""
echo "Build complete. Binary: "(pwd)"/xeneon-edge-hub"
