# Sailfish Emulator Experiment on Apple Silicon

On October 3, 2026, an x86 VM was created for the Sailfish OS 5.1.0.11 emulator
on VirtualBox 7.2.20. VirtualBox's experimental `VBoxInternal2/EnableX86OnArm=1`
setting was already enabled.

VM name: `Sailfish OS Emulator 5.1.0.11 - ARM host experiment`.
Files are stored in the project's `emulators/` directory and excluded from Git.
The original VDI in Downloads was not modified; it was cloned via VirtualBox.

## Setup

After extracting `sailfishos.vdi` from the archive:

```bash
bash scripts/setup-emulator.sh /path/to/sailfishos.vdi
```

The script creates a new VM; if a VM with the same name already exists, it exits
without touching the existing VM. Re-running the script is not sufficient to
update an existing VM.

Settings used: x86/Linux26, BIOS, 1 CPU, 2048 MB RAM, 128 MB VRAM, VBoxVGA,
SATA/AHCI disk. `CustomVideoMode1=720x1280x32` is required: the bootloader
requests `vga=864` (`0x360`). Without this setting, it waited at the video mode
prompt; after adding the setting, the kernel booted.

SSH port forwarding over NAT: `127.0.0.1:2223 → guest:22`.
A VM-specific ED25519 key was generated in `sdk-key`; the public key was placed
into `ssh/root/authorized_keys` and `ssh/defaultuser/authorized_keys`. The
private key is not shared with the guest.

Shared folders according to the image's systemd mount files:

- `ssh` → `/etc/ssh/authorized_keys`
- `config` → `/etc/mersdk/share`
- `media` → `/run/media/defaultuser/sdk`

Compositor screen dimensions and device model settings were added to the
`config` share.

## Starting and Graceful Shutdown

```bash
VBOX=/Applications/VirtualBox.app/Contents/MacOS/VBoxManage
VM='Sailfish OS Emulator 5.1.0.11 - ARM host experiment'
"$VBOX" startvm "$VM" --type gui
"$VBOX" controlvm "$VM" acpipowerbutton
```

When the SSH service is ready:

```bash
ssh -p 2223 \
  -i 'emulators/Sailfish OS Emulator 5.1.0.11 - ARM host experiment/sdk-key' \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=out/emulator-known-hosts \
  root@127.0.0.1
```

## Verified Behavior and Open Issues

- The VM was created and started.
- The Sailfish console showed `Sailfish OS 5.1.0.11 (Pispala)` and
  `Kernel 5.0.21-1.4.5.jolla on an i686`.
- The Guest Additions service ran in the logs.
- The graphical UI displayed output on a separate diagnostic copy.
- SSH was verified after assigning the NAT address `10.0.2.15`. Details are in
  the final section.
- After the initial VBoxVGA/virtio attempt, VMSVGA/Intel E1000 was also tried;
  under VMSVGA, the graphics service exits because it cannot find a DRM device.

The graphical console is tty7 and the login console is tty2. Switch between
them with Ctrl+Alt+F7 and Ctrl+Alt+F2. Screenshots and VM logs were saved for
diagnostics.

A separate offline diagnostic disk (`sailfish-debug.vdi`) was prepared; it
produced a bootloader error and was discontinued. The VM was re-attached to the
first working `sailfishos.vdi` disk. The debug shell was not enabled on the
active disk. Temporary offline inspection containers were cleaned up.

## Graphics Issue Diagnosis and Fix

On October 3, 2026, the live journal log showed the direct cause:

```text
lipstick: Could not find DRM device!
lipstick.service: Main process exited, code=killed, status=6/ABRT
```

Under VMSVGA, `/dev/dri` was missing. The image's kernel modules do not contain
`vmwgfx`. The available `vboxvideo` module supports VBoxVGA's `80ee:beef` PCI
device and does not bind to VMSVGA. Console output over VESA does not imply
that the Qt/EGLFS graphical session will also work.

