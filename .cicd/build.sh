#!/bin/bash
set -eo pipefail
. ./.cicd/helpers/general.sh
mkdir -p $BUILD_DIR
CMAKE_EXTRAS="-DCMAKE_BUILD_TYPE='Release' -DCORE_SYMBOL_NAME='SYS'"
if [[ $(uname) == 'Darwin' ]]; then
    # You can't use chained commands in execute
    [[ $TRAVIS == true ]] && export PINNED=false && ccache -s && CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER_LAUNCHER=ccache" && ./$CICD_DIR/platforms/unpinned/$IMAGE_TAG.sh
    ( [[ ! $PINNED == false || $UNPINNED == true ]] ) && CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_TOOLCHAIN_FILE=$SCRIPTS_DIR/pinned_toolchain.cmake"
    if [[ "$USE_CONAN" == 'true' ]]; then
        sed -n '/## Build Steps/,/make -j/p' $CONAN_DIR/$IMAGE_TAG.md | grep -v -e '```' -e '^$' -e 'git' -e 'cd eos' >> $CONAN_DIR/conan-build.sh
        bash -c "$CONAN_DIR/conan-build.sh && cp -r ~/.conan $BUILD_DIR/conan"
    else
        cd $BUILD_DIR
        cmake $CMAKE_EXTRAS ..
        make -j$JOBS
    fi
else # Linux
    ARGS=${ARGS:-"--rm --init -v $(pwd):$MOUNTED_DIR -e UNPINNED -e PINNED -e IMAGE_TAG"}
    PRE_COMMANDS="cd $MOUNTED_DIR/build"
    # PRE_COMMANDS: Executed pre-cmake
    # CMAKE_EXTRAS: Executed within and right before the cmake path (cmake CMAKE_EXTRAS ..)
    [[ ! $IMAGE_TAG =~ 'unpinned' && ! $IMAGE_TAG =~ 'conan' ]] && CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_TOOLCHAIN_FILE=$MOUNTED_DIR/scripts/pinned_toolchain.cmake -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    if [[ $IMAGE_TAG == 'amazon_linux-2-pinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib64/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'centos-7.6-pinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && source /opt/rh/rh-python36/enable && export PATH=/usr/lib64/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'ubuntu-16.04-pinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'ubuntu-18.04-pinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'amazon_linux-2-unpinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib64/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++' -DCMAKE_C_COMPILER='clang'"
    elif [[ $IMAGE_TAG == 'centos-7.6-unpinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && source /opt/rh/devtoolset-8/enable && source /opt/rh/rh-python36/enable && export PATH=/usr/lib64/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DLLVM_DIR='/opt/rh/llvm-toolset-7.0/root/usr/lib64/cmake/llvm'"
    elif [[ $IMAGE_TAG == 'ubuntu-18.04-unpinned' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++-7' -DCMAKE_C_COMPILER='clang-7' -DLLVM_DIR='/usr/lib/llvm-7/lib/cmake/llvm'"
    elif [[ $IMAGE_TAG =~ 'conan' ]]; then
        sed -n '/## Build Steps/,/make -j/p' $CONAN_DIR/$IMAGE_TAG.md | grep -v -e '```' -e '^$' -e 'git' -e 'cd eos' >> $CONAN_DIR/conan-build.sh
    fi
    BUILD_COMMANDS="cmake $CMAKE_EXTRAS .. && make -j$JOBS"
    # Docker Commands
    if [[ $BUILDKITE == true ]]; then
        # Generate Base Images
        $CICD_DIR/generate-base-images.sh
        [[ $ENABLE_INSTALL == true ]] && COMMANDS="cp -r $MOUNTED_DIR /root/eosio && cd /root/eosio/build &&"
        COMMANDS="$COMMANDS $BUILD_COMMANDS"
        [[ $ENABLE_INSTALL == true ]] && COMMANDS="$COMMANDS && make install"
    elif [[ $TRAVIS == true ]]; then
        ARGS="$ARGS -v /usr/lib/ccache -v $HOME/.ccache:/opt/.ccache -e JOBS -e TRAVIS -e CCACHE_DIR=/opt/.ccache"
        COMMANDS="ccache -s && $BUILD_COMMANDS"
    fi
    . $HELPERS_DIR/file-hash.sh $CICD_DIR/platforms/$PLATFORM_TYPE/$IMAGE_TAG.dockerfile
    COMMANDS="$PRE_COMMANDS && $COMMANDS"
    [[ "$USE_CONAN" == 'true' ]] && COMMANDS="cd $MOUNTED_DIR && $MOUNTED_DIR/.conan/conan-build.sh && cp -r ~/.conan $MOUNTED_DIR/build/conan"
    echo "$ docker run $ARGS $(buildkite-intrinsics) $FULL_TAG bash -c \"$COMMANDS\""
    eval docker run $ARGS $(buildkite-intrinsics) $FULL_TAG bash -c \"$COMMANDS\"
fi