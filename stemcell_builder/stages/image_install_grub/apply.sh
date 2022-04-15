#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

disk_image=${work}/${stemcell_image_name}
image_mount_point=${work}/mnt

## unmap the loop device in case it's already mapped
#umount ${image_mount_point}/proc || true
#umount ${image_mount_point}/sys || true
#umount ${image_mount_point} || true
#losetup -j ${disk_image} | cut -d ':' -f 1 | xargs --no-run-if-empty losetup -d
kpartx -dv ${disk_image}

# note: if the above kpartx command fails, it's probably because the loopback device needs to be unmapped.
# in that case, try this: sudo dmsetup remove loop0p1

# Map partition in image to loopback
device=$(losetup --show --find ${disk_image})
add_on_exit "losetup --verbose --detach ${device}"

device_partition=$(kpartx -sav ${device} | grep "^add" | cut -d" " -f3)
add_on_exit "kpartx -dv ${device}"

loopback_dev="/dev/mapper/${device_partition}"

# Mount partition
image_mount_point=${work}/mnt
mkdir -p ${image_mount_point}

mount ${loopback_dev} ${image_mount_point}
add_on_exit "umount ${image_mount_point}"

# == Guide to variables in this script (all paths are defined relative to the real root dir, not the chroot)

# work: the base working directory outside the chroot
#      eg: /mnt/stemcells/aws/xen/centos/work/work
# disk_image: path to the stemcell disk image
#      eg: /mnt/stemcells/aws/xen/centos/work/work/aws-xen-centos.raw
# device: path to the loopback devide mapped to the entire disk image
#      eg: /dev/loop0
# loopback_dev: device node mapped to the main partition in disk_image
#      eg: /dev/mapper/loop0p1
# image_mount_point: place where loopback_dev is mounted as a filesystem
#      eg: /mnt/stemcells/aws/xen/centos/work/work/mnt

# Generate random password
random_password=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)

# Install bootloader
if [ -x ${image_mount_point}/usr/sbin/grub2-install ]; then # GRUB 2

  # GRUB 2 needs to operate on the loopback block device for the whole FS image, so we map it into the chroot environment
  touch ${image_mount_point}${device}
  mount --bind ${device} ${image_mount_point}${device}
  add_on_exit "umount ${image_mount_point}${device}"

  mkdir -p `dirname ${image_mount_point}${loopback_dev}`
  touch ${image_mount_point}${loopback_dev}
  mount --bind ${loopback_dev} ${image_mount_point}${loopback_dev}
  add_on_exit "umount ${image_mount_point}${loopback_dev}"

  # GRUB 2 needs /sys and /proc to do its job
  mount -t proc none ${image_mount_point}/proc
  add_on_exit "umount ${image_mount_point}/proc"

  mount -t sysfs none ${image_mount_point}/sys
  add_on_exit "umount ${image_mount_point}/sys"

  echo "(hd0) ${device}" > ${image_mount_point}/device.map

  # install bootsector into disk image file
  run_in_chroot ${image_mount_point} "grub2-install -v --no-floppy --grub-mkdevicemap=/device.map --target=i386-pc ${device}"

  # Enable password-less booting in openSUSE, only editing the boot menu needs to be restricted
  if [ -f ${image_mount_point}/etc/SuSE-release ]; then
    run_in_chroot ${image_mount_point} "sed -i 's/CLASS=\\\"--class gnu-linux --class gnu --class os\\\"/CLASS=\\\"--class gnu-linux --class gnu --class os --unrestricted\\\"/' /etc/grub.d/10_linux"

    cat >${image_mount_point}/etc/default/grub <<EOF
GRUB_CMDLINE_LINUX="vconsole.keymap=us net.ifnames=0 crashkernel=auto selinux=0 plymouth.enable=0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 audit=1 cgroup_enable=memory swapaccount=1"
EOF
  else
    cat >${image_mount_point}/etc/default/grub <<EOF
GRUB_CMDLINE_LINUX="vconsole.keymap=us net.ifnames=0 biosdevname=0 crashkernel=auto selinux=0 plymouth.enable=0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 audit=1"
EOF
  fi

  # we use a random password to prevent user from editing the boot menu
  pbkdf2_password=`run_in_chroot ${image_mount_point} "echo -e '${random_password}\n${random_password}' | grub2-mkpasswd-pbkdf2 | grep -Eo 'grub.pbkdf2.sha512.*'"`
  echo "\

cat << EOF
set superusers=vcap
password_pbkdf2 vcap $pbkdf2_password
EOF" >> ${image_mount_point}/etc/grub.d/00_header

  # assemble config file that is read by grub2 at boot time
  run_in_chroot ${image_mount_point} "GRUB_DISABLE_RECOVERY=true grub2-mkconfig -o /boot/grub2/grub.cfg"

  # set the correct root filesystem; use the ext2 filesystem's UUID
  device_uuid=$(dumpe2fs $loopback_dev | grep UUID | awk '{print $3}')
  sed -i s%root=${loopback_dev}%root=UUID=${device_uuid}%g ${image_mount_point}/boot/grub2/grub.cfg

  rm ${image_mount_point}/device.map

