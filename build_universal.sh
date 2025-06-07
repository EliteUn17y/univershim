#!/bin/bash

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./build_universal.sh board_names"
  echo "Valid named arguments (specify with 'key=value'):"
  echo "  username     - Use a different username. This defaults to 'user'."
  echo "  password     - Use a different passsord. This defaults to 'user'."
  echo "  compress_img - Compress the final disk image into a zip file. Set this to any value to enable this option."
  echo "  rootfs_dir   - Use a different rootfs for the build. The directory you select will be copied before any patches are applied."
  echo "  quiet        - Don't use progress indicators which may clog up log files."
  echo "  desktop      - The desktop environment to install. This defaults to 'gnome'. Valid options include:"
  echo "                   gnome, xfce, kde, lxde, gnome-flashback, cinnamon, mate, lxqt"
  echo "  data_dir     - The working directory for the scripts. This defaults to ./data"
  echo "  arch         - The CPU architecture to build the shimboot image for. Set this to 'arm64' if you have an ARM Chromebook."
  echo "  release      - Set this to either 'bookworm', 'trixie', or 'unstable' to build for Debian 12, 13, or unstable."
  echo "  distro       - The Linux distro to use. This should be either 'debian', 'ubuntu', or 'alpine'."
  echo "  luks         - Set this argument to encrypt the rootfs partition."
}

assert_root
assert_args "$1"
parse_args "$@"

username="${args['username']-'user'}"
password="${args['password']-'user'}"
compress_img="${args['compress_img']}"
rootfs_dir="${args['rootfs_dir']}"
quiet="${args['quiet']}"
desktop="${args['desktop']-'gnome'}"
data_dir="${args['data_dir']}"
arch="${args['arch']-amd64}"
release="${args['release']}"
distro="${args['distro']-debian}"
luks="${args['luks']}"

positional_args=()

for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    positional_args+=("$arg")
  fi
done

#get board names like board1_board2_board3
joined=$(IFS=_; echo "${positional_args[*]}")

#get board bin paths like data/board1.bin data/board2.bin data/board3.bin
bin_paths=""
for board in "${positional_args[@]}"; do
  bin_paths+="data/shimboot_${board}.bin "
done

#trim trailing space
bin_paths="${bin_paths%% }"

#build boards
for arg in "$@"; do
    echo "building board $arg"
    ./build_board.sh $arg
done

print_title "downloading factory tools"
git clone https://chromium.googlesource.com/chromiumos/platform/factory data/factory

print_title "creating universal shim"
data/factory/setup/image_tool rma merge -i $bin_paths -o data/univershim_$joined.bin

print_title "building $distro rootfs"
if [ ! "$rootfs_dir" ]; then
  desktop_package="task-$desktop-desktop"
  rootfs_dir="$(realpath -m data/rootfs)"
  if [ "$(findmnt -T "$rootfs_dir/dev")" ]; then
    sudo umount -l $rootfs_dir/* 2>/dev/null || true
  fi
  rm -rf $rootfs_dir
  mkdir -p $rootfs_dir

  if [ "$distro" = "debian" ]; then
    release="${release:-bookworm}"
  elif [ "$distro" = "ubuntu" ]; then
    release="${release:-noble}"
  elif [ "$distro" = "alpine" ]; then
    release="${release:-edge}"
  else
    print_error "invalid distro selection"
    exit 1
  fi

  #install a newer debootstrap version if needed
  if [ -f "/etc/debian_version" ] && [ "$distro" = "ubuntu" -o "$distro" = "debian" ]; then
    if [ ! -f "/usr/share/debootstrap/scripts/$release" ]; then
      print_info "installing newer debootstrap version"
      mirror_url="https://deb.debian.org/debian/pool/main/d/debootstrap/"
      deb_file="$(curl "https://deb.debian.org/debian/pool/main/d/debootstrap/" | pcregrep -o1 'href="(debootstrap_.+?\.deb)"' | tail -n1)"
      deb_url="${mirror_url}${deb_file}"
      wget -q --show-progress "$deb_url" -O "/tmp/$deb_file"
      apt-get install -y "/tmp/$deb_file"
    fi
  fi

  ./build_rootfs.sh $rootfs_dir $release \
    custom_packages=$desktop_package \
    hostname=univershim \
    username=$username \
    user_passwd=$password \
    arch=$arch \
    distro=$distro
fi

print_title "patching $distro rootfs"
retry_cmd ./patch_rootfs.sh $shim_bin $reco_bin $rootfs_dir "quiet=$quiet"