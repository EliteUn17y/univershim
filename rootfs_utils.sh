#!/bin/bash

#patch the target rootfs to add any needed drivers

. ./common.sh
. ./image_utils.sh

make_directories() {
  rm -rf "${target_rootfs}/lib/modules"
  mkdir -p "${target_rootfs}/lib/firmware"
  mkdir -p "${target_rootfs}/lib/modprobe.d/"
  mkdir -p "${target_rootfs}/etc/modprobe.d/"
}

copy_modules() {
  local shim_rootfs=$(realpath -m $1)
  local reco_rootfs=$(realpath -m $2)
  local target_rootfs=$(realpath -m $3)

  cp -r --remove-destination "${shim_rootfs}/lib/modules/"* "${target_rootfs}/lib/modules/"*

  cp -r --remove-destination "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
  cp -r --remove-destination "${reco_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"

  cp -r --remove-destination "${reco_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/"
  cp -r --remove-destination "${reco_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/"
}

copy_firmware() {
  local firmware_path="/tmp/chromium-firmware"
  local target_rootfs=$(realpath -m $1)

  if [ ! -e "$firmware_path" ]; then
    download_firmware $firmware_path
  fi

  cp -r --remove-destination "${firmware_path}/"* "${target_rootfs}/lib/firmware/"
}

download_firmware() {
  local firmware_url="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local firmware_path=$(realpath -m $1)

  git clone --branch master --depth=1 "${firmware_url}" $firmware_path
}

extract_modules() {
  local target_rootfs=$(realpath -m $1)

  #decompress kernel modules if necessary - debian won't recognize these otherwise
  local compressed_files="$(find "${target_rootfs}/lib/modules" -name '*.gz')"
  if [ "$compressed_files" ]; then
    echo "$compressed_files" | xargs gunzip
    for kernel_dir in "$target_rootfs/lib/modules/"*; do
      local version="$(basename "$kernel_dir")"
      depmod -b "$target_rootfs" "$version"
    done
  fi
}