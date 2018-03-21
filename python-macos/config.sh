#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -e

function build_wheel {
    echo `pwd`
    echo CFLAGS=${CFLAGS}
    echo CXXFLAGS=${CXXFLAGS}
    echo LDFLAGS=${LDFLAGS}
    pushd $1

    boost_version="1.65.0"
    boost_directory_name="boost_${boost_version//\./_}"
    boost_tarball_name="${boost_directory_name}.tar.gz"
    wget --no-check-certificate \
        http://downloads.sourceforge.net/project/boost/boost/"${boost_version}"/"${boost_tarball_name}" \
        -O "${boost_tarball_name}"
    tar xf "${boost_tarball_name}"

    pushd "${boost_directory_name}"

    ./bootstrap.sh

    # Arrow is 64-bit-only at the moment
    export CFLAGS="-fPIC -arch x86_64 ${CFLAGS//"-arch i386"/}"
    export CXXFLAGS="-fPIC -arch x86_64 ${CXXFLAGS//"-arch i386"}"

    ./bjam "cxxflags=${CXXFLAGS}" cflags="${CFLAGS}" --prefix=/usr/local --with-filesystem --with-date_time --with-system --with-regex install
    popd

    export ARROW_HOME=/usr/local
    export PARQUET_HOME=/usr/local
    pip install "cython==0.25.2" "numpy==${NP_TEST_DEP}"
    pushd cpp
    mkdir build
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=$ARROW_HOME \
          -DARROW_BUILD_TESTS=OFF \
          -DARROW_BUILD_SHARED=ON \
          -DARROW_BOOST_USE_SHARED=ON \
          -DARROW_JEMALLOC=OFF \
          -DARROW_PLASMA=ON \
          -DARROW_RPATH_ORIGIN=ON \
          -DARROW_JEMALLOC_USE_SHARED=OFF \
          -DARROW_PYTHON=ON \
          -DARROW_ORC=ON \
          -DMAKE=make \
          ..
    make -j5
    make install
    popd
    popd

    git clone https://github.com/apache/parquet-cpp.git
    pushd parquet-cpp
    mkdir build
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=$PARQUET_HOME \
          -DPARQUET_BUILD_TESTS=OFF \
          -DPARQUET_BOOST_USE_SHARED=ON \
          ..
    make -j5
    make install
    popd
    popd

    unset ARROW_HOME
    unset PARQUET_HOME
    export PYARROW_WITH_PARQUET=1
    export PYARROW_WITH_ORC=1
    export PYARROW_WITH_JEMALLOC=1
    export PYARROW_WITH_PLASMA=1
    export PYARROW_BUNDLE_BOOST=1
    export PYARROW_BUNDLE_ARROW_CPP=1
    export PYARROW_BUILD_TYPE='release'
    pushd python
    python setup.py build_ext \
           --with-plasma --with-orc --with-parquet \
	   --bundle-arrow-cpp --bundle-boost --boost-namespace=arrow_boost \
	   bdist_wheel
    ls -l dist/
    popd

    pip install "delocate==0.7.3"
    delocate-wheel -L . -v python/dist/*.whl
    popd
}