elif [[ "${DISTRIB_CODENAME}" == 'bionic' || ${DISTRIB_CODENAME} == 'jammy' ]]; then
  # Since bionic seems to have grub2 utilities named without the version number in the filename (e.g. grub-mkconfig instead of grub2-mkconfig)
  # it is a bit messy to try and reuse the logic that was introduced for
  # centos/suse at present. Using the DISTRIB_CODENAME instead of the
  # existence of a the grub2 utilities seems better for now? Not sure.
  # alternative: elif [[ "$("${image_mount_point}/usr/sbin/grub-install" -V)" =~ \ 2\.[0-9]{2} ]]; then # GRUB 2
  touch ${image_mount_point}${device}
  mount --bind ${device} ${image_mount_point}${device}
  add_on_exit "umount ${image_mount_point}${device}"

  mkdir -p `dirname ${image_mount_point}${loopback_dev}`
  touch ${image_mount_point}${loopback_dev}
  mount --bind ${loopback_dev} ${image_mount_point}${loopback_dev}
  add_on_exit "umount ${image_mount_point}${loopback_dev}"

  # GRUB 2 needs /sys and /proc to do its job
  mount -t proc none ${image_mount_point}/proc
  add_on_exit "umount ${image_mount_point}/proc"

  mount -t sysfs none ${image_mount_point}/sys
  add_on_exit "umount ${image_mount_point}/sys"

  echo "(hd0) ${device}" > ${image_mount_point}/device.map

  # install bootsector into disk image file
  run_in_chroot ${image_mount_point} "grub-install -v --no-floppy --grub-mkdevicemap=/device.map --target=i386-pc ${device}"

  # Enable password-less booting, only editing the boot menu needs to be restricted
  run_in_chroot ${image_mount_point} "sed -i 's/CLASS=\\\"--class gnu-linux --class gnu --class os\\\"/CLASS=\\\"--class gnu-linux --class gnu --class os --unrestricted\\\"/' /etc/grub.d/10_linux"

  grub_suffix=""
  case "${stemcell_infrastructure}" in
  aws)
    grub_suffix="nvme_core.io_timeout=4294967295"
    ;;
  cloudstack)
    grub_suffix="console=hvc0"
    ;;
  esac

  ## TODO: investigate why we need this fix https://github.com/systemd/systemd/issues/13477
  # fixes the monit helper script for finding the net_cls group see line stages/bosh_monit/moint-access-helper.sh:16
  CGROUP_FIX="systemd.unified_cgroup_hierarchy=false"

  cat >${image_mount_point}/etc/default/grub <<EOF
GRUB_CMDLINE_LINUX="vconsole.keymap=us net.ifnames=0 biosdevname=0 crashkernel=auto selinux=0 plymouth.enable=0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 ipv6.disable=1 audit=1 cgroup_enable=memory swapaccount=1 ${grub_suffix} ${CGROUP_FIX}"
EOF

  # we use a random password to prevent user from editing the boot menu
  pbkdf2_password=`run_in_chroot ${image_mount_point} "echo -e '${random_password}\n${random_password}' | grub-mkpasswd-pbkdf2 | grep -Eo 'grub.pbkdf2.sha512.*'"`
  echo "\
cat << EOF
set superusers=vcap
set root=(hd0,0)
password_pbkdf2 vcap $pbkdf2_password
EOF" >> ${image_mount_point}/etc/grub.d/00_header

  # assemble config file that is read by grub2 at boot time
  run_in_chroot ${image_mount_point} "GRUB_DISABLE_RECOVERY=true grub-mkconfig -o /boot/grub/grub.cfg"

  # set the correct root filesystem; use the ext2 filesystem's UUID
  device_uuid=$(dumpe2fs $loopback_dev | grep UUID | awk '{print $3}')
  sed -i s%root=${loopback_dev}%root=UUID=${device_uuid}%g ${image_mount_point}/boot/grub/grub.cfg

  rm ${image_mount_point}/device.map

fi # end of GRUB and GRUB 2 bootsector installation

# Figure out uuid of partition
uuid=$(blkid -c /dev/null -sUUID -ovalue ${loopback_dev})
kernel_version=$(basename $(ls -rt ${image_mount_point}/boot/vmlinuz-* |tail -1) |cut -f2-8 -d'-')

if [ -f ${image_mount_point}/etc/debian_version ] # Ubuntu
then
  initrd_file="initrd.img-${kernel_version}"
  os_name=$(source ${image_mount_point}/etc/lsb-release ; echo -n ${DISTRIB_DESCRIPTION})
  if [[ "${OS_TYPE}" == "ubuntu" ]]; then
    cat > ${image_mount_point}/etc/fstab <<FSTAB
