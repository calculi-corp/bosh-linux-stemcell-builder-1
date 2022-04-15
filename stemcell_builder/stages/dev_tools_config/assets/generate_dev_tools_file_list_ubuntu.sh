#!/usr/bin/env bash

declare -a PACKAGES

PACKAGES=( \
  binutils \
  bison \
  build-essential \
  cmake \
  cpp \
  debhelper \
  dkms \
  dpkg-dev \
  flex \
  g++ \
  gcc \
  gettext \
  intltool-debian \
  libmpc3 \
  make \
  patch \
  po-debconf \
  cpp-5 \
  cpp-7 \
  cpp-8 \
  cpp-9 \
  cpp-10 \
  cpp-11 \
  g++-5 \
  g++-7 \
  gcc-5 \
  gcc-6 \
  gcc-7 \
  gcc-8 \
  gcc-8 \
  gcc-10 \
  gcc-11 \
  gcc-5-base \
  gcc-6-base \
  gcc-7-base \
  gcc-8-base \
  gcc-9-base \
  gcc-10-base \
  gcc-11-base
)

if [[ "$1" == 'ubuntu' ]]; then
  PACKAGES+=(cpp-5 g++-5 gcc-5 gcc-5-base gcc-6-base)
else
  PACKAGES+=(cpp-4.8 g++-4.8 gcc-4.8)
fi

for package_name in ${PACKAGES[*]} ; do
  dpkg-query -L "$package_name" | xargs file | grep -Ev ':\s+directory\s*$|:\s+symbolic link to usr/lib\s*$' | awk -F ':' '{ print $1 }'
done
