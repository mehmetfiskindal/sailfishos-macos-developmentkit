#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
vbox=/Applications/VirtualBox.app/Contents/MacOS/VBoxManage
name='Sailfish OS Emulator 5.1.0.11 - ARM host experiment'
source_disk=${1:?Usage: bash scripts/setup-emulator.sh /path/to/sailfishos.vdi}
[[ -f "$source_disk" ]] || { echo 'VDI source not found' >&2; exit 1; }
if "$vbox" showvminfo "$name" >/dev/null 2>&1; then
  echo "VM already exists: $name"
  exit 0
fi
mkdir -p "$root/emulators"
"$vbox" createvm --name "$name" --platform-architecture x86 \
  --ostype Linux26 --basefolder "$root/emulators" --register
disk="$root/emulators/$name/sailfishos.vdi"
"$vbox" clonemedium disk "$source_disk" "$disk" --format VDI
"$vbox" modifyvm "$name" --memory 2048 --cpus 1 --vram 128 \
  --firmware bios --ioapic on --x86-pae on --rtc-use-utc on \
  --graphicscontroller vboxvga --accelerate-3d off \
  --boot1 disk --boot2 none --boot3 none --boot4 none \
  --nic1 nat --nic-type1 82540EM --cable-connected1 on \
  --nat-pf1 'ssh,tcp,127.0.0.1,2223,,22' --audio-enabled off
"$vbox" storagectl "$name" --name SATA --add sata \
  --controller IntelAhci --portcount 1 --bootable on
"$vbox" storageattach "$name" --storagectl SATA --port 0 \
  --device 0 --type hdd --medium "$disk"
"$vbox" setextradata "$name" CustomVideoMode1 720x1280x32
"$vbox" setextradata "$name" GUI/LastGuestSizeHint 720,1280
"$vbox" setextradata "$name" GUI/AutoresizeGuest false
vm_dir="$root/emulators/$name"
mkdir -p "$vm_dir/ssh/root" "$vm_dir/ssh/defaultuser" "$vm_dir/vmshare" "$vm_dir/media"
if [[ ! -f "$vm_dir/sdk-key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C sailfish-emulator-local -f "$vm_dir/sdk-key"
fi
cp "$vm_dir/sdk-key.pub" "$vm_dir/ssh/root/authorized_keys"
cp "$vm_dir/sdk-key.pub" "$vm_dir/ssh/defaultuser/authorized_keys"
cat > "$vm_dir/vmshare/65-emul-wayland-ui-scale.conf" <<'CONFIG'
QT_QPA_EGLFS_SCALE=1
QT_QPA_EGLFS_WIDTH=720
QT_QPA_EGLFS_HEIGHT=1280
QT_QPA_EGLFS_PHYSICAL_WIDTH=62
QT_QPA_EGLFS_PHYSICAL_HEIGHT=111
CONFIG
cat > "$vm_dir/vmshare/device-model.txt" <<'CONFIG'
[desktop/sailfish/silica]
theme_pixel_ratio=1.25
default_allowed_orientations=11
webview_customlayoutwidth_scalingfactor=1.1
CONFIG
"$vbox" sharedfolder add "$name" --name ssh --hostpath "$vm_dir/ssh" --readonly
"$vbox" sharedfolder add "$name" --name config --hostpath "$vm_dir/vmshare" --readonly
"$vbox" sharedfolder add "$name" --name media --hostpath "$vm_dir/media"
"$vbox" showvminfo "$name" --machinereadable > "$root/emulators/config.txt"
echo "Created: $name"