# /etc/fstab Created by BOSH Stemcell Builder
UUID=${uuid} / ext4 defaults 1 1
FSTAB
  fi
elif [ -f ${image_mount_point}/etc/redhat-release ] # Centos or RHEL
then
  initrd_file="initramfs-${kernel_version}.img"
  os_name=$(cat ${image_mount_point}/etc/redhat-release)
  cat > ${image_mount_point}/etc/fstab <<FSTAB
# /etc/fstab Created by BOSH Stemcell Builder
UUID=${uuid} / ext4 defaults 1 1
FSTAB
elif [ -f ${image_mount_point}/etc/photon-release ] # PhotonOS
then
  initrd_file="initramfs-${kernel_version}.img"
  os_name=$(cat ${image_mount_point}/etc/photon-release)
  cat > ${image_mount_point}/etc/fstab <<FSTAB
# /etc/fstab Created by BOSH Stemcell Builder
UUID=${uuid} / ext4 defaults 1 1
FSTAB
elif [ -f ${image_mount_point}/etc/SuSE-release ] # openSUSE
then
  initrd_file="initramfs-${kernel_version}.img"
  os_name=$(cat ${image_mount_point}/etc/SuSE-release)
  cat > ${image_mount_point}/etc/fstab <<FSTAB
# /etc/fstab Created by BOSH Stemcell Builder
UUID=${uuid} / ext4 defaults 1 1
FSTAB
else
  echo "Unknown OS, exiting"
  exit 2
fi

if [[ "${DISTRIB_CODENAME}" == 'xenial'  ]] # Ubuntu
then
  cat > ${image_mount_point}/boot/grub/grub.cfg <<GRUB_CONF
default=0
timeout=1
title ${os_name} (${kernel_version})
  root (hd0,0)
  kernel /boot/vmlinuz-${kernel_version} ro root=UUID=${uuid} net.ifnames=0 biosdevname=0 selinux=0 cgroup_enable=memory swapaccount=1 console=ttyS0,115200n8 console=tty0 earlyprintk=ttyS0 rootdelay=300 ipv6.disable=1 audit=1
  initrd /boot/${initrd_file}
GRUB_CONF

elif [ -f ${image_mount_point}/etc/redhat-release ] # Centos or RHEL
then
  cat > ${image_mount_point}/boot/grub/grub.cfg <<GRUB_CONF
default=0
timeout=1
title ${os_name} (${kernel_version})
  root (hd0,0)
  kernel /boot/vmlinuz-${kernel_version} ro root=UUID=${uuid} net.ifnames=0 plymouth.enable=0 selinux=0 console=tty0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 ipv6.disable=1 audit=1
  initrd /boot/${initrd_file}
GRUB_CONF

elif [ -f ${image_mount_point}/etc/photon-release ] # PhotonOS
then
  cat > ${image_mount_point}/boot/grub/grub.cfg <<GRUB_CONF
default=0
timeout=1
title ${os_name} (${kernel_version})
  root (hd0,0)
  kernel /boot/vmlinuz-${kernel_version} ro root=UUID=${uuid} net.ifnames=0 plymouth.enable=0 selinux=0 console=tty0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 ipv6.disable=1 audit=1
  initrd /boot/${initrd_file}
GRUB_CONF

elif [ -f ${image_mount_point}/etc/SuSE-release ] # openSUSE
then
  cat > ${image_mount_point}/boot/grub/grub.cfg <<GRUB_CONF
default=0
timeout=1
title ${os_name} (${kernel_version})
  root (hd0,0)
  kernel /boot/vmlinuz-${kernel_version} ro root=UUID=${uuid} net.ifnames=0 plymouth.enable=0 selinux=0 console=tty0 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 ipv6.disable=1 audit=1
  initrd /boot/${initrd_file}
GRUB_CONF
fi

# For grub.cfg
if [ -f ${image_mount_point}/boot/grub/grub.cfg ];then
  sed -i "/timeout=/a password --md5 *" ${image_mount_point}/boot/grub/grub.cfg
  chown -fLR root:root ${image_mount_point}/boot/grub/grub.cfg
  chmod 600 ${image_mount_point}/boot/grub/grub.cfg
fi

# For CentOS, using grub 2, grub.cfg
if [ -f ${image_mount_point}/boot/grub2/grub.cfg ];then
  chown -fLR root:root ${image_mount_point}/boot/grub2/grub.cfg
  chmod 600 ${image_mount_point}/boot/grub2/grub.cfg
fi

run_in_chroot ${image_mount_point} "rm -f /boot/grub/menu.lst"
run_in_chroot ${image_mount_point} "ln -s ./grub.cfg /boot/grub/menu.lst"
