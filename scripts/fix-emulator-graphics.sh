#!/usr/bin/env bash
set -euo pipefail
vbox=/Applications/VirtualBox.app/Contents/MacOS/VBoxManage
name=${1:-'Sailfish OS Emulator 5.1.0.11 - ARM host experiment'}
info=$("$vbox" showvminfo "$name" --machinereadable)
if ! [[ "$info" == *'VMState="poweroff"'* ]]; then
  echo 'Shut down the VM normally before applying the graphics fix.' >&2
  exit 1
fi
# This image has vboxvideo, but no vmwgfx driver for VMSVGA.
"$vbox" modifyvm "$name" --graphicscontroller vboxvga --accelerate-3d off
"$vbox" setextradata "$name" CustomVideoMode1 720x1280x32
"$vbox" setextradata "$name" GUI/LastGuestSizeHint 720,1280
"$vbox" setextradata "$name" GUI/AutoresizeGuest false
echo "Graphics configured for: $name"
