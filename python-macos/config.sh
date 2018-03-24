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
    pip install -U pip
    pip install setuptools_scm
    echo `pwd`
    export PATH="/usr/local/opt/flex/bin:/usr/local/opt/bison/bin:$PATH"
    echo CFLAGS=${CFLAGS}
    echo CXXFLAGS=${CXXFLAGS}
    echo LDFLAGS=${LDFLAGS}
    pushd $1

    boost_version="1.65.1"
    boost_directory_name="boost_${boost_version//\./_}"
    boost_tarball_name="${boost_directory_name}.tar.gz"
    wget --no-check-certificate \
        http://downloads.sourceforge.net/project/boost/boost/"${boost_version}"/"${boost_tarball_name}" \
        -O "${boost_tarball_name}"
    tar xf "${boost_tarball_name}"

    arrow_boost="$PWD/arrow_boost"
    arrow_boost_dist="$PWD/arrow_boost_dist"
    mkdir "$arrow_boost" "$arrow_boost_dist"
    pushd "${boost_directory_name}"

    # Arrow is 64-bit-only at the moment
    export CFLAGS="-fPIC -arch x86_64 ${CFLAGS//"-arch i386"/}"
    export CXXFLAGS="-fPIC -arch x86_64 ${CXXFLAGS//"-arch i386"} -std=c++11"

    ./bootstrap.sh
    ./b2 tools/bcp > /dev/null 2>&1
    ./dist/bin/bcp --namespace=arrow_boost --namespace-alias \
        filesystem date_time system regex build algorithm locale format \
	"$arrow_boost" > /dev/null 2>&1

    popd
    pushd "$arrow_boost"
    ./bootstrap.sh
    ./bjam cxxflags="${CXXFLAGS}" \
        linkflags="-std=c++11" \
        cflags="${CFLAGS}" \
        variant=release \
        link=shared \
        --prefix="$arrow_boost_dist" \
        --with-filesystem --with-date_time --with-system --with-regex \
        install > /dev/null 2>&1
    popd

    export THRIFT_HOME=/usr/local
    export THRIFT_VERSION=0.11.0
    wget http://archive.apache.org/dist/thrift/${THRIFT_VERSION}/thrift-${THRIFT_VERSION}.tar.gz
    tar xf thrift-${THRIFT_VERSION}.tar.gz
    pushd thrift-${THRIFT_VERSION}
    mkdir build-tmp
    pushd build-tmp
    cmake -DCMAKE_BUILD_TYPE=release \
        "-DCMAKE_CXX_FLAGS=-fPIC" \
        "-DCMAKE_C_FLAGS=-fPIC" \
        "-DCMAKE_INSTALL_PREFIX=${THRIFT_HOME}" \
        "-DCMAKE_INSTALL_RPATH=${THRIFT_HOME}/lib" \
        "-DBUILD_SHARED_LIBS=OFF" \
        "-DBUILD_TESTING=OFF" \
        "-DWITH_QT4=OFF" \
        "-DWITH_C_GLIB=OFF" \
        "-DWITH_JAVA=OFF" \
        "-DWITH_PYTHON=OFF" \
        "-DWITH_CPP=ON" \
        "-DWITH_STATIC_LIB=ON" \
        "-DWITH_LIBEVENT=OFF" \
        -DBoost_NAMESPACE=arrow_boost \
        -DBOOST_ROOT="$arrow_boost_dist" \
        ..
    make install -j5
    popd
    popd

    export ARROW_HOME=/usr/local
    export PARQUET_HOME=/usr/local
    pip install "cython==0.27.3" "numpy==${NP_TEST_DEP}"
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
          -DBOOST_ROOT="$arrow_boost_dist" \
          -DBoost_NAMESPACE=arrow_boost \
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
          -DPARQUET_VERBOSE_THIRDPARTY_BUILD=ON \
          -DPARQUET_BUILD_TESTS=OFF \
          -DPARQUET_BOOST_USE_SHARED=ON \
          -DBoost_NAMESPACE=arrow_boost \
          -DBOOST_ROOT="$arrow_boost_dist" \
          ..
    make -j5 VERBOSE=1
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
    export PYARROW_CMAKE_OPTIONS="-DBOOST_ROOT=$arrow_boost_dist"
    export SETUPTOOLS_SCM_PRETEND_VERSION=$PYARROW_VERSION
    pushd python
    python setup.py build_ext \
           --with-plasma --with-orc --with-parquet \
           --bundle-arrow-cpp --bundle-boost --boost-namespace=arrow_boost \
           bdist_wheel
    ls -l dist/
    for wheel in dist/*.whl; do
	unzip -l "$wheel"
    done
    popd
    popd
}
