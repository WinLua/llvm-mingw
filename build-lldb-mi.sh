#!/bin/sh
#
# Copyright (c) 2020 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -e

: ${LLDB_MI_VERSION:=a662be43bdfcc1654537ee9bfbf2677d5fbae95d}
BUILDDIR=build
unset HOST

while [ $# -gt 0 ]; do
    case "$1" in
    --host=*)
        HOST="${1#*=}"
        ;;
    *)
        PREFIX="$1"
        ;;
    esac
    shift
done
if [ -z "$PREFIX" ]; then
    echo $0 [--host=<triple>] dest
    exit 1
fi

mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

if [ ! -d lldb-mi ]; then
    git clone https://github.com/lldb-tools/lldb-mi.git
    CHECKOUT=1
fi

if [ -n "$SYNC" ] || [ -n "$CHECKOUT" ]; then
    cd lldb-mi
    [ -z "$SYNC" ] || git fetch
    git checkout $LLDB_MI_VERSION
    git am -3 ../patches/lldb-mi/*.patch
    cd ..
fi

if [ -n "$(which ninja)" ]; then
    CMAKE_GENERATOR="Ninja"
    NINJA=1
    BUILDCMD=ninja
else
    : ${CORES:=$(nproc 2>/dev/null)}
    : ${CORES:=$(sysctl -n hw.ncpu 2>/dev/null)}
    : ${CORES:=4}

    case $(uname) in
    MINGW*)
        CMAKE_GENERATOR="MSYS Makefiles"
        ;;
    *)
        ;;
    esac
    BUILDCMD=make
fi

if [ -n "$HOST" ]; then
    BUILDDIR=$BUILDDIR-$HOST

    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_SYSTEM_NAME=Windows"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CROSSCOMPILING=TRUE"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=$HOST-gcc"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=$HOST-g++"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_RC_COMPILER=$HOST-windres"

    CROSS_ROOT=$(cd $(dirname $(which $HOST-gcc))/../$HOST && pwd)
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH=$(pwd)/llvm-project/llvm/$BUILDDIR"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
fi

# This assumes llvm was built with a builddir with the same name. If llvm was
# built with e.g. --enable-asserts, it won't match.
export LLVM_DIR=$(pwd)/llvm-project/llvm/$BUILDDIR

cd lldb-mi

[ -z "$CLEAN" ] || rm -rf $BUILDDIR
mkdir -p $BUILDDIR
cd $BUILDDIR
cmake \
    ${CMAKE_GENERATOR+-G} "$CMAKE_GENERATOR" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    $CMAKEFLAGS \
    ..

$BUILDCMD ${CORES+-j$CORES} install/strip
