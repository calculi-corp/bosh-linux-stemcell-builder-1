#!/bin/bash -eu

if [ -t 0 ]; then
  echo 'USAGE: $0 <<< extracted-image-directory'
  exit 2
fi

image_path=$(cat)
chroot=$(mktemp -d)

device=$(kpartx -sav ${image_path}/disk.raw | grep '^add' | cut -d' ' -f3)
sudo mount -o loop,rw "/dev/mapper/${device}" ${chroot}
echo $chroot
