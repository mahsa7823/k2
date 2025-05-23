#!/usr/bin/env bash
#
set -ex

if [ -z $PYTHON_VERSION ]; then
  echo "Please set the environment variable PYTHON_VERSION"
  echo "Example: export PYTHON_VERSION=3.8"
  # Valid values: 3.6, 3.7, 3.8, 3.9, 3.10, 3.11
  exit 1
fi

if [ -z $TORCH_VERSION ]; then
  echo "Please set the environment variable TORCH_VERSION"
  echo "Example: export TORCH_VERSION=1.10.0"
  exit 1
fi

if [ -z $CUDA_VERSION ]; then
  echo "Please set the environment variable CUDA_VERSION"
  echo "Example: export CUDA_VERSION=10.2"
  # valid values: 10.2, 11.1, 11.3, 11.6, 11.7, 11.8, 12.1
  exit 1
fi

if [[ $TORCH_VERSION =~ 2.2.* && $CUDA_VERSION =~ 12.* ]]; then
  # see https://github.com/pytorch/pytorch/issues/113948
  export TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0"
fi

# python3 -m pip install scikit-build
python3 -m pip install -U pip cmake "numpy<=1.26.4"
python3 -m pip install wheel twine typing_extensions
python3 -m pip install bs4 requests tqdm auditwheel

echo "Installing torch"
./install_torch.sh

python3 -c "import torch; print(torch.__file__)"

sed -i.bak /9.0a/d /Python-*/py-3.*/lib/python3.*/site-packages/torch/share/cmake/Caffe2/Modules_CUDA_fix/upstream/FindCUDA/select_compute_arch.cmake || true

if [[ x"$IS_2_28" != x"1" ]]; then
  yum -y install openssl-devel
fi

yum -y install zlib-devel bzip2-devel libffi-devel xz-devel wget redhat-lsb-core

INSTALLED_PYTHON_VERSION=${PYTHON_VERSION}.2
if [[ $PYTHON_VERSION == "3.13" ]]; then
  INSTALLED_PYTHON_VERSION=${PYTHON_VERSION}.0
fi
echo "Installing $INSTALLED_PYTHON_VERSION"

curl -O https://www.python.org/ftp/python/$INSTALLED_PYTHON_VERSION/Python-$INSTALLED_PYTHON_VERSION.tgz
tar xf Python-$INSTALLED_PYTHON_VERSION.tgz
pushd Python-$INSTALLED_PYTHON_VERSION

PYTHON_INSTALL_DIR=$PWD/py-${PYTHON_VERSION}

if [[ $PYTHON_VERSION =~ 3.1. && x"$IS_2_28" != x"1" ]]; then
  yum install -y openssl11-devel
  sed -i 's/PKG_CONFIG openssl /PKG_CONFIG openssl11 /g' configure
fi

./configure --enable-shared --prefix=$PYTHON_INSTALL_DIR >/dev/null
make install >/dev/null

popd

export PATH=$PYTHON_INSTALL_DIR/bin:$PATH
export LD_LIBRARY_PATH=$PYTHON_INSTALL_DIR/lib:$LD_LIBRARY_PATH
ls -lh $PYTHON_INSTALL_DIR/lib/

python3 --version
which python3

rm -rf ~/.cache/pip >/dev/null 2>&1
yum clean all >/dev/null 2>&1

cd /var/www

export CMAKE_CUDA_COMPILER_LAUNCHER=

export CMAKE_CUDA_COMPILER_LAUNCHER=
# export K2_CMAKE_ARGS="-DCUDAToolkit_TARGET_DIR=/usr/local/cuda/targets/x86_64-linux -DPYTHON_EXECUTABLE=$PYTHON_INSTALL_DIR/bin/python3 "
export K2_CMAKE_ARGS="-DPYTHON_EXECUTABLE=$PYTHON_INSTALL_DIR/bin/python3 "
export K2_MAKE_ARGS=" -j2 "

python3 setup.py bdist_wheel
if [[ x"$IS_2_28" == x"1" ]]; then
  plat=manylinux_2_28_x86_64
else
  plat=manylinux_2_17_x86_64
fi
export PATH=$PYTHON_INSTALL_DIR/bin:$PATH
python3 --version
which python3

auditwheel --verbose repair \
  --exclude libc10.so \
  --exclude libc10_cuda.so \
  --exclude libcuda.so.1 \
  --exclude libcudart.so.${CUDA_VERSION} \
  --exclude libnvToolsExt.so.1 \
  --exclude libnvrtc.so.${CUDA_VERSION} \
  --exclude libtorch.so \
  --exclude libtorch_cpu.so \
  --exclude libtorch_cuda.so \
  --exclude libtorch_python.so \
  \
  --exclude libcublas.so \
  --exclude libcublas.so.11 \
  --exclude libcublas.so.12 \
  --exclude libcublasLt.so \
  --exclude libcublasLt.so.11 \
  --exclude libcublasLt.so.12 \
  --exclude libcudart.so.11.0 \
  --exclude libcudart.so.12 \
  --exclude libcudnn.so.8 \
  --exclude libcufft.so \
  --exclude libcufft.so.11 \
  --exclude libcupti.so \
  --exclude libcupti.so.12 \
  --exclude libcurand.so \
  --exclude libcurand.so.10 \
  --exclude libcusparse.so \
  --exclude libcusparse.so.12 \
  --exclude libnccl.so \
  --exclude libnccl.so.2 \
  --exclude libnvJitLink.so \
  --exclude libnvJitLink.so.12 \
  --exclude libnvrtc.so \
  --exclude libnvrtc.so.11.2 \
  --exclude libnvrtc.so.12 \
  --exclude libshm.so \
  --exclude libtorch_cuda_cpp.so \
  --exclude libtorch_cuda_cu.so \
  --plat $plat \
  -w /var/www/wheelhouse \
  dist/*.whl

ls -lh  /var/www
