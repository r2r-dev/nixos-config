main() {

set -e
scriptlocation="$(dirname $(readlink -f $0))"

writeColor() {
  echo -e $3 "\e[40;1;$1m$2\e[0m"
}

informNotOk() {
  writeColor 31 "$1" "$2"
}

informOk() {
  writeColor 32 "$1" "$2"
}

fail() {
    informNotOk "Something went wrong, starting interactive shell..."
    exec setsid bash
}

trap 'fail' 0 ERR TERM INT

echo
informOk "<<< NixOS fully automated install >>>"
echo

## Bail out early if /installer is incomplete
if [ ! -d /installer ]; then
    informNotOk "Directory /installer missing"
    exit 1
fi

installImg=/installer/nixos-image
if [ ! -f $installImg ]; then
    informotOk "$installImg missing"
    exit 1
fi

export HOME=/root
cd ${HOME}

### Source configuration
interface=$(ip route list match default | awk '{print $5}')
mac_address=$(ip link show $interface | grep ether | awk '{print $2}')

informOk "Parsing custom configuration..."
try_config () {
    file=/installer/$1
    informOk "Trying $file..." -n
    if [ -f $file ]; then
        informOk "loading"
        . $file
    else
        informOk "not present"
    fi
}
try_config config-$ipv4Address
try_config config-$mac_address
try_config config
informOk "...custom configuration done"

#TODO: bail out on missing conf

informOk "Installing NixOS on device $rootDevice"

## The actual command is below the comment block.
# we will create a new GPT table
#
# o:     create new GPT table
#     y: confirm creation
#
# with the new partition table,
# we now create the EFI partition
#
# n:     create new partion
#     1: partition number
#    2048: start position
#   +300M: make it 300MB big
#    ef00: set an EFI partition type
#
# With the EFI partition, we
# use the rest of the disk for LUKS
#
# n:     create new partition
#     2: partition number
#   <empty>: start partition right after first
#   <empty>: use all remaining space
#    8300: set generic linux partition type
#
# We only need to set the partition labels
#
# c:     change partition label
#     1: partition to label
#   nixboot: name of the partition
# c:     change partition label
#     2: partition to label
# cryptroot: name of the partition
#
# w:   write changes and quit
#     y: confirm write

informOk "Setting up partition table"
# TODO(m013411): randomize labels
rm -rf /dev/disk/by-partlabel/nixboot
rm -rf /dev/disk/by-partlabel/cryptroot
gdisk ${rootDevice} >/dev/null <<end_of_commands
o
y
n
1
2048
+300M
ef00
n
2


8300
c
1
nixboot
c
2
cryptroot
w
y
end_of_commands

# check for the newly created partitions
# this sometimes gives unrelated errors
# so we change it to  `partprobe || true`
partprobe "${rootDevice}" >/dev/null || true

# wait for label to show up
while [[ ! -e /dev/disk/by-partlabel/nixboot ]];
do
  sleep 2;
done

# wait for label to show up
while [[ ! -e /dev/disk/by-partlabel/cryptroot ]];
do
  sleep 2;
done

# check if both labels exist
ls /dev/disk/by-partlabel/nixboot   >/dev/null
ls /dev/disk/by-partlabel/cryptroot >/dev/null

## format the EFI partition
informOk "Formatting EFI partition"
mkfs.vfat /dev/disk/by-partlabel/nixboot

# temporary keyfile, will be removed (8k, ridiculously large)
dd if=/dev/urandom of=/tmp/keyfile bs=1k count=8

informOk "Formatting root partiton"
# formats the partition with luks and adds the temporary keyfile.
echo "YES" |                                             \
  cryptsetup luksFormat /dev/disk/by-partlabel/cryptroot \
  --key-size 512                                         \
  --hash sha512                                          \
  --key-file /tmp/keyfile

informOk "Encrypting root partiton"
echo "${rootDevicePass}" |                                 \
  cryptsetup luksAddKey /dev/disk/by-partlabel/cryptroot \
  --key-file /tmp/keyfile

# mount the cryptdisk at /dev/mapper/nixroot
cryptsetup \
  luksOpen /dev/disk/by-partlabel/cryptroot nixroot -d /tmp/keyfile

# remove the temporary keyfile
cryptsetup \
  luksRemoveKey /dev/disk/by-partlabel/cryptroot /tmp/keyfile

rm -f /tmp/keyfile

## the actual zpool create is below
#
# zpool create    \
# -O atime=on     \ #
# -O relatime=on    \ # only write access time (requires atime, see man zfs)
# -O compression=lz4  \ # compress all the things! (man zfs)
# -O snapdir=visible  \ # ever so sligthly easier snap management (man zfs)
# -O xattr=sa     \ # selinux file permissions (man zfs)
# -o ashift=12    \ # 4k blocks (man zpool)
# -o altroot=/mnt   \ # temp mount during install (man zpool)
# rpool         \ # new name of the pool
# /dev/mapper/nixroot   # devices used in the pool (in my case one, so no mirror or raid)
informOk "Setting up zfs filesystem"
zpool create          \
  -O atime=on         \
  -O relatime=on      \
  -O compression=lz4  \
  -O snapdir=visible  \
  -O xattr=sa         \
  -o ashift=12        \
  -o altroot=/mnt     \
  rpool               \
  /dev/mapper/nixroot

# dataset for / (root)
zfs create -o mountpoint=none   rpool/root
zfs create -o mountpoint=legacy rpool/root/nixos
zfs create -o mountpoint=legacy rpool/etc
zfs create -o mountpoint=legacy rpool/nix
zfs create -o mountpoint=legacy rpool/tmp
zfs create -o mountpoint=legacy rpool/home
zfs create -o mountpoint=legacy rpool/srv
zfs create -o mountpoint=legacy rpool/docker

# dataset for swap
zfs create -o compression=off -V 8G rpool/swap
mkswap -L SWAP /dev/zvol/rpool/swap
swapon /dev/zvol/rpool/swap

# mount the root dataset at /mnt
mount -t zfs rpool/root/nixos /mnt

# create mountpoints
mkdir -p /mnt/etc
mkdir -p /mnt/nix
mkdir -p /mnt/tmp && chmod 777 /mnt/tmp
mkdir -p /mnt/home
mkdir -p /mnt/srv

mount -t zfs rpool/etc /mnt/etc
mount -t zfs rpool/nix /mnt/nix
mount -t zfs rpool/tmp /mnt/tmp
mount -t zfs rpool/home /mnt/home
mount -t zfs rpool/srv /mnt/srv

# mount EFI partition at future /boot
mkdir -p /mnt/boot
mount /dev/disk/by-partlabel/nixboot /mnt/boot

# set boot filesystem
zpool set bootfs=rpool/root/nixos rpool

# reserve place for deletions
zfs set reservation=1G rpool

# configure snapshots
zfs set com.sun:auto-snapshot=true rpool
zfs set com.sun:auto-snapshot=true rpool/etc
zfs set com.sun:auto-snapshot=true rpool/home
zfs set com.sun:auto-snapshot:monthly=false rpool/home
zfs set com.sun:auto-snapshot=true rpool/srv
zfs set com.sun:auto-snapshot=false rpool/nix

informOk "Installing NixOS"
informOk "Unpacking image $installImg..." -n
(cd /mnt && tar xapf $installImg)
chown -R 0:0 /mnt
informOk "done"

## Make the resolver config available in the chroot
cp /etc/resolv.conf /mnt

## Generate hardware-specific configuration
#nixos-generate-config --root /mnt

## NIX path to use in the chroot
#TODO: channel might be called differently than "nixos"
export NIX_PATH=/nix/var/nix/profiles/per-user/root/channels:nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/${nixosConfigPath}

informOk "generating system configuration..."
## Starting with 18.09, nix.useSandbox defaults to true, which breaks the execution of
## nix-env in a chroot when the builder needs to be invoked because Linux does not
## allow nested chroots.
nixEnvOptions="--option sandbox false"
if [ -z $useBinaryCache ]; then
    nixEnvOptions="$nixEnvOptions --option binary-caches \"\""
fi
nixos-enter --root /mnt -c "/run/current-system/sw/bin/mv /resolv.conf /etc && \
  /run/current-system/sw/bin/nix-env $nixEnvOptions -p /nix/var/nix/profiles/system -f '<nixpkgs/nixos>' --set -A system"
informOk "...system configuration done"

informOk "activating final configuration..."
NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt \
  -c "/nix/var/nix/profiles/system/bin/switch-to-configuration boot"
informOk "...activation done"

chmod 755 /mnt

informOk "rebooting into the new system"
reboot --force
}

main "$@"