To re-apply the fix while the VM is powered off:

```bash
bash scripts/fix-emulator-graphics.sh
```

The script's main fix:

```bash
"$VBOX" modifyvm "$VM" --graphicscontroller vboxvga --accelerate-3d off
```

On the next boot, the following results were verified:

```text
/dev/dri/card0
fb0: switching to vboxdrmfb from VESA VGA
[drm] Initialized vboxvideo 1.0.0 ... on minor 0
```

The Sailfish wallpaper and directional arrows were seen in the
`out/sailfish-first-ui.png` screenshot. Under experimental x86 emulation, this
boot took several minutes; an early black screen alone does not indicate that
the service crashed. The setup script now selects VBoxVGA as well.
The initial display hint was set to `GUI/LastGuestSizeHint=720,1280`, matching
the phone UI. A `1024,768` landscape window pushed the UI to the left and
shifted touch input. `GUI/AutoresizeGuest`, which resizes the phone screen when
the window changes, was disabled. These keys are defined in the
[VirtualBox source code](https://github.com/VirtualBox/virtualbox/blob/main/src/VBox/Frontends/VirtualBox/src/extradata/UIExtraDataDefs.cpp).

A separate native VirtualBox clone of the original disk
(`graphics-diagnostic.vdi`) was used for diagnostics. `systemd.debug_shell=1`
was enabled only on this copy. Changes were applied with an 11-sector offset
accounting for the **512-byte** partition start; the VDI header and bootloader
are preserved. This copy is not required for normal use. Live logs are located
in the VM directory's `media/` folder.

When trying to return to the original disk, the black screen appeared again.
Because live logs could not be captured on that disk, we could not verify
whether it was the same DRM error. Therefore, a separate native clone of the
working diagnostic disk, `sailfish-fixed.vdi`, was created. The boot parameter
in the clone was replaced with the equal-length `systemd.debug_shell=0` to
disable the root debug console. The old `sailfishos.vdi` and diagnostic copy
are kept as backups. The home screen screenshot from the diagnostic boot is in
`out/sailfish-first-ui.png`.

## SSH and Usable Disk

The active disk is `sailfish-session.vdi`. It is a clone of
`sailfish-fixed.vdi` with the debug shell enabled and a oneshot service that
writes the NAT address on boot.

`sdk-setup-emulan` runs before `eth0` appears, writes an empty `MAC` to the
fallback connman file, and exits, so DHCP never starts and Guest Additions
reports `Net/Count=0`. Once carrier comes up, the service configures the
address manually:

```text
10.0.2.15/24
gateway 10.0.2.2
dns 10.0.2.3
```

On October 3, 2026, SSH was verified with this address:

```text
Linux SailfishEmul 5.0.21-1.4.5.jolla #1 SMP PREEMPT Wed Apr 15 03:10:37 UTC 2026 i686 i686 i386 GNU/Linux
Sailfish OS 5.1.0.11 (Pispala)
```

```bash
ssh -p 2223 \
  -i 'emulators/Sailfish OS Emulator 5.1.0.11 - ARM host experiment/sdk-key' \
  -o IdentitiesOnly=yes \
  root@127.0.0.1
```

The shares mount properly: `ssh` → `/etc/ssh/authorized_keys`,
`config` → `/etc/mersdk/share`, and `media` → `/run/media/defaultuser/sdk`.
`/dev/dri/card0` exists and the `lipstick` process is running. The window, UI,
and touch layer must be `720x1280`. `QT_QPA_EGLFS_SCALE=1`; scale 2 assumed a
`2048x1536` touch area, while a `1024x768` landscape window pushed the
wallpaper to the left and shifted touch input. Do not switch back to VMSVGA.
Hardware settings match the setup script: VBoxVGA, 3D disabled, Intel E1000,
NAT `2223→22`.

This is an experimental x86 emulation test, separate from the ARM64 Docker
build environment. Existing ARM64 executables cannot run inside the i486
emulator.
