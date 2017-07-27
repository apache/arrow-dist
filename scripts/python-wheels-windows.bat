@rem Licensed to the Apache Software Foundation (ASF) under one
@rem or more contributor license agreements.  See the NOTICE file
@rem distributed with this work for additional information
@rem regarding copyright ownership.  The ASF licenses this file
@rem to you under the Apache License, Version 2.0 (the
@rem "License"); you may not use this file except in compliance
@rem with the License.  You may obtain a copy of the License at
@rem
@rem   http://www.apache.org/licenses/LICENSE-2.0
@rem
@rem Unless required by applicable law or agreed to in writing,
@rem software distributed under the License is distributed on an
@rem "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
@rem KIND, either express or implied.  See the License for the
@rem specific language governing permissions and limitations
@rem under the License.

@echo on

conda update --yes --quiet conda

conda create -n arrow -q -y python=%PYTHON% ^
      six pytest setuptools numpy=%NUMPY% pandas cython

conda install -n arrow -q -y -c conda-forge ^
      flatbuffers rapidjson ^
      cmake git boost-cpp thrift-cpp gflags snappy zlib brotli zstd lz4-c

call activate arrow

set ARROW_SRC=C:\apache-arrow
mkdir %ARROW_SRC%
git clone https://github.com/apache/arrow.git %ARROW_SRC% || exit /B
pushd %ARROW_SRC%

@rem fix up symlinks
git config core.symlinks true
git reset --hard || exit /B
git checkout %pyarrow_commit% || exit /B

popd

set ARROW_HOME=%CONDA_PREFIX%\Library
set PARQUET_HOME=%CONDA_PREFIX%\Library
set ARROW_BUILD_TOOLCHAIN=%CONDA_PREFIX%\Library
set PARQUET_BUILD_TOOLCHAIN=%CONDA_PREFIX%\Library

@rem Build and test Arrow C++ libraries
mkdir %ARROW_SRC%\cpp\build
pushd %ARROW_SRC%\cpp\build

cmake -G "%GENERATOR%" ^
      -DCMAKE_INSTALL_PREFIX=%CONDA_PREFIX%\Library ^
      -DARROW_BOOST_USE_SHARED=OFF ^
      -DARROW_BUILD_TESTS=OFF ^
      -DCMAKE_BUILD_TYPE=Release ^
      -DARROW_CXXFLAGS="/MP" ^
      -DARROW_PYTHON=ON ^
      ..  || exit /B
cmake --build . --target INSTALL --config Release  || exit /B

@rem Needed so python-test.exe works
set PYTHONPATH=%CONDA_PREFIX%\Lib;%CONDA_PREFIX%\Lib\site-packages;%CONDA_PREFIX%\python35.zip;%CONDA_PREFIX%\DLLs;%CONDA_PREFIX%
ctest -VV  || exit /B
popd

@rem Build parquet-cpp
git clone https://github.com/apache/parquet-cpp.git || exit /B
pushd parquet-cpp
git checkout %parquet_commit%
popd

mkdir parquet-cpp\build
pushd parquet-cpp\build

cmake -G "%GENERATOR%" ^
     -DCMAKE_INSTALL_PREFIX=%PARQUET_HOME% ^
     -DCMAKE_BUILD_TYPE=Release ^
     -DPARQUET_BOOST_USE_SHARED=off ^
     -DPARQUET_BUILD_TESTS=off .. || exit /B
cmake --build . --target INSTALL --config Release || exit /B
popd

@rem Build and import pyarrow
set PYTHONPATH=

pushd %ARROW_SRC%\python
python setup.py build_ext --with-parquet --bundle-arrow-cpp bdist_wheel  || exit /B
popd

@rem test the wheel
call deactivate
conda create -n wheel-test -q -y python=%PYTHON% ^
      numpy=%NUMPY% pandas
call activate wheel-test

pip install --no-index --find-links=%ARROW_SRC%\python\dist\ pyarrow
python -c "import pyarrow; import pyarrow.parquet"
